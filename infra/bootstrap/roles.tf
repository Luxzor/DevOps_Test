data "aws_region" "current" {}

locals {
  region     = data.aws_region.current.region
  account_id = local.env.account_id
  arn_prefix = "arn:aws"
  repo_arn   = "${local.arn_prefix}:ecr:${local.region}:${local.account_id}:repository/${var.project}"
}

# ===================== Rol de despliegue de la app =====================
# Publica la imagen en ECR, registra la definición de tarea y actualiza el servicio.
resource "aws_iam_role" "deploy" {
  name                 = "${local.name}-github-deploy"
  description          = "GitHub Actions: despliegue de la app en ${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.trust_environment.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  #checkov:skip=CKV_AWS_356:GetAuthorizationToken, RegisterTaskDefinition y DescribeTasks no admiten restricción por recurso (DescribeTasks se acota por clúster con una condición).
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "PushAndPullOwnRepository"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [local.repo_arn]
  }
  dynamic "statement" {
    for_each = local.source_account == null ? [] : [1]
    content {
      sid = "PullFromPreviousEnvironment"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
      ]
      resources = ["${local.arn_prefix}:ecr:${local.region}:${local.source_account}:repository/${var.project}"]
    }
  }
  statement {
    sid = "TaskDefinitions"
    # Estas acciones de ECS no admiten restringir por recurso.
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:ListTaskDefinitions",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "UpdateService"
    actions   = ["ecs:DescribeServices", "ecs:UpdateService", "ecs:ListServiceDeployments", "ecs:DescribeServiceDeployments"]
    resources = ["${local.arn_prefix}:ecs:${local.region}:${local.account_id}:service/${local.name}/${var.project}"]
  }
  statement {
    sid       = "InspectTasks"
    actions   = ["ecs:DescribeTasks", "ecs:ListTasks"]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = ["${local.arn_prefix}:ecs:${local.region}:${local.account_id}:cluster/${local.name}"]
    }
  }
  statement {
    sid     = "PassTaskRoles"
    actions = ["iam:PassRole"]
    resources = [
      "${local.arn_prefix}:iam::${local.account_id}:role/${local.name}-execution",
      "${local.arn_prefix}:iam::${local.account_id}:role/${local.name}-task",
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
  statement {
    sid       = "DeploymentRecord"
    actions   = ["ssm:GetParameter", "ssm:PutParameter"]
    resources = ["${local.arn_prefix}:ssm:${local.region}:${local.account_id}:parameter/${var.project}/${var.environment}/*"]
  }
  statement {
    sid       = "WatchAlarms"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["${local.arn_prefix}:cloudwatch:${local.region}:${local.account_id}:alarm:${local.name}-*"]
  }
  statement {
    sid       = "EndToEndTestToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["${local.arn_prefix}:secretsmanager:${local.region}:${local.account_id}:secret:${local.name}/api-token-*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy-app"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ===================== Rol de aplicación de Terraform =====================
# Crea y modifica la infraestructura. Amplio por naturaleza, pero acotado a los servicios
# que usa el proyecto y a roles IAM con el prefijo del proyecto (no puede escalar privilegios
# creando roles arbitrarios).
resource "aws_iam_role" "terraform_apply" {
  name                 = "${local.name}-github-terraform"
  description          = "GitHub Actions: terraform apply en ${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.trust_environment.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "terraform_apply" {
  #checkov:skip=CKV_AWS_109:Terraform necesita administrar los servicios del proyecto; se acota por servicio y prefijo.
  #checkov:skip=CKV_AWS_111:Igual que el anterior.
  #checkov:skip=CKV_AWS_356:Muchas acciones de estos servicios no admiten restricción por recurso.
  #checkov:skip=CKV_AWS_107:Terraform crea el secreto de la app y los roles de ECS; el rol solo lo asume el pipeline del Environment.
  #checkov:skip=CKV_AWS_108:Igual que el anterior: administrar Secrets Manager y SSM implica poder leerlos.
  statement {
    sid = "ManageProjectServices"
    actions = [
      "ec2:*",
      "ecs:*",
      "ecr:*",
      "elasticloadbalancing:*",
      "logs:*",
      "cloudwatch:*",
      "sns:*",
      "secretsmanager:*",
      "ssm:*",
      "kms:DescribeKey",
      "kms:ListAliases",
    ]
    resources = ["*"]
  }
  statement {
    sid     = "ManageProjectRoles"
    actions = ["iam:*Role*", "iam:*RolePolicy*", "iam:PassRole", "iam:TagRole", "iam:UntagRole"]
    resources = [
      "${local.arn_prefix}:iam::${local.account_id}:role/${local.name}-*",
    ]
  }
  # Los roles de GitHub quedan fuera de su alcance: el rol de Terraform no puede ampliar
  # sus propios permisos ni los del rol de despliegue.
  statement {
    sid       = "ProtectPipelineRoles"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["${local.arn_prefix}:iam::${local.account_id}:role/${local.name}-github-*"]
  }
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com"]
    }
  }
  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
  statement {
    sid       = "StateBucket"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }
  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.lock.arn]
  }
  statement {
    sid       = "AppTables"
    actions   = ["dynamodb:*"]
    resources = ["${local.arn_prefix}:dynamodb:${local.region}:${local.account_id}:table/${local.name}-*"]
  }
}

resource "aws_iam_role_policy" "terraform_apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply.json
}

# ===================== Rol de plan (solo lectura) =====================
resource "aws_iam_role" "terraform_plan" {
  name                 = "${local.name}-github-plan"
  description          = "GitHub Actions: terraform plan (solo lectura) en ${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "terraform_plan" {
  #checkov:skip=CKV_AWS_356:Las acciones Describe y List de lectura no admiten restricción por recurso.
  statement {
    sid = "ReadInfrastructure"
    actions = [
      "ec2:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "elasticloadbalancing:Describe*",
      "logs:Describe*",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
      "cloudwatch:Describe*",
      "cloudwatch:GetDashboard",
      "cloudwatch:ListTagsForResource",
      "sns:Get*",
      "sns:List*",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
      "ssm:DescribeParameters",
      "ssm:ListTagsForResource",
      "iam:Get*",
      "iam:List*",
      "kms:DescribeKey",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
    ]
    resources = ["*"]
  }
  # Solo los parámetros del proyecto (no los de otros sistemas de la cuenta).
  statement {
    sid       = "ReadProjectParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["${local.arn_prefix}:ssm:${local.region}:${local.account_id}:parameter/${var.project}/${var.environment}/*"]
  }
  statement {
    sid       = "ReadState"
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }
  # El plan toma el bloqueo para no leer un estado a medio escribir.
  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.lock.arn]
  }
}

resource "aws_iam_role_policy" "terraform_plan" {
  name   = "terraform-plan"
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_plan.json
}
