#!/usr/bin/env bash
# Funciones comunes para scripts locales y workflows. Se carga con `source scripts/lib.sh`.
#
# Lee el archivo de destino (infra/targets/<TARGET>.json) y expone la configuración de un
# ambiente. TARGET vale `local` por defecto.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-local}"
TARGET_FILE="$REPO_ROOT/infra/targets/$TARGET.json"
PROJECT="tasks-api"

log() { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$TARGET_FILE" ] || die "No existe el destino $TARGET_FILE (TARGET=local|aws)"
command -v jq >/dev/null || die "Se necesita jq"

# target_get '<filtro jq>'
target_get() { jq -r "$1 // empty" "$TARGET_FILE"; }

# env_get <ambiente> <campo>
env_get() { target_get ".environments[\"$1\"].$2"; }

require_env_name() {
  case "${1:-}" in
    dev | staging | prod) ;;
    *) die "Ambiente inválido: '${1:-}'. Usa dev, staging o prod." ;;
  esac
}

# Exporta región, cuenta, endpoint y (solo en simulación, si no hay otras) credenciales.
# Las credenciales "test" del emulador no son secretos: cada emulador opera sobre su propia
# cuenta. En AWS real nunca se fijan aquí: llegan por OIDC (pipeline) o SSO (personas).
use_env() {
  local env="$1"
  require_env_name "$env"
  export AWS_REGION AWS_DEFAULT_REGION ACCOUNT_ID
  AWS_REGION="$(target_get .region)"
  AWS_DEFAULT_REGION="$AWS_REGION"
  ACCOUNT_ID="$(env_get "$env" account_id)"
  local endpoint
  endpoint="$(env_get "$env" endpoint)"
  if [ -n "$endpoint" ]; then
    export AWS_ENDPOINT_URL="$endpoint"
    if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
      export AWS_ACCESS_KEY_ID="test" AWS_SECRET_ACCESS_KEY="test"
      unset AWS_SESSION_TOKEN
    fi
  else
    unset AWS_ENDPOINT_URL
  fi
}

# Nombres derivados por convención; Terraform crea los recursos con estos mismos valores.
cluster_name() { echo "$PROJECT-$1"; }
service_name() { echo "$PROJECT"; }
task_family() { echo "$PROJECT-$1"; }
ssm_prefix() { echo "/$PROJECT/$1"; }
role_arn() { echo "arn:aws:iam::$(env_get "$1" account_id):role/$PROJECT-$1-github-$2"; }
