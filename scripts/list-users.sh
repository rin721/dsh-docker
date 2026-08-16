#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
[[ -f .env ]] && load_env "${ROOT_DIR}"
RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
CONFIG_FILE="${RUNTIME_ABS}/tinyauth/config.yml"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "尚无 Tinyauth 配置。"
    exit 0
fi

count=0
while IFS= read -r line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ "${trimmed}" == -* ]] || continue
    item="${trimmed#-}"
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item#\"}"; item="${item%\"}"
    item="${item#\'}"; item="${item%\'}"
    [[ "${item}" == *:'$2'* ]] || continue
    echo "${item%%:*}"
    count=$((count + 1))
done < "${CONFIG_FILE}"

[[ ${count} -gt 0 ]] || echo "尚未创建登录用户。"
