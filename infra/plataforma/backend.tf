# Remote state shared by the provision and deprovision workflows (spec RF-009).
# The bucket is a bootstrap resource created by hand (infra/bootstrap/README.md).
terraform {
  backend "s3" {
    bucket       = "urban-alert-tfstate-348364742283"
    key          = "plataforma/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
