terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Estado remoto en S3 con bloqueo en DynamoDB, uno por cuenta/ambiente.
  # La configuración concreta (bucket, endpoints) la genera scripts/tf.sh
  # a partir del archivo de destino, porque un bloque backend no acepta variables.
  backend "s3" {}
}
