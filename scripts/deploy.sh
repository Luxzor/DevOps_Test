#!/usr/bin/env bash
# Despliega en ECS una imagen que ya está en el ECR del ambiente.
#   scripts/deploy.sh <env> <tag>
#
# 1. Parte de la última revisión de la definición de tarea (la que mantiene Terraform) y
#    solo cambia la imagen.
# 2. Actualiza el servicio (rolling update) y espera a que quede estable.
# 3. Verifica con un smoke test que todas las respuestas vengan de la versión nueva.
# 4. Si algo falla, vuelve a la definición de tarea anterior y termina con error.
#    Esto complementa al circuit breaker de ECS, que en AWS revierte tareas que no arrancan
#    pero no detecta una versión que arranca y responde mal.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
env="$1" tag="$2"
use_env "$env"

cluster="$(cluster_name "$env")"
service="$(service_name "$env")"
family="$(task_family "$env")"
timeout="${DEPLOY_TIMEOUT:-600}"

summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$*" >>"$GITHUB_STEP_SUMMARY" || true; }

uri="$(aws ecr describe-repositories --registry-id "$ACCOUNT_ID" --repository-names "$PROJECT" \
  --query 'repositories[0].repositoryUri' --output text)"
digest="$(aws ecr describe-images --registry-id "$ACCOUNT_ID" --repository-name "$PROJECT" --image-ids imageTag="$tag" \
  --query 'imageDetails[0].imageDigest' --output text 2>/dev/null)" \
  || die "La imagen $tag no está en el ECR de $env. Publícala o promuévela primero."

previous="$(aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].taskDefinition' --output text)"
app_url="$(aws ssm get-parameter --name "$(ssm_prefix "$env")/app-url" \
  --query Parameter.Value --output text)"

# ---------- 1. Nueva revisión de la definición de tarea ----------
base="$(aws ecs describe-task-definition --task-definition "$family" --include TAGS)"
input="$(jq --arg image "$uri:$tag" '
  .tags as $tags
  | .taskDefinition
  | .containerDefinitions |= map(if .name == "app" then .image = $image else . end)
  | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
        .registeredAt, .registeredBy, .deregisteredAt, .enableFaultInjection)
  | if ($tags | length) > 0 then .tags = $tags else . end
' <<<"$base")"
new_td="$(aws ecs register-task-definition --cli-input-json "$input" \
  --query 'taskDefinition.taskDefinitionArn' --output text)"
log "Registrada $new_td con la imagen $tag"

rollback() {
  local reason="$1"
  log "Despliegue fallido: $reason"
  if [ "$previous" = "None" ] || [ -z "$previous" ] || [ "$previous" = "$new_td" ]; then
    summary "### :x: $env: despliegue de \`$tag\` fallido, sin versión previa a la que volver"
    die "$reason"
  fi
  log "Rollback automático a $previous"
  aws ecs update-service --cluster "$cluster" --service "$service" \
    --task-definition "$previous" >/dev/null
  aws ecs wait services-stable --cluster "$cluster" --services "$service" || true
  summary "### :rewind: $env: \`$tag\` revertido automáticamente"
  summary "Motivo: $reason. El servicio volvió a \`${previous##*/}\`."
  die "$reason (se revirtió a ${previous##*/})"
}

# ---------- 2. Rolling update ----------
aws ecs update-service --cluster "$cluster" --service "$service" \
  --task-definition "$new_td" >/dev/null
log "Esperando a que $service quede estable (máximo ${timeout}s)"

deadline=$((SECONDS + timeout))
while :; do
  # shellcheck disable=SC2016 # los backticks son sintaxis de JMESPath, no de bash
  read -r current running desired state <<<"$(aws ecs describe-services \
    --cluster "$cluster" --services "$service" --output text \
    --query 'services[0].[taskDefinition, runningCount, desiredCount, deployments[?status==`PRIMARY`] | [0].rolloutState]')"
  # Si el circuit breaker de ECS revirtió el despliegue, el servicio ya no apunta a new_td.
  [ "$current" = "$new_td" ] || rollback "ECS revirtió el despliegue (circuit breaker)"
  [ "$state" = "FAILED" ] && rollback "ECS marcó el despliegue como FAILED"
  if [ "$state" = "COMPLETED" ] && [ "$running" = "$desired" ]; then
    break
  fi
  [ "$SECONDS" -ge "$deadline" ] && rollback "el servicio no quedó estable en ${timeout}s"
  sleep 5
done
log "Servicio estable: $running/$desired tareas con ${new_td##*/}"

# ---------- 3. Verificación ----------
"$(dirname "$0")/smoke-test.sh" "$app_url" "$tag" || rollback "falló el smoke test"

# ---------- 4. Registro de la versión desplegada ----------
aws ssm put-parameter --name "$(ssm_prefix "$env")/image-tag" --value "$tag" \
  --type String --overwrite >/dev/null

summary "### :rocket: $env desplegado"
summary ""
summary "| Ambiente | Versión (commit) | Digest | Definición de tarea | URL |"
summary "| --- | --- | --- | --- | --- |"
summary "| $env | \`$tag\` | \`${digest:7:12}\` | \`${new_td##*/}\` | $app_url |"
log "$env corre $tag ($digest)"
