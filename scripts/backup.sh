#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

[[ -f .env ]] || {
    echo "缺少 .env；请先部署。" >&2
    exit 1
}
load_env "${ROOT_DIR}"

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
RUNTIME_PARENT="$(dirname "${RUNTIME_ABS}")"
RUNTIME_NAME="$(basename "${RUNTIME_ABS}")"
timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"
output="${1:-${ROOT_DIR}/dsh-docker-backup-${timestamp}.tar.gz}"

umask 077
tar -czf "${output}" \
    -C "${ROOT_DIR}" .env \
    -C "${RUNTIME_PARENT}" "${RUNTIME_NAME}"

chmod 0600 "${output}"
echo "Backup: ${output}"
echo "注意：备份包含 SSH 私钥、Git/CLI 凭据和 DSH 凭据，请按敏感文件保管。"
