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


resource "aws_security_group" "allow_access" {
  description = "Security group for Zipline"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
    security_groups = [
      aws_security_group.elb.id
    ]
    self = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  depends_on = [aws_subnet.main]

  lifecycle {
    ignore_changes = [
      ingress,
      egress,
    ]
  }

  tags = {
    "kubernetes.io/cluster/zipline_${var.customer_name}_eks" = "owned"
  }
  tags_all = {
    "kubernetes.io/cluster/zipline_${var.customer_name}_eks" = "owned"
  }
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
