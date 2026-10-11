data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  zonas = slice(sort(data.aws_availability_zones.available.names), 0, var.numero_zonas)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.nombre}-vpc"
  }

  lifecycle {
    precondition {
      condition     = var.numero_zonas <= length(data.aws_availability_zones.available.names)
      error_message = "numero_zonas exceeds the availability zones of the region."
    }
  }
}

# Private subnets (/20) host the Express load balancers, the tasks and the VPC link interfaces (plan D-002).
resource "aws_subnet" "privada" {
  count = var.numero_zonas

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.zonas[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.nombre}-privada-${local.zonas[count.index]}"
    Tier = "privada"
  }
}

# Public subnets (/24) only hold the NAT gateways; no microservice is deployed here (spec RF-002).
resource "aws_subnet" "publica" {
  count = var.numero_zonas

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 240 + count.index)
  availability_zone       = local.zonas[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.nombre}-publica-${local.zonas[count.index]}"
    Tier = "publica"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.nombre}-igw"
  }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.nombre}-publica"
  }
}

resource "aws_route" "publica_internet" {
  route_table_id         = aws_route_table.publica.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "publica" {
  count = var.numero_zonas

  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# Without ingress/egress blocks Terraform removes every rule of the default security group (plan D-012).
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.nombre}-default-sin-reglas"
  }
}
