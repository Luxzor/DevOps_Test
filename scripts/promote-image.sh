#!/usr/bin/env bash
# Promueve una imagen de un ambiente al siguiente (de dev a staging, de staging a prod) copiándola de un
# ECR a otro. Construir una vez y promover: el digest (hash del contenido) debe ser idéntico.
#   scripts/promote-image.sh <env-origen> <env-destino> <tag>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
from="$1" to="$2" tag="$3"

image_digest() { # <env>
  (use_env "$1" && aws ecr describe-images --registry-id "$ACCOUNT_ID" --repository-name "$PROJECT" --image-ids imageTag="$tag" \
    --query 'imageDetails[0].imageDigest' --output text 2>/dev/null) || true
}

target_digest="$(image_digest "$to")"
if [ -n "$target_digest" ] && [ "$target_digest" != "None" ]; then
  log "La imagen $tag ya está en $to ($target_digest)"
  echo "$target_digest"
  exit 0
fi

source_digest="$(image_digest "$from")"
[ -n "$source_digest" ] && [ "$source_digest" != "None" ] \
  || die "La imagen $tag no existe en $from: solo se promueve lo que pasó por el ambiente anterior"

src="$("$(dirname "$0")/ecr-login.sh" "$from")"
dst="$("$(dirname "$0")/ecr-login.sh" "$to")"

log "Promoviendo $tag de $from a $to"
docker pull --quiet "$src:$tag" >&2
docker tag "$src:$tag" "$dst:$tag"
docker push --quiet "$dst:$tag" >&2

target_digest="$(image_digest "$to")"
[ "$target_digest" = "$source_digest" ] \
  || die "El digest cambió al promover ($source_digest != $target_digest)"
log "Misma imagen en $from y $to: $target_digest"
echo "$target_digest"
