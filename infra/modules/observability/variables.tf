variable "name" {
  description = "Prefijo de alarmas y tablero, por ejemplo tasks-api-prod."
  type        = string
}

variable "log_group_name" {
  description = "Grupo de logs de la app (logs JSON, un evento por petición)."
  type        = string
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "desired_count" {
  description = "Tareas esperadas; por debajo de esto se dispara la alarma de tareas caídas."
  type        = number
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "alarm_email" {
  description = "Correo que recibe las alarmas. null para no suscribir ninguno."
  type        = string
  default     = null
}

variable "error_threshold" {
  description = "Errores 5xx por minuto que disparan la alarma."
  type        = number
  default     = 5
}

variable "latency_threshold_ms" {
  description = "Latencia promedio (ms) por minuto que dispara la alarma."
  type        = number
  default     = 500
}

variable "enable_log_metric_filters" {
  description = "Crea las métricas de errores y latencia a partir de los logs JSON de la app."
  type        = bool
  default     = true
}
