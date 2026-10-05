data "aws_region" "current" {}

resource "aws_ecs_cluster" "this" {
  name = var.name

  # Métricas por tarea y servicio (CPU, memoria, tareas corriendo) en CloudWatch.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  #checkov:skip=CKV_AWS_158:Cifrado con la llave administrada por AWS; una CMK es un paso de crecimiento.
  #checkov:skip=CKV_AWS_338:Retención configurable; 30 días alcanzan para el proyecto.
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

# ---------- IAM ----------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Rol de ejecución: lo usa el agente de ECS para descargar la imagen, escribir logs
# y leer los secretos que se inyectan como variables de entorno.
resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "PullImages"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "PullFromRepository"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:*:*:repository/*"]
  }
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
  dynamic "statement" {
    for_each = length(var.secrets) > 0 ? [1] : []
    content {
      sid       = "ReadInjectedSecrets"
      actions   = ["secretsmanager:GetSecretValue", "ssm:GetParameters"]
      resources = values(var.secrets)
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "ecs-execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# Rol de la tarea: los permisos del código de la app (por ejemplo, leer y escribir su tabla).
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "task" {
  for_each = var.task_role_policies
  name     = each.key
  role     = aws_iam_role.task.id
  policy   = each.value
}

# ---------- Red ----------
resource "aws_security_group" "service" {
  name        = "${var.name}-service"
  description = "Tareas de ${var.name}: solo reciben trafico del balanceador"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-service" }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "Trafico desde el ALB"
  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

# Salida HTTPS (vía NAT) para ECR, Secrets Manager y CloudWatch Logs.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.service.id
  description       = "HTTPS hacia los APIs de AWS"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# ---------- Definición de tarea y servicio ----------
locals {
  container = {
    name      = var.container_name
    image     = "${var.image_repository_url}:${var.image_tag}"
    essential = true
    # Con awsvpc, hostPort es siempre igual a containerPort; declararlo evita diferencias.
    portMappings = [{ containerPort = var.container_port, hostPort = var.container_port, protocol = "tcp" }]
    environment = [
      for k, v in merge(var.environment_variables, { PORT = tostring(var.container_port) }) :
      { name = k, value = v }
    ]
    secrets = [for k, arn in var.secrets : { name = k, valueFrom = arn }]
    healthCheck = {
      command     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${var.container_port}/health', timeout=2)"]
      interval    = 15
      timeout     = 3
      retries     = 3
      startPeriod = 10
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "app"
      }
    }
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    merge(
      local.container,
      # Sistema de archivos de solo lectura: la app no escribe en disco.
      var.readonly_root_filesystem ? { readonlyRootFilesystem = true } : {},
    )
  ])
}

resource "aws_ecs_service" "app" {
  name                    = var.service_name
  cluster                 = aws_ecs_cluster.this.id
  task_definition         = aws_ecs_task_definition.app.arn
  desired_count           = var.desired_count
  launch_type             = "FARGATE"
  propagate_tags          = "SERVICE"
  enable_ecs_managed_tags = true

  # Rolling update sin caídas: arranca tareas nuevas antes de apagar las viejas.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30

  # Si las tareas nuevas no pasan el health check, ECS vuelve solo a la versión anterior.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  lifecycle {
    # La versión que corre la decide el pipeline de CD, no Terraform. Terraform sigue
    # siendo dueño de la configuración (CPU, memoria, secretos): el pipeline parte de la
    # última revisión registrada y solo cambia la imagen.
    ignore_changes = [task_definition]
  }
}
