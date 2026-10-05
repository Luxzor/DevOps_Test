#!/usr/bin/env bash
# Pruebas end to end básicas contra un ambiente desplegado (se usan en staging).
# Recorre el CRUD completo por el balanceador, con el token real de Secrets Manager.
#   scripts/e2e-test.sh <env>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
env="$1"
use_env "$env"

url="$(aws ssm get-parameter --name "$(ssm_prefix "$env")/app-url" --query Parameter.Value --output text)"
token="$(aws secretsmanager get-secret-value --secret-id "$PROJECT-$env/api-token" \
  --query SecretString --output text)"
[ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::$token"

fail() { die "E2E ($env): $*"; }
request() { # <método> <ruta> [body] [con-token]; imprime "<status> <body>"
  local args=(-s -w '\n%{http_code}' -X "$1" "$url$2" -H 'Content-Type: application/json')
  [ -n "${3:-}" ] && args+=(-d "$3")
  [ "${4:-auth}" = auth ] && args+=(-H "X-API-Key: $token")
  local out; out="$(curl "${args[@]}")"
  echo "$(tail -n1 <<<"$out") $(sed '$d' <<<"$out")"
}
expect() { # <status-esperado> <respuesta>
  [ "${2%% *}" = "$1" ] || fail "se esperaba HTTP $1 y llegó: $2"
}

log "E2E contra $url"
expect 401 "$(request POST /tasks '{"title":"sin token"}' noauth)"

created="$(request POST /tasks '{"title":"e2e","description":"creada por el pipeline"}')"
expect 201 "$created"
id="$(jq -r .id <<<"${created#* }")"

# Varias lecturas seguidas: con más de una tarea detrás del ALB, todas deben ver el dato.
for _ in 1 2 3 4; do expect 200 "$(request GET "/tasks/$id")"; done

updated="$(request PATCH "/tasks/$id" '{"done":true}')"
expect 200 "$updated"
[ "$(jq -r .done <<<"${updated#* }")" = true ] || fail "PATCH no marcó la tarea como hecha"

expect 204 "$(request DELETE "/tasks/$id")"
expect 404 "$(request GET "/tasks/$id")"
log "E2E OK en $env"
