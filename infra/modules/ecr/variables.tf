variable "name" {
  description = "Nombre del repositorio de imágenes."
  type        = string
}

variable "pull_account_ids" {
  description = "Cuentas que pueden descargar imágenes de este repositorio (promoción entre ambientes)."
  type        = list(string)
  default     = []
}

variable "max_tagged_images" {
  description = "Cuántas imágenes etiquetadas se conservan. Las más viejas se borran solas."
  type        = number
  default     = 30
}

variable "force_delete" {
  description = "Permite destruir el repositorio con imágenes dentro. true solo en ambientes desechables."
  type        = bool
  default     = false
}
