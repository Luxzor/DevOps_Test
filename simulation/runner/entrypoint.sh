#!/usr/bin/env bash
# Registra el runner en el repositorio y lo ejecuta. El token de registro se obtiene en
# Settings > Actions > Runners > New self-hosted runner, dura una hora y se usa una sola vez.
set -euo pipefail

: "${RUNNER_REPO_URL:?Define RUNNER_REPO_URL, por ejemplo https://github.com/<owner>/<repo>}"
: "${RUNNER_TOKEN:?Define RUNNER_TOKEN con un token de registro del repositorio}"

# El grupo dueño del socket cambia según el sistema; el usuario runner debe pertenecer a él.
SOCK_GID="$(stat -c '%g' /var/run/docker.sock)"
if [ "$(getent group docker | cut -d: -f3)" != "$SOCK_GID" ]; then
  groupmod -o -g "$SOCK_GID" docker
fi

cd /home/runner
run_as_runner() { sudo -E -H -u runner "$@"; }

if [ ! -f .runner ]; then
  run_as_runner ./config.sh --unattended --replace \
    --url "$RUNNER_REPO_URL" \
    --token "$RUNNER_TOKEN" \
    --name "${RUNNER_NAME:-sim-runner}" \
    --labels "${RUNNER_LABELS:-sim}" \
    --work _work
fi

exec sudo -E -H -u runner ./run.sh
