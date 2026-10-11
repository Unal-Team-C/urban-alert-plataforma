# Platform contract (spec RF-008): fails with ParameterNotFound when the platform is not provisioned.
data "aws_ssm_parameter" "api_id" {
  name = "/urban-alert/plataforma/api-id"
}

data "aws_ssm_parameter" "vpc_link_id" {
  name = "/urban-alert/plataforma/vpc-link-id"
}

data "aws_ssm_parameter" "api_execution_arn" {
  name = "/urban-alert/plataforma/api-execution-arn"
}

# Public route -> path of the service (convention of UrbanAlert/infrastructure/README.md, spec RF-018).
# "NONE" routes are public; "AWS_IAM" routes are internal, only for other microservices (spec RF-019).
locals {
  rutas = {
    reports = {
      route_key = "GET /api/v1/geoespacial/reports"
      metodo    = "GET"
      ruta      = "/api/v1/geospatial/reports"
      auth      = "NONE"
    }
    coordinate = {
      route_key = "GET /api/v1/geoespacial/coordinates/{id}"
      metodo    = "GET"
      ruta      = "/api/v1/geospatial/coordinates/$request.path.id"
      auth      = "NONE"
    }
    assign = {
      route_key = "POST /api/v1/geoespacial/coordinates"
      metodo    = "POST"
      ruta      = "/api/v1/geospatial/coordinates"
      auth      = "AWS_IAM"
    }
  }
}

# The Express load balancer routes by Host header: without overwriting Host with the service endpoint
# the request matches no listener rule and returns 404 (research R-1, plan D-005).
resource "aws_apigatewayv2_integration" "this" {
  for_each = local.rutas

  api_id                 = data.aws_ssm_parameter.api_id.value
  integration_type       = "HTTP_PROXY"
  integration_method     = each.value.metodo
  integration_uri        = var.express_listener_arn
  connection_type        = "VPC_LINK"
  connection_id          = data.aws_ssm_parameter.vpc_link_id.value
  payload_format_version = "1.0"

  tls_config {
    server_name_to_verify = var.express_endpoint
  }

  request_parameters = merge(
    { for nombre, valor in var.cabeceras_fijas : "overwrite:header.${nombre}" => valor },
    {
      "overwrite:header.host" = var.express_endpoint
      "overwrite:path"        = each.value.ruta
    },
  )
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.rutas

  api_id             = data.aws_ssm_parameter.api_id.value
  route_key          = each.value.route_key
  authorization_type = each.value.auth
  target             = "integrations/${aws_apigatewayv2_integration.this[each.key].id}"
}
