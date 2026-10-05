variable "name" {
  description = "Prefijo de los nombres (máximo 24 caracteres por el límite del ALB)."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "listener_port" {
  description = "Puerto HTTP del listener. 80 en AWS; en el emulador se usa 8080."
  type        = number
  default     = 80
}

variable "certificate_arn" {
  description = "Certificado de ACM. Si se define, se abre HTTPS (443) y HTTP redirige a HTTPS."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Puerto del contenedor hacia el que el ALB envía el tráfico."
  type        = number
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "deletion_protection" {
  description = "Impide borrar el ALB por error. true en producción."
  type        = bool
  default     = false
}
