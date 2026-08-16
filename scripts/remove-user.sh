#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
[[ -f .env ]] && load_env "${ROOT_DIR}"
"${ROOT_DIR}/scripts/init-runtime.sh" >/dev/null
RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
CONFIG_FILE="${RUNTIME_ABS}/tinyauth/config.yml"

username="${1:-}"
if [[ -z "${username}" ]]; then
    read -r -p "要删除的用户名: " username
fi
[[ -n "${username}" ]] || { echo "用户名不能为空。" >&2; exit 1; }

declare -a records=()
found=false
while IFS= read -r line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ "${trimmed}" == -* ]] || continue
    item="${trimmed#-}"
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item#\"}"; item="${item%\"}"
    item="${item#\'}"; item="${item%\'}"
    [[ "${item}" == *:'$2'* ]] || continue
    if [[ "${item%%:*}" == "${username}" ]]; then
        found=true
    else
        records+=("${item}")
    fi
done < "${CONFIG_FILE}"

[[ "${found}" == true ]] || { echo "用户 '${username}' 不存在。" >&2; exit 1; }

umask 077
{
    echo "auth:"
    echo "  users:"
    for item in "${records[@]}"; do
        printf '    - "%s"\n' "${item}"
    done
} > "${CONFIG_FILE}"
if [[ "${EUID}" -eq 0 ]]; then
    chown "${RUNTIME_UID:-1000}:${RUNTIME_GID:-1000}" "${CONFIG_FILE}"
fi
chmod 0600 "${CONFIG_FILE}"

echo "用户 '${username}' 已删除。"
echo "若服务正在运行，执行 docker compose restart tinyauth gateway 使配置立即生效。"
