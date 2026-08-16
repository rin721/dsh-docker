#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker
[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"

: "${DSH_DOMAIN:?启用 HTTPS edge 时必须设置 DSH_DOMAIN}"
: "${AUTH_DOMAIN:?启用 HTTPS edge 时必须设置 AUTH_DOMAIN}"
: "${ACME_EMAIL:?启用 HTTPS edge 时必须设置 ACME_EMAIL}"
[[ "${TINYAUTH_SECURE_COOKIE:-false}" == "true" ]] || { echo "TINYAUTH_SECURE_COOKIE 必须为 true。" >&2; exit 1; }
[[ "${AUTH_URL:-}" == "https://${AUTH_DOMAIN}" ]] || { echo "AUTH_URL 应为 https://${AUTH_DOMAIN}" >&2; exit 1; }

"${ROOT_DIR}/scripts/init-runtime.sh"
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge config >/dev/null
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge pull tinyauth gateway edge
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge build --pull dsh
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge up -d --remove-orphans

echo "HTTPS edge 已启动："
echo "  DSH:  https://${DSH_DOMAIN}"
echo "  Auth: https://${AUTH_DOMAIN}"
