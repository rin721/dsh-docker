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
    echo "已从 .env.example 创建本地 .env（默认使用仓库内 .runtime）。"
fi
load_env "${ROOT_DIR}"

"${ROOT_DIR}/scripts/init-runtime.sh"
RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
CONFIG_FILE="${RUNTIME_ABS}/tinyauth/config.yml"

if ! grep -Eq '^[[:space:]]*-[[:space:]]*"[^:]+:\$2' "${CONFIG_FILE}"; then
    echo
    echo "首次部署需要创建登录用户。"
    "${ROOT_DIR}/scripts/create-user.sh"
fi

DSH_PORT="${DSH_PORT:-3080}"
AUTH_PORT="${AUTH_PORT:-3081}"
for port_name in DSH_PORT AUTH_PORT; do
    port="${!port_name}"
    [[ "${port}" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || {
        echo "${port_name} 必须是 1-65535 的端口。" >&2
        exit 1
    }
done
[[ "${DSH_PORT}" != "${AUTH_PORT}" ]] || { echo "DSH_PORT 与 AUTH_PORT 不能相同。" >&2; exit 1; }

AUTH_URL="${AUTH_URL:-http://127.0.0.1:3081}"
[[ "${AUTH_URL}" =~ ^https?:// ]] || { echo "AUTH_URL 必须以 http:// 或 https:// 开头。" >&2; exit 1; }

if [[ "${BIND_ADDRESS:-127.0.0.1}" == "0.0.0.0" && "${AUTH_URL}" == http://* ]]; then
    echo "警告：登录入口将通过明文 HTTP 对外监听；公网部署建议使用 HTTPS 反向代理。" >&2
fi

docker compose config >/dev/null
docker compose pull tinyauth gateway
docker compose build --pull dsh
docker compose up -d --remove-orphans

printf '\n部署完成。\n'
printf 'Repository : %s\n' "${ROOT_DIR}"
printf 'Runtime    : %s\n' "${RUNTIME_ABS}"
printf 'DSH port   : %s:%s\n' "${BIND_ADDRESS:-127.0.0.1}" "${DSH_PORT}"
printf 'Auth URL   : %s\n' "${AUTH_URL}"
printf '\n更新仓库并重建：./scripts/update.sh\n'
