#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
load_env "${ROOT_DIR}"

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"

mkdir -p \
    "${RUNTIME_ABS}/workspace" \
    "${RUNTIME_ABS}/dsh-home" \
    "${RUNTIME_ABS}/tinyauth/data" \
    "${RUNTIME_ABS}/edge/caddy/data" \
    "${RUNTIME_ABS}/edge/caddy/config"

# Tinyauth config must exist before Compose creates the bind mount.
if [[ ! -f "${RUNTIME_ABS}/tinyauth/config.yml" ]]; then
    umask 077
    cat > "${RUNTIME_ABS}/tinyauth/config.yml" <<'YAML'
auth:
  users: []
YAML
fi

# DSH runs as node UID/GID 1000. Tinyauth's container user is also expected
# to write its repository-local data directory. Root deployments can set the
# ownership exactly; non-root deployments keep user ownership and warn.
if [[ "${EUID}" -eq 0 ]]; then
    chown -R 1000:1000 \
        "${RUNTIME_ABS}/workspace" \
        "${RUNTIME_ABS}/dsh-home" \
        "${RUNTIME_ABS}/tinyauth/data"
else
    echo "提示：当前不是 root。若 DSH/Tinyauth 出现 bind mount 权限问题，请将以下目录赋予 UID 1000：" >&2
    printf '  %s\n' \
        "${RUNTIME_ABS}/workspace" \
        "${RUNTIME_ABS}/dsh-home" \
        "${RUNTIME_ABS}/tinyauth/data" >&2
fi

chmod 0750 "${RUNTIME_ABS}/workspace" "${RUNTIME_ABS}/tinyauth/data"
chmod 0700 "${RUNTIME_ABS}/dsh-home"
chmod 0600 "${RUNTIME_ABS}/tinyauth/config.yml"

echo "Repository runtime: ${RUNTIME_ABS}"
