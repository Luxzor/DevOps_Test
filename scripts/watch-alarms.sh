#!/usr/bin/env bash
# Vigila un ambiente después de desplegar: alarmas de CloudWatch y /health.
# Termina con error si alguna alarma del servicio entra en ALARM o la app deja de responder.
#   scripts/watch-alarms.sh <env> [minutos]   (por defecto 10)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
env="$1" minutes="${2:-10}"
use_env "$env"

prefix="$PROJECT-$env"
url="$(aws ssm get-parameter --name "$(ssm_prefix "$env")/app-url" --query Parameter.Value --output text)"
interval="${WATCH_INTERVAL:-30}"
deadline=$((SECONDS + minutes * 60))

log "Vigilando $env durante $minutes min (alarmas $prefix-*, $url/health)"
while [ "$SECONDS" -lt "$deadline" ]; do
  # El filtro por estado va en la consulta (algunos emuladores ignoran --state-value).
  firing="$(aws cloudwatch describe-alarms --alarm-name-prefix "$prefix-" \
    --query "MetricAlarms[?StateValue=='ALARM'].AlarmName" --output text)"
  [ -z "$firing" ] || [ "$firing" = "None" ] || die "Alarmas activas en $env: $firing"
  status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url/health" || true)"
  [ "$status" = 200 ] || die "/health respondió $status en $env"
  sleep "$interval"
done
log "Sin alarmas durante $minutes min en $env"
