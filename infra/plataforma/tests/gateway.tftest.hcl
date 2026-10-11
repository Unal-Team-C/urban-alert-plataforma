# Shared gateway and its private link (spec RF-004, RF-005, RF-007, RF-015, RF-017, RNF-005, RNF-006).
mock_provider "aws" {}

override_data {
  target = data.aws_availability_zones.available
  values = {
    names = ["us-east-2a", "us-east-2b", "us-east-2c"]
  }
}

run "http_api_only_routes" {
  command = apply

  assert {
    condition     = aws_apigatewayv2_api.this.protocol_type == "HTTP" && aws_apigatewayv2_api.this.name == "urban-alert-gateway"
    error_message = "The gateway must be an HTTP API named urban-alert-gateway."
  }

  assert {
    condition     = aws_apigatewayv2_api.this.target == null && aws_apigatewayv2_api.this.route_key == null
    error_message = "The platform must not create a default route: unregistered paths must return 404."
  }

  assert {
    condition     = !aws_apigatewayv2_api.this.disable_execute_api_endpoint
    error_message = "The execute-api endpoint is the public URL of the gateway and must stay enabled."
  }
}

run "cors_without_credentials" {
  command = apply

  assert {
    condition     = aws_apigatewayv2_api.this.cors_configuration[0].allow_credentials == false && toset(aws_apigatewayv2_api.this.cors_configuration[0].allow_origins) == toset(["*"])
    error_message = "CORS must allow the configured origins without credentials."
  }
}

run "default_stage_with_throttling_and_access_logs" {
  command = apply

  assert {
    condition     = aws_apigatewayv2_stage.default.name == "$default" && aws_apigatewayv2_stage.default.auto_deploy
    error_message = "The gateway must use an auto-deployed $default stage."
  }

  assert {
    condition     = aws_apigatewayv2_stage.default.default_route_settings[0].throttling_rate_limit == 50 && aws_apigatewayv2_stage.default.default_route_settings[0].throttling_burst_limit == 100
    error_message = "The default stage must throttle at 50 rps with a burst of 100."
  }

  assert {
    condition     = aws_apigatewayv2_stage.default.access_log_settings[0].destination_arn == aws_cloudwatch_log_group.gateway.arn
    error_message = "Access logs must go to the gateway log group."
  }

  assert {
    condition = alltrue([for k in ["requestId", "requestTime", "httpMethod", "routeKey", "path", "status", "responseLatency", "integrationLatency"] :
    contains(keys(jsondecode(aws_apigatewayv2_stage.default.access_log_settings[0].format)), k)])
    error_message = "The access log format must be JSON with request id, time, method, route, path, status and latencies."
  }

  assert {
    condition     = aws_cloudwatch_log_group.gateway.name == "/aws/apigateway/urban-alert-gateway" && aws_cloudwatch_log_group.gateway.retention_in_days == 30
    error_message = "Access logs must be kept 30 days in /aws/apigateway/urban-alert-gateway."
  }
}

run "short_log_retention_is_rejected" {
  command = plan

  variables {
    retencion_logs_dias = 7
  }

  expect_failures = [var.retencion_logs_dias]
}

run "vpc_link_in_private_subnets_with_https_egress_only" {
  command = apply

  assert {
    condition     = toset(aws_apigatewayv2_vpc_link.this.subnet_ids) == toset(aws_subnet.privada[*].id)
    error_message = "The VPC link must have interfaces in every private subnet."
  }

  assert {
    condition     = toset(aws_apigatewayv2_vpc_link.this.security_group_ids) == toset([aws_security_group.vpc_link.id])
    error_message = "The VPC link must use its own security group."
  }

  assert {
    condition     = length(aws_security_group.vpc_link.ingress) == 0
    error_message = "The VPC link security group must not accept inbound traffic."
  }

  assert {
    condition = (aws_vpc_security_group_egress_rule.vpc_link_https.security_group_id == aws_security_group.vpc_link.id
      && aws_vpc_security_group_egress_rule.vpc_link_https.ip_protocol == "tcp"
      && aws_vpc_security_group_egress_rule.vpc_link_https.from_port == 443
      && aws_vpc_security_group_egress_rule.vpc_link_https.to_port == 443
    && aws_vpc_security_group_egress_rule.vpc_link_https.cidr_ipv4 == aws_vpc.this.cidr_block)
    error_message = "The VPC link may only send HTTPS (443) to the VPC."
  }
}
