#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker
[[ -f .env ]] && load_env "${ROOT_DIR}"

docker compose ps

echo
FILE="$(users_file "${ROOT_DIR}")"
count=0
[[ -f "${FILE}" ]] && count="$(awk 'NF >= 2 { n++ } END { print n+0 }' "${FILE}")"
echo "Auth users : ${count}"
echo "Runtime    : $(runtime_dir_abs "${ROOT_DIR}")"
echo "Gateway    : ${BIND_ADDRESS:-127.0.0.1}:${DSH_PORT:-3080}"

host="${BIND_ADDRESS:-127.0.0.1}"
[[ "${host}" == "0.0.0.0" ]] && host="127.0.0.1"
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://${host}:${DSH_PORT:-3080}/" 2>/dev/null || true)"
if [[ "${code}" == "401" ]]; then
    echo "Gateway HTTP: 401 (正常：未携带凭据被认证层拒绝)"
elif [[ -n "${code}" ]]; then
    echo "Gateway HTTP: ${code}"
else
    echo "Gateway HTTP: 无法连接"
fi
