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
"${ROOT_DIR}/scripts/init-runtime.sh"

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
CONFIG_FILE="${RUNTIME_ABS}/tinyauth/config.yml"
has_tinyauth_user "${CONFIG_FILE}" || {
    echo "缺少登录用户，请先执行 ./scripts/create-user.sh。" >&2
    exit 1
}

# update.sh passes the pre-pull image ID. A direct rebuild captures the image
# currently used by this Compose project itself.
OLD_DSH_IMAGE_ID="${OLD_DSH_IMAGE_ID:-$(docker compose images -q dsh 2>/dev/null | head -n 1 || true)}"

echo "停止并删除当前 Compose 项目的旧容器/网络..."
docker compose down --remove-orphans --rmi local

# --rmi local is the primary cleanup path for Compose-built images. Keep the
# captured pre-update ID as a compatibility fallback in case an older Compose
# release/tagging strategy leaves it behind.
if [[ -n "${OLD_DSH_IMAGE_ID}" ]] && docker image inspect "${OLD_DSH_IMAGE_ID}" >/dev/null 2>&1; then
    echo "清理残留旧 DSH 镜像：${OLD_DSH_IMAGE_ID}"
    docker image rm "${OLD_DSH_IMAGE_ID}" >/dev/null 2>&1 || true
fi

echo "拉取外部依赖镜像..."
docker compose pull tinyauth gateway

echo "构建新的 DSH 镜像..."
docker compose build --pull dsh

echo "启动新容器..."
docker compose up -d --remove-orphans

docker image prune -f >/dev/null 2>&1 || true

echo
echo "重建完成；持久化数据保留：${RUNTIME_ABS}"
docker compose ps
