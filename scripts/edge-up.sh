#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker
[[ -f .env ]] || { echo "缺少 .env，请先执行 ./scripts/deploy.sh。" >&2; exit 1; }
load_env "${ROOT_DIR}"

: "${DSH_DOMAIN:?请在 .env 设置 DSH_DOMAIN，例如 dsh.example.com}"
: "${ACME_EMAIL:?请在 .env 设置 ACME_EMAIL}"
validate_port EDGE_HTTP_PORT "${EDGE_HTTP_PORT:-80}"
validate_port EDGE_HTTPS_PORT "${EDGE_HTTPS_PORT:-443}"

"${ROOT_DIR}/scripts/init-runtime.sh" >/dev/null

docker compose -f compose.yaml -f compose.edge.caddy.yaml config >/dev/null
docker compose -f compose.yaml -f compose.edge.caddy.yaml pull gateway edge
docker compose -f compose.yaml -f compose.edge.caddy.yaml up -d --remove-orphans

echo "HTTPS Edge 已启动：https://${DSH_DOMAIN}"
