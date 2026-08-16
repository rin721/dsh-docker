#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker
[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"

: "${DSH_DOMAIN:?启用 HTTPS edge 时必须设置 DSH_DOMAIN}"
: "${AUTH_DOMAIN:?启用 HTTPS edge 时必须设置 AUTH_DOMAIN}"
: "${ACME_EMAIL:?启用 HTTPS edge 时必须设置 ACME_EMAIL}"
[[ "${TINYAUTH_SECURE_COOKIE:-false}" == "true" ]] || {
    echo "TINYAUTH_SECURE_COOKIE 必须为 true。" >&2
    exit 1
}
[[ "${AUTH_URL:-}" == "https://${AUTH_DOMAIN}" ]] || {
    echo "AUTH_URL 应设置为 https://${AUTH_DOMAIN}" >&2
    exit 1
}

# Tinyauth shares authentication cookies across sibling subdomains. Warn rather
# than hard-fail so advanced users can intentionally use another arrangement.
auth_parent="${AUTH_DOMAIN#*.}"
if [[ "${DSH_DOMAIN}" != *."${auth_parent}" ]]; then
    echo "警告：DSH_DOMAIN 与 AUTH_DOMAIN 看起来不是同一父域。跨子域认证 Cookie 可能无法正常工作。" >&2
fi

"${ROOT_DIR}/scripts/init-runtime.sh"
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge config >/dev/null
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge pull edge
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge up -d edge

echo "HTTPS edge 已启动："
echo "  DSH:  https://${DSH_DOMAIN}"
echo "  Auth: https://${AUTH_DOMAIN}"
