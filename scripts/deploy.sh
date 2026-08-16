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

#:
#   ./scripts/deploy.sh
#   ./scripts/deploy.sh local [port]
#   ./scripts/deploy.sh domain-http dsh.example.com [port]
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
fi

if [[ "${mode}" == "domain-https" ]]; then
    if [[ -z "${DSH_DOMAIN:-}" ]]; then
        read -r -p "域名（例如 dsh.example.com）: " DSH_DOMAIN
        validate_domain "${DSH_DOMAIN}"
        set_env_value "${ROOT_DIR}" DSH_DOMAIN "${DSH_DOMAIN}"
    fi

    if [[ -z "${ACME_EMAIL:-}" ]]; then
        read -r -p "ACME 邮箱: " ACME_EMAIL
        [[ -n "${ACME_EMAIL}" ]] || {
            echo "ACME 邮箱不能为空。" >&2
            exit 1
        }
        set_env_value "${ROOT_DIR}" ACME_EMAIL "${ACME_EMAIL}"
    fi
fi

load_env "${ROOT_DIR}"
validate_mode_config

# IMPORTANT: reject port conflicts before pulling/building anything expensive.
echo "执行端口预检..."
preflight_access_ports "${ROOT_DIR}"

"${ROOT_DIR}/scripts/init-runtime.sh"

echo
echo "Access mode : ${ACCESS_MODE:-local}"
echo "Public URL  : $(public_url)"
echo "Image mode  : ${DSH_IMAGE_MODE:-auto}"
echo

if [[ "${ACCESS_MODE:-local}" == "domain-http" ]]; then
    echo >&2
    echo "警告：当前为 domain-http（No HTTPS）。" >&2
    echo "Basic Auth 凭据通过明文 HTTP 传输，只应在可信网络/受控环境使用。" >&2
fi

active_compose config >/dev/null

echo "拉取 Caddy 网关镜像..."
pull_gateway_images

USERS_FILE="$(users_file "${ROOT_DIR}")"
if ! has_auth_user "${USERS_FILE}"; then
    echo
    echo "首次部署需要创建登录用户。"
    "${ROOT_DIR}/scripts/create-user.sh"
fi

echo "验证 Caddy 配置..."
validate_all_caddy_or_die

prepare_dsh_image

echo "启动服务..."
active_compose up -d --remove-orphans

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"

printf '\n部署完成。\n'
printf 'Repository : %s\n' "${ROOT_DIR}"
printf 'Runtime    : %s\n' "${RUNTIME_ABS}"
printf 'Mode       : %s\n' "${ACCESS_MODE:-local}"
printf 'Image mode : %s\n' "${DSH_DELIVERY:-unknown}"
printf 'Public URL : %s\n' "$(public_url)"
printf 'Workspace  : %s <-> /workspace\n' "${RUNTIME_ABS}/workspace"

echo
"${ROOT_DIR}/scripts/check.sh"

printf '\n仓库更新：./scripts/update.sh\n'
