# Recursos que deben existir antes que cualquier pipeline: el lugar donde Terraform guarda
# su estado y la identidad con la que GitHub Actions entra a la cuenta. Es el único paso
# manual del proyecto (ver scripts/bootstrap.sh).

locals {
  target   = jsondecode(file("${path.module}/../targets/${var.target}.json"))
  env      = local.target.environments[var.environment]
  is_local = var.target == "local"
  repo     = local.target.github_repository
  name     = "${var.project}-${var.environment}"

  # Ambiente anterior en la cadena de promoción (de dónde se copian las imágenes).
  promotion_source = { dev = null, staging = "dev", prod = "staging" }[var.environment]
  source_account   = local.promotion_source == null ? null : local.target.environments[local.promotion_source].account_id

  github_oidc_host = "token.actions.githubusercontent.com"
}

# ---------- Estado remoto ----------
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_144:Replicación entre regiones fuera del alcance (multi región es paso de crecimiento).
  #checkov:skip=CKV_AWS_18:Access logs del bucket de estado quedan como mejora.
  #checkov:skip=CKV2_AWS_62:Sin notificaciones de eventos para el bucket de estado.
  #checkov:skip=CKV_AWS_145:Cifrado SSE-S3; KMS con llave propia es un paso de crecimiento.
  bucket = "${var.project}-tfstate-${local.env.account_id}"

  # El bucket guarda la historia de toda la infraestructura: no se borra con un destroy.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  # El emulador habla HTTP plano; la política de solo TLS aplica en AWS real.
  count  = local.is_local ? 0 : 1
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json
}

resource "aws_dynamodb_table" "lock" {
  #checkov:skip=CKV_AWS_119:Cifrado con la llave administrada por AWS.
  name         = "${var.project}-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---------- Identidad de GitHub Actions (OIDC) ----------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

# Relación de confianza: solo este repositorio, y solo jobs ligados al Environment de este
# ambiente. Qué ramas o tags pueden usar el Environment lo deciden sus reglas de protección
# en GitHub (main para dev y staging; tags v* y aprobación para prod).
data "aws_iam_policy_document" "trust_environment" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["repo:${local.repo}:environment:${var.environment}"]
    }
  }
}

# El plan de Terraform corre en Pull Requests y en main, sin Environment y con permisos de lectura.
data "aws_iam_policy_document" "trust_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values = [
        "repo:${local.repo}:pull_request",
        "repo:${local.repo}:ref:refs/heads/main",
      ]
    }
  }
}
