# Provisions a VPC and two public subnets when the caller omits aws.vpc_id /
# aws.primary_subnet_id / aws.secondary_subnet_id. Everything here reads var.aws
# directly (never local.cloud_args) so it does not cycle with the resolved ids
# that locals.tf resolves for the cluster consumers.

locals {
  network_vpc_cidr = trimspace(tostring(try(var.aws.vpc_cidr, ""))) != "" ? var.aws.vpc_cidr : "10.0.0.0/16"

  network_subnets = local.create_network ? {
    primary   = 0
    secondary = 1
  } : {}
}

data "aws_availability_zones" "available" {
  count = local.create_network ? 1 : 0
  state = "available"
}

resource "aws_vpc" "main" {
  count                = local.create_network ? 1 : 0
  cidr_block           = local.network_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "gw" {
  count  = local.create_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  count  = local.create_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw[0].id
  }

  tags = { Name = "${local.name_prefix}-public-rt" }
}

# map_public_ip_on_launch lets Karpenter nodes reach ECR/S3/DynamoDB over the IGW
# without a NAT gateway. The kubernetes.io/role/elb tags let the AWS Load Balancer
# Controller auto-discover these subnets; omit them and the ingress NLBs never
# provision — a failure that only surfaces after apply succeeds.
resource "aws_subnet" "zipline" {
  for_each = local.network_subnets

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = cidrsubnet(local.network_vpc_cidr, 4, each.value)
  availability_zone       = data.aws_availability_zones.available[0].names[each.value]
  map_public_ip_on_launch = true

  tags = {
    Name                              = "${local.name_prefix}-subnet-${each.key}"
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_route_table_association" "public" {
  for_each = local.network_subnets

  subnet_id      = aws_subnet.zipline[each.key].id
  route_table_id = aws_route_table.public[0].id
}
