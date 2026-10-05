#!/usr/bin/env bash
# Configura el repositorio de GitHub como lo exige el pipeline (idempotente: se puede repetir).
# Requiere GitHub CLI autenticado con permisos de administrador del repositorio:
#   gh auth login
#   scripts/github-setup.sh Luxzor/DevOps_Test
#
# Qué configura:
#   - Merge solo por squash, historial lineal, borrar ramas al fusionar
#   - Permiso para que GitHub Actions cree Pull Requests (release-please)
#   - Variables del repositorio (DEPLOY_TARGET, PROD_WATCH_MINUTES)
#   - Environments dev, staging y prod (prod con revisor obligatorio)
#   - Ruleset de main: PR obligatorio, 1 aprobación, Code Owners, checks en verde, sin force push
#   - Alertas y actualizaciones de seguridad de Dependabot; escaneo de secretos si el plan lo permite
set -euo pipefail

repo="${1:?Uso: scripts/github-setup.sh <owner>/<repo>}"
reviewer="${REVIEWER:-$(gh api user --jq .login)}"
api() { gh api -H "Accept: application/vnd.github+json" "$@"; }
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    aviso: %s\033[0m\n' "$*"; }

step "Opciones de merge"
api -X PATCH "repos/$repo" \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true -F allow_auto_merge=true \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY >/dev/null

step "Permisos de GitHub Actions"
# Token de los workflows en solo lectura por defecto; cada workflow pide lo que necesita.
api -X PUT "repos/$repo/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true >/dev/null

step "Variables del repositorio"
gh variable set DEPLOY_TARGET --repo "$repo" --body "${DEPLOY_TARGET:-local}"
gh variable set PROD_WATCH_MINUTES --repo "$repo" --body "${PROD_WATCH_MINUTES:-10}"

step "Environments"
reviewer_id="$(api "users/$reviewer" --jq .id)"
for env in dev staging prod; do
  if [ "$env" = prod ]; then
    body=$(jq -n --argjson id "$reviewer_id" '{
      wait_timer: 0,
      prevent_self_review: false,
      reviewers: [{type: "User", id: $id}],
      deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}
    }')
  else
    body='{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
  fi
  api -X PUT "repos/$repo/environments/$env" --input - <<<"$body" >/dev/null
  # Solo main puede desplegar en cualquier ambiente (también es la base de la confianza OIDC).
  existing="$(api "repos/$repo/environments/$env/deployment-branch-policies" --jq '.branch_policies[].name')"
  grep -qx main <<<"$existing" ||
    api -X POST "repos/$repo/environments/$env/deployment-branch-policies" -f name=main -f type=branch >/dev/null
  echo "    $env listo"
done

step "Ruleset de la rama main"
ruleset=$(jq -n '{
  name: "main",
  target: "branch",
  enforcement: "active",
  conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
  bypass_actors: [{actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "pull_request"}],
  rules: [
    {type: "deletion"},
    {type: "non_fast_forward"},
    {type: "required_linear_history"},
    {type: "pull_request", parameters: {
      required_approving_review_count: 1,
      dismiss_stale_reviews_on_push: true,
      require_code_owner_review: true,
      require_last_push_approval: false,
      required_review_thread_resolution: true,
      allowed_merge_methods: ["squash"]
    }},
    {type: "required_status_checks", parameters: {
      strict_required_status_checks_policy: true,
      required_status_checks: [
        {context: "ci-ok"},
        {context: "Conventional Commits"},
        {context: "CodeQL · python"},
        {context: "CodeQL · actions"}
      ]
    }}
  ]
}')
existing_id="$(api "repos/$repo/rulesets" --jq '.[] | select(.name=="main") | .id')"
if [ -n "$existing_id" ]; then
  api -X PUT "repos/$repo/rulesets/$existing_id" --input - <<<"$ruleset" >/dev/null
else
  api -X POST "repos/$repo/rulesets" --input - <<<"$ruleset" >/dev/null
fi
echo "    PR obligatorio, 1 aprobación, Code Owners, historial lineal y checks: ci-ok, PR title, CodeQL"
echo "    Los administradores pueden fusionar sin aprobación (bypass) para poder trabajar en solitario."

step "Seguridad"
api -X PUT "repos/$repo/vulnerability-alerts" >/dev/null && echo "    Alertas de Dependabot activadas"
api -X PUT "repos/$repo/automated-security-fixes" >/dev/null && echo "    Actualizaciones de seguridad de Dependabot activadas"
if api -X PATCH "repos/$repo" --input - >/dev/null 2>&1 <<'EOF'
{"security_and_analysis": {
  "secret_scanning": {"status": "enabled"},
  "secret_scanning_push_protection": {"status": "enabled"}
}}
EOF
then
  echo "    Escaneo de secretos y push protection activados"
else
  warn "el escaneo de secretos de GitHub en repos privados requiere GitHub Secret Protection."
  warn "Gitleaks (CI) y Trivy cubren la detección de secretos mientras tanto."
fi

step "Listo"
cat <<EOF
Pendiente (manual):
  1. Registrar el runner autohospedado: Settings > Actions > Runners > New self-hosted runner,
     y luego: RUNNER_REPO_URL=https://github.com/$repo RUNNER_TOKEN=<token> \\
       docker compose -f simulation/docker-compose.yml --profile runner up -d --build
  2. (Opcional) Secreto RELEASE_PLEASE_TOKEN para que el PR de release dispare el CI.
EOF
