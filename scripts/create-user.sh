#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/auth/tinyauth.yml"
IMAGE="ghcr.io/tinyauthapp/tinyauth:v5.1.3"

command -v docker >/dev/null 2>&1 || {
    echo "未找到 docker。" >&2
    exit 1
}

read -r -p "用户名: " username
[[ -n "${username}" ]] || { echo "用户名不能为空。" >&2; exit 1; }
[[ "${username}" != *:* ]] || { echo "用户名不能包含冒号 (:)." >&2; exit 1; }

read -r -s -p "密码: " password
echo
read -r -s -p "再次输入密码: " password2
echo

[[ -n "${password}" ]] || { echo "密码不能为空。" >&2; exit 1; }
[[ "${password}" == "${password2}" ]] || { echo "两次密码不一致。" >&2; exit 1; }

# Tinyauth 官方 CLI 使用 bcrypt 生成用户。这里不使用 --docker，保留原始 $ bcrypt 字符。
output="$(docker run --rm "${IMAGE}" user create --username "${username}" --password "${password}")"
unset password password2

record="$(printf '%s\n' "${output}" | sed -n 's/^--auth\.users=//p' | tail -n 1)"

if [[ -z "${record}" || "${record}" != "${username}:"\$2* ]]; then
    echo "无法从 Tinyauth CLI 输出中提取 bcrypt 用户记录。原始输出如下：" >&2
    printf '%s\n' "${output}" >&2
    exit 1
fi

mkdir -p "$(dirname "${CONFIG_FILE}")"

# 读取已有用户，替换同名账号；不存在则追加。
declare -a records=()
if [[ -f "${CONFIG_FILE}" ]]; then
    while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]*-[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
            existing="${BASH_REMATCH[1]}"
            existing_name="${existing%%:*}"
            if [[ "${existing_name}" != "${username}" ]]; then
                records+=("${existing}")
            fi
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
echo "已写入 Tinyauth 用户 '${username}'：${CONFIG_FILE}"
echo "密码仅用于生成 bcrypt，本脚本不会保存明文密码。"
