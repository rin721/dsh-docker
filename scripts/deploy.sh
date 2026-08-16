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

# 可选：
#   ./scripts/deploy.sh local
#   ./scripts/deploy.sh domain-http dsh.example.com
#   ./scripts/deploy.sh domain-https dsh.example.com admin@example.com
if [[ $# -gt 0 ]]; then
    configure_access_mode "${ROOT_DIR}" "$@"
fi

load_env "${ROOT_DIR}"

mode="${ACCESS_MODE:-local}"
validate_access_mode "${mode}"

if [[ "${mode}" == "domain-http" && -z "${DSH_DOMAIN:-}" ]]; then
    read -r -p "域名（例如 dsh.example.com）: " DSH_DOMAIN
    validate_domain "${DSH_DOMAIN}"
    set_env_value "${ROOT_DIR}" DSH_DOMAIN "${DSH_DOMAIN}"
    export DSH_DOMAIN
fi

if [[ "${mode}" == "domain-https" ]]; then
    if [[ -z "${DSH_DOMAIN:-}" ]]; then
        read -r -p "域名（例如 dsh.example.com）: " DSH_DOMAIN
        validate_domain "${DSH_DOMAIN}"
        set_env_value "${ROOT_DIR}" DSH_DOMAIN "${DSH_DOMAIN}"
        export DSH_DOMAIN
    fi

    if [[ -z "${ACME_EMAIL:-}" ]]; then
        read -r -p "ACME 邮箱: " ACME_EMAIL
        [[ -n "${ACME_EMAIL}" ]] || {
            echo "ACME 邮箱不能为空。" >&2
            exit 1
        }
        set_env_value "${ROOT_DIR}" ACME_EMAIL "${ACME_EMAIL}"
        export ACME_EMAIL
    fi
fi

# 参数模式可能刚刚写入 .env，重新读取确保所有变量一致。
load_env "${ROOT_DIR}"
validate_mode_config
"${ROOT_DIR}/scripts/init-runtime.sh"

echo "Access mode : ${ACCESS_MODE:-local}"
echo "Public URL  : $(public_url)"
echo

if [[ "${ACCESS_MODE:-local}" == "domain-http" ]]; then
    echo >&2
    echo "警告：当前为 domain-http（No HTTPS）。" >&2
    echo "Basic Auth 凭据会通过明文 HTTP 传输，只应在可信网络/受控环境使用。" >&2
fi

active_compose config >/dev/null

echo "拉取网关镜像..."
pull_mode_images

USERS_FILE="$(users_file "${ROOT_DIR}")"
if ! has_auth_user "${USERS_FILE}"; then
    echo
    echo "首次部署需要创建登录用户。"
    "${ROOT_DIR}/scripts/create-user.sh"
fi

echo "验证 Caddy 配置..."
validate_all_caddy_or_die

echo "构建 DSH 开发镜像..."
active_compose build --pull dsh

echo "启动服务..."
active_compose up -d --remove-orphans

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"

printf '\n部署完成。\n'
printf 'Repository : %s\n' "${ROOT_DIR}"
printf 'Runtime    : %s\n' "${RUNTIME_ABS}"
printf 'Mode       : %s\n' "${ACCESS_MODE:-local}"
printf 'Public URL : %s\n' "$(public_url)"
printf 'Workspace  : %s <-> /workspace\n' "${RUNTIME_ABS}/workspace"

echo
"${ROOT_DIR}/scripts/check.sh"

printf '\n仓库更新并重建：./scripts/update.sh\n'
