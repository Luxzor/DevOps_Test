variable "target" {
  type    = string
  default = "local"

  validation {
    condition     = contains(["local", "aws"], var.target)
    error_message = "target debe ser local o aws."
  }
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser dev, staging o prod."
  }
}

variable "project" {
  type    = string
  default = "tasks-api"
}
