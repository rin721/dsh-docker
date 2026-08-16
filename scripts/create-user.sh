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
[[ "${username}" =~ ^[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}$ ]] || {
    echo "用户名仅允许 1-64 位字母、数字、点、下划线、@、+、-，且必须以字母或数字开头。" >&2
    exit 1
}

read -r -s -p "密码: " password
echo
read -r -s -p "再次输入密码: " password2
echo
[[ -n "${password}" ]] || { echo "密码不能为空。" >&2; exit 1; }
[[ "${password}" == "${password2}" ]] || { echo "两次密码不一致。" >&2; exit 1; }

# Use Tinyauth's own CLI to generate the bcrypt hash. Capture both stdout and
# stderr because CLI presentation/streams can change between patch releases.
output="$(
    docker run --rm \
        "${IMAGE}" \
        user create \
        --username "${username}" \
        --password "${password}" \
        2>&1
)"
unset password password2

# Do not depend on the human-readable CLI labels such as
# TINYAUTH_AUTH_USERS=..., --auth.users=..., or the YAML preview. Extract the
# bcrypt token itself. A standard bcrypt string is exactly 60 characters.
hash="$(
    printf '%s\n' "${output}" \
        | tr -d '\r' \
        | LC_ALL=C grep -oE '\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}' \
        | sed -n '1p' \
        || true
)"

if [[ -z "${hash}" ]]; then
    echo "无法从 Tinyauth CLI 输出中提取 bcrypt Hash。" >&2
    echo "Tinyauth 原始输出：" >&2
    printf '%s\n' "${output}" >&2
    exit 1
fi

record="${username}:${hash}"

declare -a records=()
if [[ -f "${CONFIG_FILE}" ]]; then
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "${trimmed}" == -* ]] || continue

        existing="${trimmed#-}"
        existing="${existing#"${existing%%[![:space:]]*}"}"
        existing="${existing#\"}"
        existing="${existing%\"}"
        existing="${existing#\'}"
        existing="${existing%\'}"

        [[ "${existing}" == *:'$2'* ]] || continue
        existing_name="${existing%%:*}"
        [[ "${existing_name}" == "${username}" ]] || records+=("${existing}")
    done < "${CONFIG_FILE}"
fi
records+=("${record}")

mkdir -p "$(dirname "${CONFIG_FILE}")"
umask 077
{
    echo "auth:"
    echo "  users:"
    for item in "${records[@]}"; do
        printf '    - "%s"\n' "${item}"
    done
} > "${CONFIG_FILE}"

# Tinyauth runs as a non-root user in the official image. When deploying as
# root, align ownership with the default container UID/GID used by this stack.
if [[ "${EUID}" -eq 0 ]]; then
    chown "${RUNTIME_UID:-1000}:${RUNTIME_GID:-1000}" "${CONFIG_FILE}"
fi
chmod 0600 "${CONFIG_FILE}"

echo
echo "用户 '${username}' 创建/更新成功。"
echo "配置文件：${CONFIG_FILE}"
echo "明文密码不会保存。"
