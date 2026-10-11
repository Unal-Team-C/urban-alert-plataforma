variable "region" {
  description = "AWS region of the platform."
  type        = string
  default     = "us-east-2"
}

variable "express_endpoint" {
  description = "Host of the Express service (ingress_paths[0].endpoint of aws_ecs_express_gateway_service), without https://."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.express_endpoint))
    error_message = "express_endpoint must be a bare host name such as geoespacial-abc.ecs.us-east-2.on.aws (no scheme, no path)."
  }
}

variable "express_listener_arn" {
  description = "ARN of the 443 listener of the Express load balancer (scripts/buscar-listener-express.sh)."
  type        = string

  validation {
    condition     = startswith(var.express_listener_arn, "arn:aws:elasticloadbalancing:") && strcontains(var.express_listener_arn, ":listener/app/")
    error_message = "express_listener_arn must be the ARN of an Application Load Balancer listener."
  }
}

variable "rol_llamante" {
  description = "Name of the task role of the microservice allowed to call the internal routes (e.g. the Reportes task role)."
  type        = string
}

variable "cabeceras_fijas" {
  description = "Fixed headers the gateway adds towards the service (e.g. X-Urban-Gateway-Key for Auditoria)."
  type        = map(string)
  default     = {}
  sensitive   = true
}
