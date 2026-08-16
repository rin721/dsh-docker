#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

require_docker
"${ROOT_DIR}/scripts/cleanup-legacy.sh"

if [[ ! -f .env ]]; then
    cp .env.example .env
    echo "已从 .env.example 创建本地 .env。"
fi

load_env "${ROOT_DIR}"
"${ROOT_DIR}/scripts/init-runtime.sh"

DSH_PORT="${DSH_PORT:-3080}"
validate_port DSH_PORT "${DSH_PORT}"

if [[ "${BIND_ADDRESS:-127.0.0.1}" == "0.0.0.0" ]]; then
    echo >&2
    echo "警告：Gateway 将监听所有宿主机网卡。" >&2
    echo "HTTP Basic Auth 不应通过公网明文 HTTP 使用；公网部署请在前面提供 HTTPS。" >&2
fi

docker compose config >/dev/null

echo "拉取 Gateway 镜像..."
docker compose pull gateway

USERS_FILE="$(users_file "${ROOT_DIR}")"
if ! has_auth_user "${USERS_FILE}"; then
    echo
    echo "首次部署需要创建登录用户。"
    "${ROOT_DIR}/scripts/create-user.sh"
fi

echo "验证 Gateway 配置..."
validate_gateway_config_or_die

echo "构建 DSH 开发镜像..."
docker compose build --pull dsh

echo "启动服务..."
docker compose up -d --remove-orphans

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"

printf '\n部署完成。\n'
printf 'Repository : %s\n' "${ROOT_DIR}"
printf 'Runtime    : %s\n' "${RUNTIME_ABS}"
printf 'Gateway    : %s:%s\n' "${BIND_ADDRESS:-127.0.0.1}" "${DSH_PORT}"

echo
"${ROOT_DIR}/scripts/check.sh"

printf '\n仓库更新并重建：./scripts/update.sh\n'
