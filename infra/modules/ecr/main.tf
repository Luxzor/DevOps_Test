resource "aws_ecr_repository" "this" {
  name = var.name
  # Etiquetas inmutables: un hash de commit siempre apunta a la misma imagen.
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Borrar imágenes sin etiqueta después de 7 días"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Conservar solo las últimas ${var.max_tagged_images} imágenes etiquetadas"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

# Política de repositorio para la promoción entre cuentas: el ambiente siguiente
# (por ejemplo staging) puede descargar la imagen ya probada en el anterior (dev).
data "aws_iam_policy_document" "cross_account_pull" {
  count = length(var.pull_account_ids) > 0 ? 1 : 0

  statement {
    sid = "CrossAccountPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
    ]
    principals {
      type        = "AWS"
      identifiers = [for id in var.pull_account_ids : "arn:aws:iam::${id}:root"]
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  count      = length(var.pull_account_ids) > 0 ? 1 : 0
  repository = aws_ecr_repository.this.name
  policy     = data.aws_iam_policy_document.cross_account_pull[0].json
}
