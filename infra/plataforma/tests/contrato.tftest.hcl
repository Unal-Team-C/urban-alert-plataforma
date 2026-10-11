# Outputs published for the microservices: a stable contract (spec RF-008, constitution P9).
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

run "ssm_parameters_have_the_contract_names" {
  command = apply

  assert {
    condition = toset([for p in aws_ssm_parameter.contrato : p.name]) == toset([
      "/urban-alert/plataforma/region",
      "/urban-alert/plataforma/vpc-id",
      "/urban-alert/plataforma/vpc-cidr",
      "/urban-alert/plataforma/subredes-privadas",
      "/urban-alert/plataforma/api-id",
      "/urban-alert/plataforma/api-endpoint",
      "/urban-alert/plataforma/api-execution-arn",
      "/urban-alert/plataforma/vpc-link-id",
      "/urban-alert/plataforma/vpc-link-sg-id",
    ])
    error_message = "The SSM parameters must be exactly the nine names of plan §7."
  }
}

run "ssm_parameters_have_the_right_values" {
  command = apply

  assert {
    condition = (aws_ssm_parameter.contrato["region"].value == "us-east-2"
      && aws_ssm_parameter.contrato["vpc-id"].value == aws_vpc.this.id
      && aws_ssm_parameter.contrato["vpc-cidr"].value == "10.20.0.0/16"
      && aws_ssm_parameter.contrato["api-id"].value == aws_apigatewayv2_api.this.id
      && aws_ssm_parameter.contrato["api-endpoint"].value == aws_apigatewayv2_api.this.api_endpoint
      && aws_ssm_parameter.contrato["api-execution-arn"].value == aws_apigatewayv2_api.this.execution_arn
      && aws_ssm_parameter.contrato["vpc-link-id"].value == aws_apigatewayv2_vpc_link.this.id
    && aws_ssm_parameter.contrato["vpc-link-sg-id"].value == aws_security_group.vpc_link.id)
    error_message = "Each SSM parameter must hold the identifier of its resource."
  }

  assert {
    condition = (aws_ssm_parameter.contrato["subredes-privadas"].type == "StringList"
    && aws_ssm_parameter.contrato["subredes-privadas"].value == join(",", aws_subnet.privada[*].id))
    error_message = "subredes-privadas must be a StringList with the private subnet ids in zone order."
  }

  assert {
    condition     = alltrue([for k, p in aws_ssm_parameter.contrato : k == "subredes-privadas" || p.type == "String"])
    error_message = "Every other parameter must be a plain String."
  }
}

run "terraform_outputs_mirror_the_contract" {
  command = apply

  assert {
    condition     = output.ssm_prefix == "/urban-alert/plataforma/" && output.vpc_id == aws_vpc.this.id && output.api_endpoint == aws_apigatewayv2_api.this.api_endpoint
    error_message = "Terraform outputs must expose the SSM prefix and the main identifiers for the workflow summary."
  }

  assert {
    condition     = output.subredes_privadas == aws_subnet.privada[*].id && output.vpc_link_id == aws_apigatewayv2_vpc_link.this.id
    error_message = "Terraform outputs must expose the private subnets and the VPC link."
  }
}
