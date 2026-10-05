variable "target" {
  description = "Dónde se despliega: local (emulador) o aws (cuentas reales). Ver infra/targets."
  type        = string
  default     = "local"

  validation {
    condition     = contains(["local", "aws"], var.target)
    error_message = "target debe ser local o aws."
  }
}

variable "environment" {
  description = "Nombre del ambiente: dev, staging o prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser dev, staging o prod."
  }
}

variable "project" {
  type    = string
  default = "tasks-api"
}

variable "vpc_cidr" {
  type = string
}

variable "nat_gateway_mode" {
  type    = string
  default = "single"
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "alarm_email" {
  description = "Correo para las alarmas; null para no suscribir."
  type        = string
  default     = null
}

variable "error_threshold" {
  type    = number
  default = 5
}

variable "alb_deletion_protection" {
  type    = bool
  default = false
}

variable "certificate_arn" {
  description = "Certificado ACM para HTTPS. Requiere un dominio; null en la simulación."
  type        = string
  default     = null
}

variable "ecr_pull_environments" {
  description = "Ambientes que pueden descargar imágenes de este (el siguiente en la promoción)."
  type        = list(string)
  default     = []
}
