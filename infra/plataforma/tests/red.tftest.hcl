# Network guarantees consumed by every microservice (spec RF-001, RF-002, RNF-001, RNF-007).
mock_provider "aws" {
  # The provider validates ARN formats, so mocked ARNs must look real.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-2:348364742283:log-group:/aws/apigateway/urban-alert-gateway"
    }
  }
}

override_data {
  target = data.aws_availability_zones.available
  values = {
    names = ["us-east-2a", "us-east-2b", "us-east-2c"]
  }
}

run "private_subnets_in_two_zones" {
  command = apply

  assert {
    condition     = length(aws_subnet.privada) == 2
    error_message = "Expected one private subnet per zone (2)."
  }

  assert {
    condition     = aws_subnet.privada[0].availability_zone != aws_subnet.privada[1].availability_zone
    error_message = "Private subnets must be in different availability zones."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.privada : endswith(s.cidr_block, "/20") && s.vpc_id == aws_vpc.this.id])
    error_message = "Private subnets must be /20 blocks of the platform VPC."
  }

  assert {
    condition     = alltrue([for s in concat(aws_subnet.privada, aws_subnet.publica) : !s.map_public_ip_on_launch])
    error_message = "No subnet may assign public IPs automatically."
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.20.0.0/16" && aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "The VPC must use 10.20.0.0/16 with DNS support and hostnames enabled."
  }
}

run "public_subnets_route_to_the_internet_gateway" {
  command = apply

  assert {
    condition     = aws_route.publica_internet.gateway_id == aws_internet_gateway.this.id && aws_route.publica_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "The public route table must send 0.0.0.0/0 to the internet gateway."
  }

  assert {
    condition     = length(aws_route_table_association.publica) == 2
    error_message = "Every public subnet must be associated with the public route table."
  }
}

run "default_security_group_has_no_rules" {
  command = apply

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "The default security group must have no rules."
  }
}

run "a_single_zone_is_rejected" {
  command = plan

  variables {
    numero_zonas = 1
  }

  expect_failures = [var.numero_zonas]
}
