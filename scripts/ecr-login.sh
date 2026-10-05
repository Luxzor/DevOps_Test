#!/usr/bin/env bash
# Inicia sesión de Docker en el registro ECR de un ambiente e imprime la URI del repositorio.
#   scripts/ecr-login.sh <env>
# Se indica siempre --registry-id: al promover, las credenciales son del ambiente destino y el
# registro es el de la cuenta de origen (acceso permitido por la política del repositorio).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
use_env "$1"

uri="$(aws ecr describe-repositories --registry-id "$ACCOUNT_ID" --repository-names "$PROJECT" \
  --query 'repositories[0].repositoryUri' --output text)"
registry="${uri%%/*}"
aws ecr get-login-password | docker login --username AWS --password-stdin "$registry" >/dev/null
echo "$uri"
