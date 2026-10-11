# Contract with the microservices (spec RF-008; constitution P9; plan D-006).
# Names are stable: renaming or removing one breaks the consumers' pipelines.
locals {
  ssm_prefix = "/urban-alert/plataforma/"

  contrato = {
    "region"            = var.region
    "vpc-id"            = aws_vpc.this.id
    "vpc-cidr"          = aws_vpc.this.cidr_block
    "subredes-privadas" = join(",", aws_subnet.privada[*].id)
    "api-id"            = aws_apigatewayv2_api.this.id
    "api-endpoint"      = aws_apigatewayv2_api.this.api_endpoint
    "api-execution-arn" = aws_apigatewayv2_api.this.execution_arn
    "vpc-link-id"       = aws_apigatewayv2_vpc_link.this.id
    "vpc-link-sg-id"    = aws_security_group.vpc_link.id
  }
}

resource "aws_ssm_parameter" "contrato" {
  for_each = local.contrato

  name        = "${local.ssm_prefix}${each.key}"
  description = "UrbanAlert shared platform output (contract with the microservices)"
  type        = each.key == "subredes-privadas" ? "StringList" : "String"
  value       = each.value
}
