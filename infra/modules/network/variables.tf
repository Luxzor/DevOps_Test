variable "name" {
  description = "Prefijo de los nombres de los recursos."
  type        = string
}

variable "cidr_block" {
  description = "Rango de direcciones de la VPC."
  type        = string
}

variable "availability_zones" {
  description = "Zonas de disponibilidad. Una subred pública y una privada por zona."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Subredes públicas (solo el balanceador y el NAT)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Subredes privadas, donde corren las tareas de ECS."
  type        = list(string)
}

variable "nat_gateway_mode" {
  description = "single: un NAT compartido (barato, dev). per_az: uno por zona (alta disponibilidad, prod)."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode debe ser single o per_az."
  }
}

variable "flow_logs_retention_days" {
  description = "Retención de los VPC Flow Logs en CloudWatch."
  type        = number
  default     = 30
}
