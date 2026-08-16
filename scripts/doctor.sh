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
    load_env "${ROOT_DIR}" || true
fi

if validate_port DSH_PORT "${DSH_PORT:-3080}" >/dev/null 2>&1; then ok "DSH_PORT=${DSH_PORT:-3080}"; else bad "invalid DSH_PORT"; fi

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
echo "Runtime: ${RUNTIME_ABS}"
FILE="$(users_file "${ROOT_DIR}")"
if has_auth_user "${FILE}"; then ok "至少存在一个 Basic Auth 用户"; else warn "尚未创建认证用户"; fi

if docker compose config >/dev/null 2>&1; then ok "compose config"; else bad "compose config invalid"; fi

if [[ -s "${FILE}" ]] && docker info >/dev/null 2>&1; then
    if docker image inspect "$(gateway_image)" >/dev/null 2>&1; then
        if validate_gateway_config >/dev/null 2>&1; then
            ok "Caddy gateway config"
        else
            bad "Caddy gateway config invalid"
        fi
    else
        warn "Gateway 镜像尚未拉取；deploy.sh 会先拉取后验证"
    fi
fi

if [[ "${BIND_ADDRESS:-127.0.0.1}" == "0.0.0.0" ]]; then
    warn "BIND_ADDRESS=0.0.0.0；若跨不可信网络访问，请务必在前面提供 HTTPS"
fi

(( errors == 0 )) || exit 1
