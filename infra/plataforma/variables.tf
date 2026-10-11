variable "region" {
  description = "AWS region of the platform."
  type        = string
  default     = "us-east-2"
}

variable "nombre" {
  description = "Name prefix for every platform resource."
  type        = string
  default     = "urban-alert"

  validation {
    condition     = startswith(var.nombre, "urban-alert")
    error_message = "nombre must start with urban-alert (bootstrap policies are scoped to that prefix)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the shared VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 16
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix of /16 or larger (subnets are /20 and /24)."
  }
}

variable "numero_zonas" {
  description = "Number of availability zones with a private and a public subnet."
  type        = number
  default     = 2

  validation {
    condition     = var.numero_zonas >= 2 && var.numero_zonas <= 4
    error_message = "numero_zonas must be between 2 and 4: load balancers and RDS subnet groups need at least 2 zones."
  }
}

variable "nat_por_zona" {
  description = "true: one NAT Gateway per zone (zone-resilient egress, higher cost); false: a single shared NAT Gateway."
  type        = bool
  default     = false
}

variable "cors_origenes" {
  description = "Origins allowed by the gateway CORS configuration."
  type        = list(string)
  default     = ["*"]

  validation {
    condition     = length(var.cors_origenes) > 0
    error_message = "cors_origenes must contain at least one origin."
  }
}

variable "limite_tasa" {
  description = "Default steady-state request rate limit of the gateway (requests per second)."
  type        = number
  default     = 50

  validation {
    condition     = var.limite_tasa > 0
    error_message = "limite_tasa must be greater than 0."
  }
}

variable "limite_rafaga" {
  description = "Default burst limit of the gateway (requests)."
  type        = number
  default     = 100

  validation {
    condition     = var.limite_rafaga >= var.limite_tasa
    error_message = "limite_rafaga must be greater than or equal to limite_tasa."
  }
}

variable "retencion_logs_dias" {
  description = "Retention of the gateway access logs, in days (spec RNF-006: at least 30)."
  type        = number
  default     = 30

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retencion_logs_dias)
    error_message = "retencion_logs_dias must be a CloudWatch Logs retention value of at least 30 days."
  }
}

variable "permitir_reemplazo_compartido" {
  description = "Set to true in a commit to allow a plan that deletes or replaces shared resources (scripts/guard-plan.sh, spec RF-013)."
  type        = bool
  default     = false
}
