#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

require_docker
[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
HOME_STATE="${RUNTIME_ABS}/home"

container="$(docker compose ps -q dsh 2>/dev/null || true)"
if [[ -z "${container}" ]]; then
    echo "Home migration: no existing DSH container; skipped."
    exit 0
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null || true)" != "true" ]]; then
    echo "Home migration: existing DSH container is not running; skipped."
    exit 0
fi

copy_dir_if_empty() {
    local source="$1"
    local target="$2"
    [[ -z "$(find "${target}" -mindepth 1 -print -quit 2>/dev/null || true)" ]] || return 0
    docker exec "${container}" sh -lc "test -d '$source'" >/dev/null 2>&1 || return 0

    echo "Home migration: ${source} -> ${target}"
    docker exec "${container}" sh -lc \
        "cd '$source' && tar --exclude='S.gpg-agent*' -cf - ." \
        | tar -xf - -C "${target}"
}

copy_file_if_empty() {
    local source="$1"
    local target="$2"
    [[ ! -s "${target}" ]] || return 0
    docker exec "${container}" sh -lc "test -f '$source'" >/dev/null 2>&1 || return 0

    echo "Home migration: ${source} -> ${target}"
    docker exec "${container}" sh -lc "cat '$source'" > "${target}"
}

copy_dir_if_empty /home/node/.ssh "${HOME_STATE}/ssh"
copy_dir_if_empty /home/node/.gnupg "${HOME_STATE}/gnupg"
copy_dir_if_empty /home/node/.aws "${HOME_STATE}/aws"
copy_dir_if_empty /home/node/.kube "${HOME_STATE}/kube"
copy_dir_if_empty /home/node/.docker "${HOME_STATE}/docker"
copy_dir_if_empty /home/node/.config "${HOME_STATE}/config"
copy_dir_if_empty /home/node/.local/share "${HOME_STATE}/local/share"
copy_dir_if_empty /home/node/.local/state "${HOME_STATE}/local/state"

copy_file_if_empty /home/node/.gitconfig "${HOME_STATE}/git/config"
copy_file_if_empty /home/node/.git-credentials "${HOME_STATE}/git/credentials"
copy_file_if_empty /home/node/.bash_history "${HOME_STATE}/shell/bash_history"
copy_file_if_empty /home/node/.python_history "${HOME_STATE}/shell/python_history"
copy_file_if_empty /home/node/.npmrc "${HOME_STATE}/npm/npmrc"
copy_file_if_empty /home/node/.netrc "${HOME_STATE}/netrc"
copy_file_if_empty /home/node/.pypirc "${HOME_STATE}/pypirc"
copy_file_if_empty /home/node/.cargo/config.toml "${HOME_STATE}/cargo/config.toml"
copy_file_if_empty /home/node/.cargo/credentials.toml "${HOME_STATE}/cargo/credentials.toml"

bash "${ROOT_DIR}/scripts/fix-home-permissions.sh"
