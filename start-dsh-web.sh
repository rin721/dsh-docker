#!/usr/bin/env bash
set -Eeuo pipefail

readonly internal_host="${DSH_INTERNAL_HOST:-127.0.0.1}"
readonly internal_port="${DSH_INTERNAL_PORT:-3079}"
readonly proxy_port="${DSH_PROXY_PORT:-3080}"

readonly workspace_dir="${DSH_WORKSPACE_DIR:-/workspace}"
readonly workspace_link="${HOME}/workspace"
readonly persist_home="${DSH_PERSIST_HOME:-${HOME}/.persist}"

dsh_pid=''
proxy_pid=''

copy_missing_directory_content() {
    local source="$1"
    local target="$2"
    [[ -d "${source}" ]] || return 0
    mkdir -p "${target}"
    cp -a -n "${source}/." "${target}/" 2>/dev/null || true
}

ensure_directory_link() {
    local link_path="$1"
    local target_path="$2"

    mkdir -p "$(dirname "${link_path}")" "${target_path}"

    if [[ -L "${link_path}" ]]; then
        local current_target
        current_target="$(readlink "${link_path}" 2>/dev/null || true)"
        [[ "${current_target}" == "${target_path}" ]] && return 0
        rm -f "${link_path}"
    elif [[ -d "${link_path}" ]]; then
        copy_missing_directory_content "${link_path}" "${target_path}"
        rm -rf "${link_path}"
    elif [[ -e "${link_path}" ]]; then
        echo "警告：${link_path} 已存在且不是目录/符号链接，不会覆盖。" >&2
        return 0
    fi

    ln -s "${target_path}" "${link_path}"
}

ensure_file_link() {
    local link_path="$1"
    local target_path="$2"

    mkdir -p "$(dirname "${link_path}")" "$(dirname "${target_path}")"
    touch "${target_path}"

    if [[ -L "${link_path}" ]]; then
        local current_target
        current_target="$(readlink "${link_path}" 2>/dev/null || true)"
        [[ "${current_target}" == "${target_path}" ]] && return 0
        rm -f "${link_path}"
    elif [[ -f "${link_path}" ]]; then
        if [[ ! -s "${target_path}" && -s "${link_path}" ]]; then
            cp -a "${link_path}" "${target_path}"
        fi
        rm -f "${link_path}"
    elif [[ -e "${link_path}" ]]; then
        echo "警告：${link_path} 已存在且不是文件/符号链接，不会覆盖。" >&2
        return 0
    fi

    ln -s "${target_path}" "${link_path}"
}

prepare_persistent_home() {
    mkdir -p "${persist_home}"

    # DSH directory browser starts from HOME.
    ensure_directory_link "${workspace_link}" "${workspace_dir}"

    # Developer identity / credentials.
    ensure_directory_link "${HOME}/.ssh" "${persist_home}/ssh"
    ensure_directory_link "${HOME}/.gnupg" "${persist_home}/gnupg"
    ensure_directory_link "${HOME}/.aws" "${persist_home}/aws"
    ensure_directory_link "${HOME}/.kube" "${persist_home}/kube"
    ensure_directory_link "${HOME}/.docker" "${persist_home}/docker"

    # XDG state.
    ensure_directory_link "${HOME}/.config" "${persist_home}/config"
    ensure_directory_link "${HOME}/.local/share" "${persist_home}/local/share"
    ensure_directory_link "${HOME}/.local/state" "${persist_home}/local/state"

    # Git.
    ensure_file_link "${HOME}/.gitconfig" "${persist_home}/git/config"
    ensure_file_link "${HOME}/.git-credentials" "${persist_home}/git/credentials"

    # Shell/common CLI.
    ensure_file_link "${HOME}/.bash_history" "${persist_home}/shell/bash_history"
    ensure_file_link "${HOME}/.python_history" "${persist_home}/shell/python_history"
    ensure_file_link "${HOME}/.npmrc" "${persist_home}/npm/npmrc"
    ensure_file_link "${HOME}/.netrc" "${persist_home}/netrc"
    ensure_file_link "${HOME}/.pypirc" "${persist_home}/pypirc"

    # Keep Rust binaries/toolchains image-managed; persist Cargo user config only.
    ensure_file_link "${HOME}/.cargo/config.toml" "${persist_home}/cargo/config.toml"
    ensure_file_link "${HOME}/.cargo/credentials.toml" "${persist_home}/cargo/credentials.toml"

    find "${persist_home}/gnupg" -maxdepth 1 -type s -delete 2>/dev/null || true
}

cleanup() {
    local status="${1:-0}"
    trap - EXIT INT TERM

    [[ -n "${proxy_pid}" ]] && kill -TERM "${proxy_pid}" 2>/dev/null || true
    [[ -n "${dsh_pid}" ]] && kill -TERM "${dsh_pid}" 2>/dev/null || true

    [[ -n "${proxy_pid}" ]] && wait "${proxy_pid}" 2>/dev/null || true
    [[ -n "${dsh_pid}" ]] && wait "${dsh_pid}" 2>/dev/null || true

    exit "${status}"
}

trap 'cleanup $?' EXIT
trap 'cleanup 130' INT
trap 'cleanup 0' TERM

prepare_persistent_home

if [[ "${DSH_STARTUP_PREPARE_ONLY:-false}" == "true" ]]; then
    exit 0
fi

dsh_args=(
    web
    --host "${internal_host}"
    --port "${internal_port}"
    --trusted-host "localhost"
    --trusted-host "127.0.0.1"
)

dsh "${dsh_args[@]}" "$@" &
dsh_pid="$!"

DSH_INTERNAL_HOST="${internal_host}" \
DSH_INTERNAL_PORT="${internal_port}" \
DSH_PROXY_PORT="${proxy_port}" \
node /usr/local/lib/dsh-web-proxy.mjs &
proxy_pid="$!"

wait -n "${dsh_pid}" "${proxy_pid}"
