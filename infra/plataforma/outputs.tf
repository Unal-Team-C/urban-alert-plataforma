# Mirrors the SSM contract for the provision workflow summary; consumers read SSM, not this state.
output "ssm_prefix" {
  description = "Prefix of the SSM parameters consumed by the microservices."
  value       = local.ssm_prefix
}

output "region" {
  description = "AWS region of the platform."
  value       = var.region
}

output "vpc_id" {
  description = "ID of the shared VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the shared VPC."
  value       = aws_vpc.this.cidr_block
}

output "subredes_privadas" {
  description = "Private subnet IDs, in zone order."
  value       = aws_subnet.privada[*].id
}

output "api_id" {
  description = "ID of the shared HTTP API."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Public HTTPS URL of the shared gateway."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_execution_arn" {
  description = "Execution ARN of the gateway, used to grant execute-api:Invoke on internal routes."
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "vpc_link_id" {
  description = "ID of the VPC link towards the internal Express load balancers."
  value       = aws_apigatewayv2_vpc_link.this.id
}

output "vpc_link_sg_id" {
  description = "Security group of the VPC link."
  value       = aws_security_group.vpc_link.id
}
