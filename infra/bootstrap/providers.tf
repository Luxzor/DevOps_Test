provider "aws" {
  region              = local.target.region
  allowed_account_ids = [local.env.account_id]

  s3_use_path_style       = local.is_local
  skip_metadata_api_check = local.is_local

  dynamic "endpoints" {
    for_each = local.is_local ? [local.env.endpoint] : []
    content {
      dynamodb = endpoints.value
      iam      = endpoints.value
      s3       = endpoints.value
      sts      = endpoints.value
      # S3 Control antepone el ID de cuenta al host (<cuenta>.localhost), que no siempre
      # resuelve. *.localhost.floci.io es un DNS público que apunta a 127.0.0.1.
      s3control = replace(endpoints.value, "//localhost:", "//localhost.floci.io:")
    }
  }

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = local.target.owner
      ManagedBy   = "terraform-bootstrap"
    }
  }
}
