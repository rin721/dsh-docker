#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker

"${ROOT_DIR}/scripts/cleanup-legacy.sh"
[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"
validate_mode_config
"${ROOT_DIR}/scripts/init-runtime.sh"

USERS_FILE="$(users_file "${ROOT_DIR}")"
has_auth_user "${USERS_FILE}" || {
    echo "缺少登录用户，请先执行 ./scripts/create-user.sh。" >&2
    exit 1
}

OLD_DSH_IMAGE_ID="${OLD_DSH_IMAGE_ID:-$(docker compose images -q dsh 2>/dev/null | head -n 1 || true)}"

echo "停止并删除当前 Compose 项目的旧容器/网络/本地构建镜像..."
active_compose down --remove-orphans --rmi local || \
    docker compose down --remove-orphans --rmi local || true

if [[ -n "${OLD_DSH_IMAGE_ID}" ]] && docker image inspect "${OLD_DSH_IMAGE_ID}" >/dev/null 2>&1; then
    echo "清理残留旧 DSH 镜像：${OLD_DSH_IMAGE_ID}"
    docker image rm "${OLD_DSH_IMAGE_ID}" >/dev/null 2>&1 || true
fi

echo "拉取网关镜像..."
pull_mode_images

echo "验证 Caddy 配置..."
validate_all_caddy_or_die

echo "构建新的 DSH 镜像..."
active_compose build --pull dsh

echo "启动新容器..."
active_compose up -d --remove-orphans

docker image prune -f >/dev/null 2>&1 || true

echo
echo "重建完成；.runtime 持久化数据未删除。"
echo "Mode      : ${ACCESS_MODE:-local}"
echo "Public URL: $(public_url)"
active_compose ps
