terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Huevo y gallina: el bucket del estado remoto todavía no existe, así que el bootstrap
  # guarda su propio estado en local, un workspace por ambiente (terraform.tfstate.d/<env>).
  # Nunca se versiona en Git; ver docs/runbook.md para respaldarlo.
  backend "local" {}
}
