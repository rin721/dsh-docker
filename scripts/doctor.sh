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
    warn ".env 不存在；deploy.sh 会自动创建"
    load_env "${ROOT_DIR}" || true
fi

if validate_access_mode "${ACCESS_MODE:-local}" >/dev/null 2>&1; then
    ok "ACCESS_MODE=${ACCESS_MODE:-local}"
else
    bad "invalid ACCESS_MODE"
fi

if validate_image_mode "${DSH_IMAGE_MODE:-auto}" >/dev/null 2>&1; then
    ok "DSH_IMAGE_MODE=${DSH_IMAGE_MODE:-auto}"
else
    bad "invalid DSH_IMAGE_MODE"
fi

if validate_mode_config >/dev/null 2>&1; then
    ok "access config"
else
    bad "access config invalid"
fi

if preflight_access_ports "${ROOT_DIR}" >/dev/null 2>&1; then
    ok "host ports available / owned by this project"
else
    bad "host port conflict"
fi

FILE="$(users_file "${ROOT_DIR}")"
if has_auth_user "${FILE}"; then ok "Basic Auth user exists"; else warn "尚未创建认证用户"; fi

if active_compose config >/dev/null 2>&1; then ok "compose config"; else bad "compose config invalid"; fi

if [[ "${DSH_IMAGE_MODE:-auto}" != "build" ]]; then
    echo "DSH image    : ${DSH_IMAGE:-ghcr.io/rin721/dsh-docker:latest}"
fi

if [[ "${ACCESS_MODE:-local}" == "domain-http" ]]; then
    warn "domain-http 是明文 HTTP；Basic Auth 只适合可信网络/受控环境"
fi

(( errors == 0 )) || exit 1
