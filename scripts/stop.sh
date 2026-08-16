#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

[[ -f .env ]] && load_env "${ROOT_DIR}"
active_compose down --remove-orphans || docker compose down --remove-orphans
printf '服务已停止；.runtime 数据未删除。\n'
