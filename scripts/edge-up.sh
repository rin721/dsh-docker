#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

require_docker
[[ -f .env ]] || { echo "缺少 .env，请先执行 ./scripts/deploy.sh。" >&2; exit 1; }
load_env "${ROOT_DIR}"

[[ "${ACCESS_MODE:-local}" == "domain-https" ]] || {
    echo "edge-up.sh 仅用于 ACCESS_MODE=domain-https。" >&2
    echo "可直接执行：./scripts/deploy.sh domain-https dsh.example.com admin@example.com" >&2
    exit 1
}

validate_mode_config
"${ROOT_DIR}/scripts/init-runtime.sh" >/dev/null

docker compose -f compose.yaml -f compose.edge.caddy.yaml config >/dev/null
docker compose -f compose.yaml -f compose.edge.caddy.yaml pull gateway edge

echo "验证 HTTPS Edge 配置..."
validate_edge_config_or_die

docker compose -f compose.yaml -f compose.edge.caddy.yaml up -d --remove-orphans

echo "HTTPS Edge 已启动：$(public_url)"
