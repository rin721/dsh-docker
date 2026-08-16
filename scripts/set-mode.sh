#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

[[ $# -ge 1 ]] || {
    echo "用法：" >&2
    echo "  ./scripts/set-mode.sh local [port]" >&2
    echo "  ./scripts/set-mode.sh domain-http dsh.example.com [port]" >&2
    echo "  ./scripts/set-mode.sh domain-https dsh.example.com admin@example.com" >&2
    exit 1
}

[[ -f .env ]] || cp .env.example .env
configure_access_mode "${ROOT_DIR}" "$@"
load_env "${ROOT_DIR}"
validate_mode_config

echo "ACCESS_MODE=${ACCESS_MODE:-local}"
echo "BIND_ADDRESS=${BIND_ADDRESS:-127.0.0.1}"
echo "DSH_PORT=${DSH_PORT:-3080}"
[[ -n "${DSH_DOMAIN:-}" ]] && echo "DSH_DOMAIN=${DSH_DOMAIN}"
[[ -n "${ACME_EMAIL:-}" ]] && echo "ACME_EMAIL=${ACME_EMAIL}"
echo "Public URL=$(public_url)"
