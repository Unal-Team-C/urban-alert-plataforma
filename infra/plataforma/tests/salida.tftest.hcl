# Egress of the private subnets (spec RF-003, RNF-004; plan D-003).
mock_provider "aws" {}

override_data {
  target = data.aws_availability_zones.available
  values = {
    names = ["us-east-2a", "us-east-2b", "us-east-2c"]
  }
}

run "single_shared_nat_gateway_by_default" {
  command = apply

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && aws_nat_gateway.this[0].subnet_id == aws_subnet.publica[0].id
    error_message = "By default there must be one NAT gateway, in the first public subnet."
  }

  assert {
    condition     = alltrue([for r in aws_route.privada_salida : r.destination_cidr_block == "0.0.0.0/0" && r.nat_gateway_id == aws_nat_gateway.this[0].id])
    error_message = "Every private route table must send 0.0.0.0/0 to the shared NAT gateway."
  }

  assert {
    condition     = aws_nat_gateway.this[0].allocation_id == aws_eip.nat[0].id
    error_message = "The NAT gateway must use its elastic IP."
  }
}

run "one_nat_gateway_per_zone" {
  command = apply

  variables {
    nat_por_zona = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2 && length(aws_eip.nat) == 2
    error_message = "nat_por_zona = true must create one NAT gateway and one elastic IP per zone."
  }

  assert {
    condition     = alltrue([for i in range(2) : aws_route.privada_salida[i].nat_gateway_id == aws_nat_gateway.this[i].id && aws_nat_gateway.this[i].subnet_id == aws_subnet.publica[i].id])
    error_message = "Each private route table must use the NAT gateway of its own zone."
  }
}

run "s3_gateway_endpoint_on_private_route_tables" {
  command = apply

  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" && aws_vpc_endpoint.s3.service_name == "com.amazonaws.us-east-2.s3"
    error_message = "The S3 endpoint must be a gateway endpoint for us-east-2."
  }

  assert {
    condition     = toset(aws_vpc_endpoint.s3.route_table_ids) == toset(aws_route_table.privada[*].id)
    error_message = "The S3 endpoint must be associated with every private route table."
  }
}

run "private_subnets_reach_the_internet_only_through_nat" {
  command = apply

  assert {
    condition     = alltrue([for r in aws_route.privada_salida : r.gateway_id == null && r.nat_gateway_id != null])
    error_message = "Private route tables must reach the internet only through a NAT gateway."
  }

  assert {
    condition     = alltrue([for i in range(2) : aws_route_table_association.privada[i].subnet_id == aws_subnet.privada[i].id && aws_route_table_association.privada[i].route_table_id == aws_route_table.privada[i].id])
    error_message = "Each private subnet must use the private route table of its zone."
  }
}
