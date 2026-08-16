#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
[[ -f .env ]] && load_env "${ROOT_DIR}"
RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
CONFIG_FILE="${RUNTIME_ABS}/tinyauth/config.yml"

echo "Repository: ${ROOT_DIR}"
echo "Runtime:    ${RUNTIME_ABS}"
echo "DSH bind:   ${BIND_ADDRESS:-127.0.0.1}:${DSH_PORT:-3080}"
echo "Auth bind:  ${BIND_ADDRESS:-127.0.0.1}:${AUTH_PORT:-3081}"
echo "Auth URL:   ${AUTH_URL:-http://localhost:3081}"
if has_tinyauth_user "${CONFIG_FILE}"; then
    echo "Auth users: configured"
else
    echo "Auth users: missing"
fi

echo
echo "Compose status:"
docker compose ps

echo
echo "Published ports:"
docker compose port gateway 3080 2>/dev/null || true
docker compose port gateway 3081 2>/dev/null || true

echo
echo "Recent logs:"
docker compose logs --tail=30 gateway tinyauth dsh
