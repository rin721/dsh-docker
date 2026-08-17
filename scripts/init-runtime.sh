#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"

mkdir -p \
    "${RUNTIME_ABS}/workspace/projects" \
    "${RUNTIME_ABS}/dsh-home" \
    "${RUNTIME_ABS}/auth" \
    "${RUNTIME_ABS}/home/ssh" \
    "${RUNTIME_ABS}/home/gnupg" \
    "${RUNTIME_ABS}/home/aws" \
    "${RUNTIME_ABS}/home/kube" \
    "${RUNTIME_ABS}/home/docker" \
    "${RUNTIME_ABS}/home/config" \
    "${RUNTIME_ABS}/home/local/share" \
    "${RUNTIME_ABS}/home/local/state" \
    "${RUNTIME_ABS}/home/git" \
    "${RUNTIME_ABS}/home/shell" \
    "${RUNTIME_ABS}/home/npm" \
    "${RUNTIME_ABS}/home/cargo"

touch \
    "${RUNTIME_ABS}/auth/users.caddy" \
    "${RUNTIME_ABS}/home/git/config" \
    "${RUNTIME_ABS}/home/git/credentials" \
    "${RUNTIME_ABS}/home/shell/bash_history" \
    "${RUNTIME_ABS}/home/shell/python_history" \
    "${RUNTIME_ABS}/home/npm/npmrc" \
    "${RUNTIME_ABS}/home/netrc" \
    "${RUNTIME_ABS}/home/pypirc" \
    "${RUNTIME_ABS}/home/cargo/config.toml" \
    "${RUNTIME_ABS}/home/cargo/credentials.toml"

bash "${ROOT_DIR}/scripts/fix-home-permissions.sh"

chmod 0750 "${RUNTIME_ABS}"
chmod 0750 "${RUNTIME_ABS}/workspace" "${RUNTIME_ABS}/auth"
chmod 0700 "${RUNTIME_ABS}/dsh-home"

# Final explicit security fence for persistent developer identity.
chmod 0700 "${RUNTIME_ABS}/home" "${RUNTIME_ABS}/home/ssh" "${RUNTIME_ABS}/home/gnupg"
chmod 0600 \
    "${RUNTIME_ABS}/home/git/config" \
    "${RUNTIME_ABS}/home/git/credentials" \
    "${RUNTIME_ABS}/home/shell/bash_history" \
    "${RUNTIME_ABS}/home/shell/python_history" \
    "${RUNTIME_ABS}/home/npm/npmrc" \
    "${RUNTIME_ABS}/home/netrc" \
    "${RUNTIME_ABS}/home/pypirc" \
    "${RUNTIME_ABS}/home/cargo/config.toml" \
    "${RUNTIME_ABS}/home/cargo/credentials.toml"

# Caddy needs this one file readable through its bind mount.
chmod 0644 "${RUNTIME_ABS}/auth/users.caddy"

echo "Repository runtime: ${RUNTIME_ABS}"
