#!/usr/bin/env bash
# Publica en el ECR de un ambiente una imagen ya construida (la de CI), con el hash del
# commit como etiqueta. No reconstruye nada.
#   scripts/publish-image.sh <env> <imagen-local> <tag>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
env="$1" local_image="$2" tag="$3"

uri="$("$(dirname "$0")/ecr-login.sh" "$env")"
use_env "$env"

existing="$(aws ecr describe-images --registry-id "$ACCOUNT_ID" --repository-name "$PROJECT" --image-ids imageTag="$tag" \
  --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || true)"
if [ -n "$existing" ] && [ "$existing" != "None" ]; then
  # Las etiquetas son inmutables: si ya existe, no se vuelve a publicar.
  log "La imagen $tag ya existe en $env ($existing); no se publica de nuevo"
  echo "$existing"
  exit 0
fi

docker tag "$local_image" "$uri:$tag"
docker push --quiet "$uri:$tag" >&2
digest="$(aws ecr describe-images --registry-id "$ACCOUNT_ID" --repository-name "$PROJECT" --image-ids imageTag="$tag" \
  --query 'imageDetails[0].imageDigest' --output text)"
log "Publicada $uri:$tag ($digest)"
echo "$digest"
