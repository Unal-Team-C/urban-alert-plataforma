# Egress of the private subnets through managed NAT gateways (spec RF-003; plan D-003).
# The microservices call each other through the public gateway URL, so the private subnets need internet egress.
locals {
  numero_nat = var.nat_por_zona ? var.numero_zonas : 1
}

resource "aws_eip" "nat" {
  count = local.numero_nat

  domain = "vpc"

  tags = {
    Name = "${var.nombre}-nat-${local.zonas[count.index]}"
  }
}

resource "aws_nat_gateway" "this" {
  count = local.numero_nat

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.publica[count.index].id

  tags = {
    Name = "${var.nombre}-nat-${local.zonas[count.index]}"
  }

  depends_on = [aws_internet_gateway.this]
}

# One route table per zone, so switching nat_por_zona only changes the route targets.
resource "aws_route_table" "privada" {
  count = var.numero_zonas

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.nombre}-privada-${local.zonas[count.index]}"
  }
}

resource "aws_route" "privada_salida" {
  count = var.numero_zonas

  route_table_id         = aws_route_table.privada[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.nat_por_zona ? count.index : 0].id
}

resource "aws_route_table_association" "privada" {
  count = var.numero_zonas

  subnet_id      = aws_subnet.privada[count.index].id
  route_table_id = aws_route_table.privada[count.index].id
}

# Free gateway endpoint: ECR image layers are served from S3 and skip the NAT data charge.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.privada[*].id

  tags = {
    Name = "${var.nombre}-s3"
  }
}
