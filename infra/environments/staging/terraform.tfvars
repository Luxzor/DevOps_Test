# Staging: misma forma que producción, en tamaño reducido.
environment        = "staging"
vpc_cidr           = "10.20.0.0/16"
nat_gateway_mode   = "single"
desired_count      = 2
task_cpu           = 256
task_memory        = 512
log_retention_days = 14

# Producción descarga de staging las imágenes que promueve.
ecr_pull_environments = ["prod"]
