#!/usr/bin/env bash
# Envoltorio de Terraform para un ambiente:  scripts/tf.sh <env> <comando> [args...]
#
#   scripts/tf.sh dev init        genera la configuración del backend y ejecuta init
#   scripts/tf.sh dev plan        cualquier otro comando pasa tal cual a terraform
#   TARGET=aws scripts/tf.sh prod plan
set -euo pipefail
source "$(dirname "$0")/lib.sh"

env="${1:-}"; shift || true
cmd="${1:-}"; shift || true
[ -n "$cmd" ] || die "Uso: scripts/tf.sh <dev|staging|prod> <comando terraform> [args]"
use_env "$env"

dir="$REPO_ROOT/infra/environments/$env"
export TF_VAR_target="$TARGET"
export TF_IN_AUTOMATION="${TF_IN_AUTOMATION:-}"
# Terraform toma los endpoints del archivo de destino, no de esta variable.
endpoint="${AWS_ENDPOINT_URL:-}"
unset AWS_ENDPOINT_URL

if [ "$cmd" = "init" ]; then
  backend_file="$(mktemp)"
  trap 'rm -f "$backend_file"' EXIT
  {
    echo "bucket         = \"$PROJECT-tfstate-$ACCOUNT_ID\""
    echo "key            = \"infra/terraform.tfstate\""
    echo "region         = \"$AWS_REGION\""
    echo "dynamodb_table = \"$PROJECT-tflock\""
    echo "encrypt        = true"
    if [ -n "$endpoint" ]; then
      echo "use_path_style = true"
      echo "endpoints = {"
      for svc in s3 dynamodb sts iam; do echo "  $svc = \"$endpoint\""; done
      echo "}"
    fi
  } >"$backend_file"
  log "terraform init ($env, destino $TARGET, cuenta $ACCOUNT_ID)"
  terraform -chdir="$dir" init -reconfigure -input=false -backend-config="$backend_file" "$@"
else
  terraform -chdir="$dir" "$cmd" "$@"
fi
