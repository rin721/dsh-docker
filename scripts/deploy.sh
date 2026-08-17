#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

# Self-heal host filesystem modes when this script was invoked as
# `bash scripts/deploy.sh` from a checkout whose executable bits were lost.
bash "${ROOT_DIR}/scripts/repair-permissions.sh" >/dev/null 2>&1 || true

require_docker
bash "${ROOT_DIR}/scripts/cleanup-legacy.sh"

if [[ ! -f .env ]]; then
    cp .env.example .env
    echo "已从 .env.example 创建本地 .env。"
fi

load_env "${ROOT_DIR}"
validate_core_config

echo "执行端口预检..."
preflight_core_port "${ROOT_DIR}"

bash "${ROOT_DIR}/scripts/init-runtime.sh"

# Preserve pre-v5 container identity/config before it can be replaced.
bash "${ROOT_DIR}/scripts/migrate-home-state.sh"

echo
echo "Core listen : ${BIND_ADDRESS:-127.0.0.1}:${DSH_PORT:-3080}"
echo "Image mode  : ${DSH_IMAGE_MODE:-auto}"
echo

if [[ "${BIND_ADDRESS:-127.0.0.1}" == "0.0.0.0" ]]; then
    echo "警告：Core 正在监听所有宿主机网卡。" >&2
    echo "如果前面使用 Nginx/1Panel，通常建议保持 BIND_ADDRESS=127.0.0.1。" >&2
fi

docker compose config >/dev/null

echo "拉取 Gateway 镜像..."
docker compose pull gateway

USERS_FILE="$(users_file "${ROOT_DIR}")"
if ! has_auth_user "${USERS_FILE}"; then
    echo
    echo "首次部署需要创建登录用户。"
    bash "${ROOT_DIR}/scripts/create-user.sh"
fi

echo "验证 Gateway 配置..."
validate_gateway_config_or_die

prepare_dsh_image

echo "启动服务..."
docker compose up -d --remove-orphans

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"

printf '\n部署完成。\n'
printf 'Repository : %s\n' "${ROOT_DIR}"
printf 'Runtime    : %s\n' "${RUNTIME_ABS}"
printf 'Core       : %s:%s\n' "${BIND_ADDRESS:-127.0.0.1}" "${DSH_PORT:-3080}"
printf 'Workspace  : %s <-> /workspace\n' "${RUNTIME_ABS}/workspace"

echo
echo "你的反向代理上游地址：http://127.0.0.1:${DSH_PORT:-3080}"
echo

bash "${ROOT_DIR}/scripts/check.sh"
