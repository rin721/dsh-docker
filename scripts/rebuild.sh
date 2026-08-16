#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

require_docker
[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"

validate_core_config
preflight_core_port "${ROOT_DIR}"
"${ROOT_DIR}/scripts/init-runtime.sh"

USERS_FILE="$(users_file "${ROOT_DIR}")"
has_auth_user "${USERS_FILE}" || {
    echo "缺少登录用户，请先执行 ./scripts/create-user.sh。" >&2
    exit 1
}

docker compose config >/dev/null

echo "更新 Gateway 镜像..."
docker compose pull gateway

echo "验证 Gateway 配置..."
validate_gateway_config_or_die

prepare_dsh_image

echo "应用新版本..."
docker compose up -d --remove-orphans

docker image prune -f >/dev/null 2>&1 || true

echo
echo "重建完成；.runtime 数据未删除。"
docker compose ps
