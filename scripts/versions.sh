#!/usr/bin/env bash
# Muestra qué versión corre en cada ambiente, preguntándole a la app y a SSM.
#   scripts/versions.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

printf '%-8s  %-40s  %-40s  %s\n' AMBIENTE "COMMIT (SSM)" "COMMIT (/version)" URL
for env in dev staging prod; do
  (
    use_env "$env"
    prefix="$(ssm_prefix "$env")"
    tag="$(aws ssm get-parameter --name "$prefix/image-tag" --query Parameter.Value --output text 2>/dev/null || echo "?")"
    url="$(aws ssm get-parameter --name "$prefix/app-url" --query Parameter.Value --output text 2>/dev/null || echo "")"
    live="$( [ -n "$url" ] && curl -sf --max-time 5 "$url/version" | jq -r .commit 2>/dev/null || echo "sin respuesta")"
    printf '%-8s  %-40s  %-40s  %s\n' "$env" "$tag" "$live" "$url"
  )
done
