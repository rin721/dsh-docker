#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

errors=0
ok() { printf '[OK] %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*" >&2; errors=$((errors + 1)); }
warn() { printf '[WARN] %s\n' "$*" >&2; }

if command -v docker >/dev/null 2>&1; then ok "docker found"; else bad "docker not found"; fi
if docker compose version >/dev/null 2>&1; then ok "docker compose v2"; else bad "docker compose v2 unavailable"; fi
if docker info >/dev/null 2>&1; then ok "docker daemon reachable"; else bad "docker daemon unavailable"; fi

if [[ -f .env ]]; then
    ok ".env exists"
    load_env "${ROOT_DIR}"
else
    warn ".env 不存在；deploy.sh 会从 .env.example 自动创建"
fi

if validate_access_mode "${ACCESS_MODE:-local}" >/dev/null 2>&1; then
    ok "ACCESS_MODE=${ACCESS_MODE:-local}"
else
    bad "invalid ACCESS_MODE"
fi

if validate_mode_config >/dev/null 2>&1; then
    ok "access mode config"
else
    bad "access mode config invalid"
fi

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
echo "Runtime: ${RUNTIME_ABS}"

FILE="$(users_file "${ROOT_DIR}")"
if has_auth_user "${FILE}"; then ok "至少存在一个 Basic Auth 用户"; else warn "尚未创建认证用户"; fi

if active_compose config >/dev/null 2>&1; then ok "compose config"; else bad "compose config invalid"; fi

if [[ -s "${FILE}" ]] && docker info >/dev/null 2>&1; then
    if docker image inspect "$(gateway_image)" >/dev/null 2>&1; then
        if validate_gateway_config_or_die >/dev/null 2>&1; then
            ok "Caddy gateway config"
        else
            bad "Caddy gateway config invalid"
        fi
    else
        warn "Gateway 镜像尚未拉取；deploy.sh 会自动拉取"
    fi
fi

if [[ "${ACCESS_MODE:-local}" == "domain-http" ]]; then
    warn "domain-http 使用明文 HTTP；Basic Auth 只适用于可信网络/受控环境"
fi

if [[ "${DSH_HTTP_COMPAT_SHIM:-true}" == "true" ]]; then
    ok "remote HTTP crypto.randomUUID compatibility shim enabled"
else
    warn "remote HTTP compatibility shim disabled"
fi

(( errors == 0 )) || exit 1
