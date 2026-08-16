#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
[[ -f .env ]] && load_env "${ROOT_DIR}"
FILE="$(users_file "${ROOT_DIR}")"
if [[ ! -s "${FILE}" ]]; then
    echo "暂无登录用户。"
    exit 0
fi
awk 'NF >= 2 { print $1 }' "${FILE}"
