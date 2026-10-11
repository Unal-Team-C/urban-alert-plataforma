# Shared HTTP API: the only public entry point of the microservices (spec RF-004; plan D-004).
# The platform creates no routes: each microservice registers its own integrations and routes,
# and any unregistered path returns 404 (spec RF-007). No authorizer: the gateway only routes (spec RF-017).
resource "aws_apigatewayv2_api" "this" {
  name          = "${var.nombre}-gateway"
  protocol_type = "HTTP"
  description   = "Shared entry point of the UrbanAlert microservices"

  # The default execute-api URL is the public address of the platform (no custom domain, spec §8).
  disable_execute_api_endpoint = false

  cors_configuration {
    allow_origins     = var.cors_origenes
    allow_methods     = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers     = ["content-type", "authorization", "x-amz-date", "x-amz-security-token"]
    allow_credentials = false
    max_age           = 3600
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.limite_tasa
    throttling_burst_limit = var.limite_rafaga
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.gateway.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      ip                      = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      httpMethod              = "$context.httpMethod"
      routeKey                = "$context.routeKey"
      path                    = "$context.path"
      status                  = "$context.status"
      protocol                = "$context.protocol"
      responseLength          = "$context.responseLength"
      responseLatency         = "$context.responseLatency"
      integrationLatency      = "$context.integrationLatency"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }
}

# The VPC link only opens connections towards the internal Express load balancers (HTTPS listener).
resource "aws_security_group" "vpc_link" {
  name        = "${var.nombre}-vpc-link"
  description = "API Gateway VPC link: HTTPS to the internal load balancers of the VPC"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.nombre}-vpc-link"
  }
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_https" {
  security_group_id = aws_security_group.vpc_link.id
  description       = "HTTPS to the internal Express load balancers"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = aws_vpc.this.cidr_block
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.nombre}-vpc-link"
  subnet_ids         = aws_subnet.privada[*].id
  security_group_ids = [aws_security_group.vpc_link.id]
}
