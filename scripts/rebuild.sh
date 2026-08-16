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

USERS_FILE="$(users_file "${ROOT_DIR}")"
has_auth_user "${USERS_FILE}" || {
    echo "缺少登录用户，请先执行 ./scripts/create-user.sh。" >&2
    exit 1
}

validate_port DSH_PORT "${DSH_PORT:-3080}"
docker compose config >/dev/null

# update.sh 会传入 pull 前正在运行的 image ID；直接 rebuild 时则现场获取。
OLD_DSH_IMAGE_ID="${OLD_DSH_IMAGE_ID:-$(docker compose images -q dsh 2>/dev/null | head -n 1 || true)}"

EDGE_WAS_RUNNING=0
if [[ -f compose.edge.caddy.yaml ]]; then
    if [[ -n "$(docker compose -f compose.yaml -f compose.edge.caddy.yaml ps --status running -q edge 2>/dev/null || true)" ]]; then
        EDGE_WAS_RUNNING=1
    fi
fi

echo "停止并删除当前 Compose 项目的旧容器/网络/本地构建镜像..."
docker compose down --remove-orphans --rmi local

if [[ -n "${OLD_DSH_IMAGE_ID}" ]] && docker image inspect "${OLD_DSH_IMAGE_ID}" >/dev/null 2>&1; then
    echo "清理残留旧 DSH 镜像：${OLD_DSH_IMAGE_ID}"
    docker image rm "${OLD_DSH_IMAGE_ID}" >/dev/null 2>&1 || true
fi

echo "拉取 Gateway 镜像..."
docker compose pull gateway

echo "验证 Gateway 配置..."
validate_gateway_config_or_die

echo "构建新的 DSH 镜像..."
docker compose build --pull dsh

echo "启动新容器..."
docker compose up -d --remove-orphans

if [[ "${EDGE_WAS_RUNNING}" == "1" ]]; then
    echo "恢复更新前已启用的 HTTPS Edge..."
    "${ROOT_DIR}/scripts/edge-up.sh"
fi

docker image prune -f >/dev/null 2>&1 || true

echo
echo "重建完成；.runtime 持久化数据未删除。"
docker compose ps
