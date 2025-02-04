// Establishes the network for the kubernetes cluster
resource "aws_vpc" "main" {
  cidr_block           = "172.31.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "zipline-${var.customer_name}-vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.31.0.0/20"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
}

resource "aws_security_group" "elb" {
  description = "Security group for Zipline Kubernetes ELB"
  vpc_id      = aws_vpc.main.id

  tags = {
    "kubernetes.io/cluster/zipline_${var.customer_name}_eks" = "owned"
  }
  tags_all = {
    "kubernetes.io/cluster/zipline_${var.customer_name}_eks" = "owned"
  }

}

resource "aws_vpc_security_group_ingress_rule" "tcp" {
  security_group_id = aws_security_group.elb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 3000
  ip_protocol = "tcp"
  to_port     = 3000
}

resource "aws_vpc_security_group_ingress_rule" "icmp" {
  security_group_id = aws_security_group.elb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 3
  ip_protocol = "icmp"
  to_port     = 4
}


resource "aws_security_group" "emr_sg" {
  name        = "zipline-${var.customer_name}-sg"
  description = "Security group for Zipline"
  vpc_id      = aws_vpc.main.id

  tags = {
    "kubernetes.io/cluster/zipline_${var.customer_name}_eks" = "owned"
  }
  tags_all = {
    "kubernetes.io/cluster/zipline_${var.customer_name}_eks" = "owned"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_access" {
  security_group_id = aws_security_group.emr_sg.id

  ip_protocol                  = "-1"
  from_port                    = 0
  to_port                      = 0
  referenced_security_group_id = aws_security_group.elb.id
}

data "aws_ec2_managed_prefix_list" "ec2_instance_connect" {
  filter {
    name   = "prefix-list-name"
    values = ["com.amazonaws.${var.region}.ec2-instance-connect"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "instance_connect" {
  security_group_id = aws_security_group.emr_sg.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  prefix_list_id    = data.aws_ec2_managed_prefix_list.ec2_instance_connect.id
}


resource "aws_vpc_security_group_egress_rule" "allow_access" {
  security_group_id = aws_security_group.emr_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "r" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.main.id
  route_table_id = aws_route_table.r.id
}

output "main_subnet_id" {
  value = aws_subnet.main.id
}