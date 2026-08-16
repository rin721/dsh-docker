#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker

[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"
"${ROOT_DIR}/scripts/init-runtime.sh" >/dev/null

USERS_FILE="$(users_file "${ROOT_DIR}")"
CADDY_IMAGE="caddy:${GATEWAY_CADDY_VERSION:-2.11.4}"
BCRYPT_COST="${AUTH_BCRYPT_COST:-14}"
[[ "${BCRYPT_COST}" =~ ^[0-9]+$ ]] && (( BCRYPT_COST >= 4 && BCRYPT_COST <= 31 )) || {
    echo "AUTH_BCRYPT_COST 必须是 4-31 的整数。" >&2
    exit 1
}

read -r -p "用户名: " username
[[ -n "${username}" ]] || { echo "用户名不能为空。" >&2; exit 1; }
[[ "${username}" =~ ^[A-Za-z0-9._@-]+$ ]] || {
    echo "用户名仅允许字母、数字、点、下划线、@、连字符。" >&2
    exit 1
}

read -r -s -p "密码: " password
echo
read -r -s -p "再次输入密码: " password2
echo
[[ -n "${password}" ]] || { echo "密码不能为空。" >&2; exit 1; }
[[ "${password}" == "${password2}" ]] || { echo "两次密码不一致。" >&2; exit 1; }

# 不使用 --plaintext 参数，避免把密码出现在 docker/进程参数中；通过 stdin 传给 Caddy。
hash="$({ printf '%s\n' "${password}" | docker run --rm -i --entrypoint caddy "${CADDY_IMAGE}" \
    hash-password --algorithm bcrypt --bcrypt-cost "${BCRYPT_COST}"; } | tr -d '\r\n')"
unset password password2

[[ "${hash}" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]] || {
    echo "Caddy 未返回合法 bcrypt Hash。" >&2
    exit 1
}

# 同名用户 = 修改密码；不存在 = 新增。
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
if [[ -f "${USERS_FILE}" ]]; then
    awk -v user="${username}" '$1 != user { print }' "${USERS_FILE}" > "${tmp}"
fi
printf '%s %s\n' "${username}" "${hash}" >> "${tmp}"
LC_ALL=C sort -k1,1 "${tmp}" > "${USERS_FILE}"
chmod 0644 "${USERS_FILE}"

echo
echo "用户 '${username}' 已创建/更新。"
echo "认证文件：${USERS_FILE}"
echo "明文密码未写入磁盘。"
echo
if [[ -n "$(docker compose ps -a -q gateway 2>/dev/null || true)" ]]; then
    echo "重新创建 Gateway 以加载新认证配置..."
    docker compose up -d --force-recreate gateway
fi
