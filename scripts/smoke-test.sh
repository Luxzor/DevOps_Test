#!/usr/bin/env bash
# Prueba de humo: /health responde y /version reporta el commit esperado, varias veces
# seguidas (con dos o más tareas detrás del balanceador, todas deben tener la versión nueva).
#   scripts/smoke-test.sh <url> <commit-esperado>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
url="${1%/}" expected="$2"
required="${SMOKE_CONSECUTIVE:-5}" timeout="${SMOKE_TIMEOUT:-180}"

ok=0 deadline=$((SECONDS + timeout))
while [ "$SECONDS" -lt "$deadline" ]; do
  health="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url/health" || true)"
  commit="$(curl -sf --max-time 5 "$url/version" | jq -r .commit 2>/dev/null || true)"
  if [ "$health" = 200 ] && [ "$commit" = "$expected" ]; then
    ok=$((ok + 1))
    [ "$ok" -ge "$required" ] && { log "Smoke test OK: $url corre $expected"; exit 0; }
  else
    [ "$ok" -gt 0 ] && log "Respuesta inconsistente (health=$health commit=${commit:-?}); reinicio la cuenta"
    ok=0
  fi
  sleep 2
done
die "Smoke test falló en $url: se esperaba $expected (último health=$health commit=${commit:-?})"
