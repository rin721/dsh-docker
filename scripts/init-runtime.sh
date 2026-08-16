#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
UID_VALUE="${RUNTIME_UID:-1000}"
GID_VALUE="${RUNTIME_GID:-1000}"

mkdir -p \
    "${RUNTIME_ABS}/workspace" \
    "${RUNTIME_ABS}/workspace/projects" \
    "${RUNTIME_ABS}/dsh-home" \
    "${RUNTIME_ABS}/auth" \
    "${RUNTIME_ABS}/edge/caddy/data" \
    "${RUNTIME_ABS}/edge/caddy/config"

touch "${RUNTIME_ABS}/auth/users.caddy"

# DSH 容器以 node(1000:1000) 运行。root 部署时主动对齐工作区权限。
if [[ "${EUID}" -eq 0 ]]; then
    chown -R "${UID_VALUE}:${GID_VALUE}" \
        "${RUNTIME_ABS}/workspace" \
    "${RUNTIME_ABS}/workspace/projects" \
        "${RUNTIME_ABS}/dsh-home"
fi

chmod 0750 "${RUNTIME_ABS}"
chmod 0750 "${RUNTIME_ABS}/workspace" "${RUNTIME_ABS}/auth"
chmod 0700 "${RUNTIME_ABS}/dsh-home"
# Caddy 容器必须能读取该 bind-mounted 文件；目录本身仍限制为 0750。
chmod 0644 "${RUNTIME_ABS}/auth/users.caddy"

echo "Repository runtime: ${RUNTIME_ABS}"
