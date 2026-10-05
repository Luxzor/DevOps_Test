#!/usr/bin/env bash
# Imprime, en formato de outputs de GitHub Actions, la configuración de un ambiente según el
# destino activo (TARGET). Los workflows la usan para autenticarse por OIDC.
#   scripts/gha-target.sh <env> >> "$GITHUB_OUTPUT"
set -euo pipefail
source "$(dirname "$0")/lib.sh"
env="$1"
require_env_name "$env"

account="$(env_get "$env" account_id)"
[[ "$account" =~ ^[0-9]{12}$ ]] || die "account_id de $env inválido en $TARGET_FILE: '$account'"

echo "target=$TARGET"
echo "region=$(target_get .region)"
echo "account_id=$account"
echo "endpoint=$(env_get "$env" endpoint)"
echo "deploy_role=$(role_arn "$env" deploy)"
echo "terraform_role=$(role_arn "$env" terraform)"
echo "plan_role=$(role_arn "$env" plan)"
