#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"

RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"
HOME_STATE="${RUNTIME_ABS}/home"
UID_VALUE="${RUNTIME_UID:-1000}"
GID_VALUE="${RUNTIME_GID:-1000}"

mkdir -p "${HOME_STATE}"

if [[ "${EUID}" -eq 0 ]]; then
    chown -R "${UID_VALUE}:${GID_VALUE}" \
        "${RUNTIME_ABS}/workspace" \
        "${RUNTIME_ABS}/dsh-home" \
        "${HOME_STATE}"
else
    owner="$(stat -c '%u' "${HOME_STATE}" 2>/dev/null || true)"
    if [[ -n "${owner}" && "${owner}" != "${UID_VALUE}" ]]; then
        echo "警告：${HOME_STATE} owner uid=${owner}，容器用户 uid=${UID_VALUE}。" >&2
    fi
fi

chmod 0700 "${HOME_STATE}"

for dir in ssh gnupg aws kube docker config git shell npm cargo local local/share local/state; do
    [[ -e "${HOME_STATE}/${dir}" ]] && chmod 0700 "${HOME_STATE}/${dir}" || true
done

if [[ -d "${HOME_STATE}/ssh" ]]; then
    find "${HOME_STATE}/ssh" -type d -exec chmod 0700 {} + 2>/dev/null || true
    find "${HOME_STATE}/ssh" -type f -exec chmod 0600 {} + 2>/dev/null || true
    find "${HOME_STATE}/ssh" -type f \( -name '*.pub' -o -name 'known_hosts' -o -name 'known_hosts.old' \) \
        -exec chmod 0644 {} + 2>/dev/null || true
fi

if [[ -d "${HOME_STATE}/gnupg" ]]; then
    find "${HOME_STATE}/gnupg" -type s -delete 2>/dev/null || true
    find "${HOME_STATE}/gnupg" -type d -exec chmod 0700 {} + 2>/dev/null || true
    find "${HOME_STATE}/gnupg" -type f -exec chmod 0600 {} + 2>/dev/null || true
fi

for file in \
    git/config \
    git/credentials \
    shell/bash_history \
    shell/python_history \
    npm/npmrc \
    netrc \
    pypirc \
    cargo/config.toml \
    cargo/credentials.toml
do
    [[ -e "${HOME_STATE}/${file}" ]] && chmod 0600 "${HOME_STATE}/${file}" || true
done
