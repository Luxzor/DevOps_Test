variable "name" {
  description = "Prefijo de los nombres, por ejemplo tasks-api-dev."
  type        = string
}

variable "service_name" {
  description = "Nombre del servicio de ECS (estable entre ambientes, lo usan los workflows)."
  type        = string
}

variable "container_name" {
  description = "Nombre del contenedor dentro de la definición de tarea."
  type        = string
  default     = "app"
}

variable "image_repository_url" {
  type = string
}

variable "image_tag" {
  description = "Etiqueta de la imagen con la que Terraform registra la definición de tarea."
  type        = string
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "cpu" {
  description = "Unidades de CPU de la tarea Fargate (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memoria de la tarea en MiB; debe ser compatible con el valor de cpu."
  type        = number
  default     = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "environment_variables" {
  description = "Variables de entorno no sensibles del contenedor."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Variables sensibles: nombre de la variable => ARN en Secrets Manager o SSM."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "task_role_policies" {
  description = "Políticas IAM (nombre => JSON) con los permisos del código de la app."
  type        = map(string)
  default     = {}
}

variable "readonly_root_filesystem" {
  description = "Monta el sistema de archivos del contenedor en solo lectura (endurecimiento)."
  type        = bool
  default     = true
}
