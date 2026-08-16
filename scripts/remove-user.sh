#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker
[[ -f .env ]] && load_env "${ROOT_DIR}"
FILE="$(users_file "${ROOT_DIR}")"
[[ -s "${FILE}" ]] || { echo "暂无登录用户。"; exit 0; }

read -r -p "要删除的用户名: " username
[[ "${username}" =~ ^[A-Za-z0-9._@-]+$ ]] || { echo "用户名格式无效。" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
awk -v user="${username}" '$1 != user { print }' "${FILE}" > "${tmp}"

if cmp -s "${FILE}" "${tmp}"; then
    echo "用户 '${username}' 不存在。"
    exit 1
fi

mv "${tmp}" "${FILE}"
trap - EXIT
chmod 0644 "${FILE}"
echo "已删除用户 '${username}'。"

if [[ ! -s "${FILE}" ]]; then
    echo "警告：当前已经没有登录用户，Gateway 下一次加载配置会失败。请立即创建至少一个用户。" >&2
fi

if docker compose ps --status running gateway 2>/dev/null | grep -q gateway; then
    if [[ -s "${FILE}" ]]; then
        docker compose up -d --force-recreate gateway
    else
        docker compose stop gateway
    fi
fi
