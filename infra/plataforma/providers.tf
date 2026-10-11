provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "urban-alert"
      ManagedBy = "terraform"
      Stack     = "plataforma"
    }
  }
}
