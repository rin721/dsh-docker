#!/usr/bin/env bash
set -Eeuo pipefail

readonly internal_host="${DSH_INTERNAL_HOST:-127.0.0.1}"
readonly internal_port="${DSH_INTERNAL_PORT:-3079}"
readonly proxy_port="${DSH_PROXY_PORT:-3080}"

dsh_pid=''
proxy_pid=''

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
