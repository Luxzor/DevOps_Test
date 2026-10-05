# Ambiente de desarrollo: barato y desechable.
environment        = "dev"
vpc_cidr           = "10.10.0.0/16"
nat_gateway_mode   = "single"
desired_count      = 1
task_cpu           = 256
task_memory        = 512
log_retention_days = 7

# Staging descarga de dev las imágenes que promueve.
ecr_pull_environments = ["staging"]
