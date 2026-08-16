#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
load_env "${ROOT_DIR}"

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
RUNTIME_UID="${RUNTIME_UID:-1000}"
RUNTIME_GID="${RUNTIME_GID:-1000}"

mkdir -p \
    "${RUNTIME_ABS}/workspace" \
    "${RUNTIME_ABS}/dsh-home" \
    "${RUNTIME_ABS}/tinyauth/data" \
    "${RUNTIME_ABS}/edge/caddy/data" \
    "${RUNTIME_ABS}/edge/caddy/config"

if [[ ! -f "${RUNTIME_ABS}/tinyauth/config.yml" ]]; then
    umask 077
    cat > "${RUNTIME_ABS}/tinyauth/config.yml" <<'YAML'
auth:
  users: []
YAML
fi

if [[ "${EUID}" -eq 0 ]]; then
    chown -R "${RUNTIME_UID}:${RUNTIME_GID}" \
        "${RUNTIME_ABS}/workspace" \
        "${RUNTIME_ABS}/dsh-home" \
        "${RUNTIME_ABS}/tinyauth/data"
    chown "${RUNTIME_UID}:${RUNTIME_GID}" "${RUNTIME_ABS}/tinyauth/config.yml"
else
    echo "提示：当前不是 root。容器默认以 UID/GID ${RUNTIME_UID}:${RUNTIME_GID} 访问 DSH/Tinyauth 数据。" >&2
    echo "若出现 Permission denied，请修正 .runtime 目录的数值 UID/GID，或用 root/sudo 部署。" >&2
fi

chmod 0750 "${RUNTIME_ABS}/workspace" "${RUNTIME_ABS}/tinyauth/data"
chmod 0700 "${RUNTIME_ABS}/dsh-home"
chmod 0600 "${RUNTIME_ABS}/tinyauth/config.yml"
chmod 0750 "${RUNTIME_ABS}/edge/caddy/data" "${RUNTIME_ABS}/edge/caddy/config"

echo "Repository runtime: ${RUNTIME_ABS}"
