# Access logs of the shared gateway (spec RF-015, RNF-006).
resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/aws/apigateway/${var.nombre}-gateway"
  retention_in_days = var.retencion_logs_dias
}
