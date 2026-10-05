locals {
  target   = jsondecode(file("${path.module}/../../targets/${var.target}.json"))
  env      = local.target.environments[var.environment]
  is_local = var.target == "local"
  name     = "${var.project}-${var.environment}"
  azs      = ["${local.target.region}a", "${local.target.region}b"]

  # Parámetros que comparte la infraestructura con el pipeline de CD.
  ssm_prefix = "/${var.project}/${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name                 = local.name
  cidr_block           = var.vpc_cidr
  availability_zones   = local.azs
  public_subnet_cidrs  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  nat_gateway_mode     = var.nat_gateway_mode
}

module "ecr" {
  source = "../../modules/ecr"

  name             = var.project
  pull_account_ids = [for e in var.ecr_pull_environments : local.target.environments[e].account_id]
  # Dev y staging se destruyen y recrean libremente; en prod borrar imágenes exige intervenir.
  force_delete = local.is_local || var.environment != "prod"
}

module "alb" {
  source = "../../modules/alb"

  name                = local.name
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  listener_port       = local.env.alb_listener_port
  certificate_arn     = var.certificate_arn
  container_port      = 8000
  deletion_protection = var.alb_deletion_protection && !local.is_local
}

# ---------- Datos de la app ----------
# Las tareas de ECS no guardan estado: los datos viven en DynamoDB y todas las réplicas
# detrás del balanceador ven lo mismo.
resource "aws_dynamodb_table" "tasks" {
  #checkov:skip=CKV_AWS_119:Cifrado con la llave administrada por AWS; una CMK es un paso de crecimiento.
  name         = "${local.name}-tasks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = var.environment == "prod" && !local.is_local
}

data "aws_iam_policy_document" "app" {
  statement {
    sid = "TasksTable"
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Scan",
    ]
    resources = [aws_dynamodb_table.tasks.arn]
  }
}

# ---------- Secretos de la app ----------
resource "aws_secretsmanager_secret" "api_token" {
  #checkov:skip=CKV_AWS_149:Llave administrada por AWS; una CMK por ambiente es un paso de crecimiento.
  #checkov:skip=CKV2_AWS_57:La rotación automática requiere una Lambda; se documenta como mejora.
  name        = "${local.name}/api-token"
  description = "Token que exige la API para operaciones de escritura."
  # En prod, 7 días para recuperar un borrado accidental; en el resto, borrado inmediato
  # para poder destruir y recrear el ambiente sin conflictos de nombre.
  recovery_window_in_days = var.environment == "prod" && !local.is_local ? 7 : 0
}

# Valor generado sin quedar guardado en el estado de Terraform (recurso efímero + argumento
# de solo escritura). Para rotarlo: incrementar secret_string_wo_version.
ephemeral "random_password" "api_token" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret_version" "api_token" {
  secret_id                = aws_secretsmanager_secret.api_token.id
  secret_string_wo         = ephemeral.random_password.api_token.result
  secret_string_wo_version = 1
}

# ---------- Versión desplegada ----------
# La escribe el pipeline de CD en cada despliegue. Terraform solo la crea y la lee, para
# registrar sus revisiones de la definición de tarea con la imagen que ya está corriendo.
resource "aws_ssm_parameter" "image_tag" {
  #checkov:skip=CKV2_AWS_34:Valor público (un hash de commit); no es un secreto.
  name           = "${local.ssm_prefix}/image-tag"
  description    = "Etiqueta (hash de commit) de la imagen desplegada. La actualiza el pipeline."
  type           = "String"
  insecure_value = "bootstrap"

  lifecycle {
    ignore_changes = [insecure_value]
  }
}

data "aws_ssm_parameter" "image_tag" {
  name = aws_ssm_parameter.image_tag.name
}

module "service" {
  source = "../../modules/ecs-service"

  name                  = local.name
  service_name          = var.project
  image_repository_url  = module.ecr.repository_url
  image_tag             = data.aws_ssm_parameter.image_tag.insecure_value
  cpu                   = var.task_cpu
  memory                = var.task_memory
  desired_count         = var.desired_count
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn
  log_retention_days    = var.log_retention_days
  # Floci 2.1.0 descarta este atributo y Terraform vería un cambio en cada plan.
  readonly_root_filesystem = !local.is_local

  task_role_policies = { app-data = data.aws_iam_policy_document.app.json }

  environment_variables = {
    APP_ENV            = var.environment
    APP_LOG_LEVEL      = "INFO"
    APP_STORAGE        = "dynamodb"
    APP_DYNAMODB_TABLE = aws_dynamodb_table.tasks.name
  }
  secrets = {
    APP_API_TOKEN = aws_secretsmanager_secret.api_token.arn
  }

  depends_on = [aws_secretsmanager_secret_version.api_token]
}

module "observability" {
  source = "../../modules/observability"

  name                    = local.name
  log_group_name          = module.service.log_group_name
  cluster_name            = module.service.cluster_name
  service_name            = module.service.service_name
  desired_count           = var.desired_count
  alb_arn_suffix          = module.alb.arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  alarm_email             = var.alarm_email
  error_threshold         = var.error_threshold

  enable_log_metric_filters = local.target.log_metric_filters
}

resource "aws_ssm_parameter" "app_url" {
  #checkov:skip=CKV2_AWS_34:Valor público (la URL del balanceador); no es un secreto.
  name           = "${local.ssm_prefix}/app-url"
  description    = "URL pública de la app; la usan las pruebas posteriores al despliegue."
  type           = "String"
  insecure_value = coalesce(local.env.app_url, module.alb.url)
}
