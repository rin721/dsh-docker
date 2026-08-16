#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker

"${ROOT_DIR}/scripts/cleanup-legacy.sh"
load_env "${ROOT_DIR}"

"${ROOT_DIR}/scripts/init-runtime.sh"
RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
CONFIG_FILE="${RUNTIME_ABS}/tinyauth/config.yml"
if ! grep -Eq '^[[:space:]]*-[[:space:]]*"[^:]+:\$2' "${CONFIG_FILE}"; then
    echo "缺少登录用户，请执行 ./scripts/create-user.sh。" >&2
    exit 1
fi

OLD_DSH_IMAGE_ID="${OLD_DSH_IMAGE_ID:-}"

echo "停止并删除当前 Compose 项目的旧容器/网络..."
docker compose down --remove-orphans

if [[ -n "${OLD_DSH_IMAGE_ID}" ]]; then
    echo "删除旧 DSH 镜像：${OLD_DSH_IMAGE_ID}"
    docker image rm -f "${OLD_DSH_IMAGE_ID}" >/dev/null 2>&1 || true
else
    # For compose-managed build images without explicit custom tags.
    docker compose down --rmi local --remove-orphans >/dev/null 2>&1 || true
fi

echo "拉取外部依赖镜像..."
docker compose pull tinyauth gateway

echo "构建新的 DSH 镜像..."
docker compose build --pull dsh

echo "启动新容器..."
docker compose up -d --remove-orphans

# Remove dangling image objects left by the replaced local build, but do not
# remove tagged/shared upstream images.
docker image prune -f >/dev/null 2>&1 || true

echo
echo "重建完成。持久化数据未删除：${RUNTIME_ABS}"
docker compose ps
