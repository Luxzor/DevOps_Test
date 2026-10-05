# Producción: alta disponibilidad y protecciones contra borrados accidentales.
environment             = "prod"
vpc_cidr                = "10.30.0.0/16"
nat_gateway_mode        = "per_az"
desired_count           = 2
task_cpu                = 512
task_memory             = 1024
log_retention_days      = 90
alb_deletion_protection = true
error_threshold         = 3

# alarm_email = "equipo@example.com"
