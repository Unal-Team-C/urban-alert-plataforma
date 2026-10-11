# Integration pattern of a microservice behind the shared gateway (spec RF-006, RF-018, RF-019; plan D-005).
mock_provider "aws" {}

variables {
  express_endpoint     = "geoespacial-abc123.ecs.us-east-2.on.aws"
  express_listener_arn = "arn:aws:elasticloadbalancing:us-east-2:348364742283:listener/app/ecs-express-gateway-alb-1/0a1b2c/3d4e5f"
  rol_llamante         = "urban-alert-reportes-task-role"
}

override_data {
  target = data.aws_ssm_parameter.api_id
  values = { value = "api0test" }
}

override_data {
  target = data.aws_ssm_parameter.vpc_link_id
  values = { value = "vl0test" }
}

override_data {
  target = data.aws_ssm_parameter.api_execution_arn
  values = { value = "arn:aws:execute-api:us-east-2:348364742283:api0test" }
}

run "integrations_reach_the_express_listener_with_its_host" {
  command = apply

  assert {
    condition = alltrue([for i in aws_apigatewayv2_integration.this :
      i.integration_type == "HTTP_PROXY" && i.connection_type == "VPC_LINK" && i.connection_id == "vl0test"
    && i.integration_uri == var.express_listener_arn && i.payload_format_version == "1.0" && i.api_id == "api0test"])
    error_message = "Every integration must be an HTTP proxy through the platform VPC link to the Express listener, payload 1.0."
  }

  assert {
    condition = alltrue([for i in aws_apigatewayv2_integration.this :
    i.tls_config[0].server_name_to_verify == var.express_endpoint && i.request_parameters["overwrite:header.host"] == var.express_endpoint])
    error_message = "Every integration must send the Express endpoint as Host and verify it as TLS server name (host-header routing)."
  }
}

run "public_paths_are_rewritten_to_the_service_paths" {
  command = apply

  assert {
    condition     = aws_apigatewayv2_integration.this["reports"].request_parameters["overwrite:path"] == "/api/v1/geospatial/reports"
    error_message = "GET /api/v1/geoespacial/reports must reach /api/v1/geospatial/reports."
  }

  assert {
    condition     = aws_apigatewayv2_integration.this["coordinate"].request_parameters["overwrite:path"] == "/api/v1/geospatial/coordinates/$request.path.id"
    error_message = "The coordinate id must be carried into the service path."
  }
}

run "routes_publish_only_their_methods" {
  command = apply

  assert {
    condition = toset([for r in aws_apigatewayv2_route.this : r.route_key]) == toset([
      "GET /api/v1/geoespacial/reports",
      "GET /api/v1/geoespacial/coordinates/{id}",
      "POST /api/v1/geoespacial/coordinates",
    ])
    error_message = "The example must publish exactly the three geoespacial routes."
  }

  assert {
    condition     = alltrue([for k, r in aws_apigatewayv2_route.this : r.target == "integrations/${aws_apigatewayv2_integration.this[k].id}"])
    error_message = "Each route must target its own integration."
  }
}

run "internal_route_requires_iam_and_only_the_caller_may_invoke_it" {
  command = apply

  assert {
    condition     = aws_apigatewayv2_route.this["assign"].authorization_type == "AWS_IAM"
    error_message = "The internal POST route must require IAM (SigV4) authorization."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["reports"].authorization_type == "NONE" && aws_apigatewayv2_route.this["coordinate"].authorization_type == "NONE"
    error_message = "Public routes must not require authorization (the gateway only routes, spec RF-017)."
  }

  assert {
    condition = (aws_iam_role_policy.invocar_rutas_internas.role == "urban-alert-reportes-task-role"
      && jsondecode(aws_iam_role_policy.invocar_rutas_internas.policy).Statement[0].Action == "execute-api:Invoke"
      && jsondecode(aws_iam_role_policy.invocar_rutas_internas.policy).Statement[0].Resource == [
        "arn:aws:execute-api:us-east-2:348364742283:api0test/$default/POST/api/v1/geoespacial/coordinates",
    ])
    error_message = "The caller role may only invoke the internal route."
  }
}

run "fixed_headers_are_added_towards_the_service" {
  command = apply

  variables {
    cabeceras_fijas = { "X-Urban-Gateway-Key" = "test-key" }
  }

  assert {
    condition     = alltrue([for i in aws_apigatewayv2_integration.this : nonsensitive(i.request_parameters["overwrite:header.X-Urban-Gateway-Key"]) == "test-key"])
    error_message = "Fixed headers must be set on every integration of the service."
  }
}

run "endpoint_with_scheme_is_rejected" {
  command = plan

  variables {
    express_endpoint = "https://geoespacial-abc123.ecs.us-east-2.on.aws"
  }

  expect_failures = [var.express_endpoint]
}
