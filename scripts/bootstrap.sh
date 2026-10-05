#!/usr/bin/env bash
# Único paso manual del proyecto: crea, en la cuenta de un ambiente, el bucket del estado
# remoto, la tabla de bloqueo, el proveedor OIDC de GitHub y los roles del pipeline.
#
#   scripts/bootstrap.sh dev          (simulación)
#   TARGET=aws scripts/bootstrap.sh prod   (con credenciales de administrador de esa cuenta)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

env="${1:-}"
use_env "$env"
dir="$REPO_ROOT/infra/bootstrap"

log "Bootstrap de $env en el destino $TARGET (cuenta $ACCOUNT_ID)"
unset AWS_ENDPOINT_URL # el proveedor usa los endpoints del archivo de destino
terraform -chdir="$dir" init -input=false >/dev/null
# Un workspace por destino y ambiente: estados de bootstrap separados.
terraform -chdir="$dir" workspace select -or-create "$TARGET-$env" >/dev/null
terraform -chdir="$dir" apply -input=false \
  -var "target=$TARGET" -var "environment=$env" ${AUTO_APPROVE:+-auto-approve}

log "Listo. Siguiente paso: scripts/tf.sh $env init && scripts/tf.sh $env apply"
