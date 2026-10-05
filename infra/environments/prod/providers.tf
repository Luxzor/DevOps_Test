provider "aws" {
  region = local.target.region

  # Red de seguridad: Terraform se niega a operar si las credenciales son de otra cuenta.
  # Evita, por ejemplo, aplicar la configuración de dev sobre producción.
  allowed_account_ids = [local.env.account_id]

  # En la simulación todo apunta al emulador del ambiente; en AWS real no hay endpoints.
  s3_use_path_style       = local.is_local
  skip_metadata_api_check = local.is_local

  dynamic "endpoints" {
    for_each = local.is_local ? [local.env.endpoint] : []
    content {
      cloudwatch     = endpoints.value
      dynamodb       = endpoints.value
      ec2            = endpoints.value
      ecr            = endpoints.value
      ecs            = endpoints.value
      elbv2          = endpoints.value
      iam            = endpoints.value
      kms            = endpoints.value
      logs           = endpoints.value
      s3             = endpoints.value
      secretsmanager = endpoints.value
      sns            = endpoints.value
      ssm            = endpoints.value
      sts            = endpoints.value
      # S3 Control antepone el ID de cuenta al host (<cuenta>.localhost), que no siempre
      # resuelve. *.localhost.floci.io es un DNS público que apunta a 127.0.0.1.
      s3control = replace(endpoints.value, "//localhost:", "//localhost.floci.io:")
    }
  }

  # Etiquetas obligatorias en todos los recursos.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = local.target.owner
      ManagedBy   = "terraform"
    }
  }
}
