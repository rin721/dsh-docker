#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

require_docker
[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"

validate_mode_config
preflight_access_ports "${ROOT_DIR}"
"${ROOT_DIR}/scripts/init-runtime.sh"

USERS_FILE="$(users_file "${ROOT_DIR}")"
has_auth_user "${USERS_FILE}" || {
    echo "缺少登录用户，请先执行 ./scripts/create-user.sh。" >&2
    exit 1
}

active_compose config >/dev/null

echo "更新 Caddy 网关镜像..."
pull_gateway_images

echo "验证 Caddy 配置..."
validate_all_caddy_or_die

prepare_dsh_image

echo "应用新版本..."
active_compose up -d --remove-orphans

# Only prune dangling images after the new stack is already running.
docker image prune -f >/dev/null 2>&1 || true

echo
echo "更新/重建完成；.runtime 持久化数据未删除。"
echo "Public URL : $(public_url)"
active_compose ps
