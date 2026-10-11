# Reference configuration for the microservices (plan D-010). It is validated and tested in this
# repository but never applied from here: each microservice copies what it needs into its own stack.
terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}
