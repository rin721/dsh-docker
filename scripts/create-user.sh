#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker
load_env "${ROOT_DIR}"

"${ROOT_DIR}/scripts/init-runtime.sh" >/dev/null
RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
CONFIG_FILE="${RUNTIME_ABS}/tinyauth/config.yml"
IMAGE="ghcr.io/tinyauthapp/tinyauth:${TINYAUTH_VERSION:-v5.1.3}"

read -r -p "用户名: " username
[[ -n "${username}" ]] || { echo "用户名不能为空。" >&2; exit 1; }
[[ "${username}" != *:* ]] || { echo "用户名不能包含冒号 (:)." >&2; exit 1; }

read -r -s -p "密码: " password
echo
read -r -s -p "再次输入密码: " password2
echo
[[ -n "${password}" ]] || { echo "密码不能为空。" >&2; exit 1; }
[[ "${password}" == "${password2}" ]] || { echo "两次密码不一致。" >&2; exit 1; }

output="$(docker run --rm "${IMAGE}" user create --username "${username}" --password "${password}")"
unset password password2

# 兼容 Tinyauth 不同版本的输出格式，同时清理 CRLF。
clean_output="$(printf '%s\n' "${output}" | tr -d '\r')"

record=""

while IFS= read -r line; do
    case "${line}" in
        TINYAUTH_AUTH_USERS=*)
            record="${line#TINYAUTH_AUTH_USERS=}"
            break
            ;;
        --auth.users=*)
            record="${line#--auth.users=}"
            break
            ;;
    esac
done <<< "${clean_output}"

if [[ -z "${record}" || "${record}" != "${username}:"\$2* ]]; then
    echo "无法从 Tinyauth CLI 输出中提取 bcrypt 用户记录。" >&2
    printf '%s\n' "${output}" >&2
    exit 1
fi

declare -a records=()
if [[ -f "${CONFIG_FILE}" ]]; then
    while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]*-[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
            existing="${BASH_REMATCH[1]}"
            existing_name="${existing%%:*}"
            [[ "${existing_name}" == "${username}" ]] || records+=("${existing}")
        fi
    done < "${CONFIG_FILE}"
fi
records+=("${record}")

umask 077
{
    echo "auth:"
    echo "  users:"
    for item in "${records[@]}"; do
        printf '    - "%s"\n' "${item}"
    done
} > "${CONFIG_FILE}"
chmod 600 "${CONFIG_FILE}"

echo "用户 '${username}' 已写入：${CONFIG_FILE}"
echo "明文密码不会保存。"
