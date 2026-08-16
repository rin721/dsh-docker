#!/usr/bin/env bash
set -Eeuo pipefail

readonly internal_host="${DSH_INTERNAL_HOST:-127.0.0.1}"
readonly internal_port="${DSH_INTERNAL_PORT:-3079}"
readonly proxy_port="${DSH_PROXY_PORT:-3080}"

readonly workspace_dir="${DSH_WORKSPACE_DIR:-/workspace}"
readonly workspace_link="${HOME}/workspace"

dsh_pid=''
proxy_pid=''

ensure_workspace_link() {
    # DSH's browse directory picker starts at os.homedir(), which is
    # /home/node in this image. Keep HOME intact for Go/Rust/npm/DSH state,
    # and expose the persistent Docker workspace through one stable symlink.
    if [[ -L "${workspace_link}" ]]; then
        local current_target
        current_target="$(readlink "${workspace_link}" 2>/dev/null || true)"

        if [[ "${current_target}" != "${workspace_dir}" ]]; then
            rm -f "${workspace_link}"
            ln -s "${workspace_dir}" "${workspace_link}"
        fi
        return
    fi

    if [[ -e "${workspace_link}" ]]; then
        echo "警告：${workspace_link} 已存在且不是符号链接，不会覆盖。" >&2
        return
    fi

    ln -s "${workspace_dir}" "${workspace_link}"
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

ensure_workspace_link

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
