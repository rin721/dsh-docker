#!/usr/bin/env bash
set -Eeuo pipefail

# DSH Web 默认只应监听回环地址。
# socat 仅把它桥接到容器网络的 3080 端口；Compose 不向宿主机发布 3080，
# 因而公网入口只能经过 Caddy + Tinyauth。
readonly internal_host="${DSH_INTERNAL_HOST:-127.0.0.1}"
readonly internal_port="${DSH_INTERNAL_PORT:-3079}"
readonly proxy_port="${DSH_PROXY_PORT:-3080}"
readonly browser_port="${DSH_BROWSER_PORT:-3080}"

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
    --trusted-host "localhost:${browser_port}"
    --trusted-host "127.0.0.1:${browser_port}"
)

# 逗号分隔，例如：DSH_EXTRA_TRUSTED_HOSTS='dsh.example.com,dsh.example.com:443'
if [[ -n "${DSH_EXTRA_TRUSTED_HOSTS:-}" ]]; then
    IFS=',' read -r -a extra_hosts <<< "${DSH_EXTRA_TRUSTED_HOSTS}"
    for trusted_host in "${extra_hosts[@]}"; do
        [[ -n "${trusted_host}" ]] && dsh_args+=(--trusted-host "${trusted_host}")
    done
fi

dsh "${dsh_args[@]}" "$@" &
dsh_pid="$!"

socat \
    "TCP-LISTEN:${proxy_port},reuseaddr,fork,bind=0.0.0.0" \
    "TCP:${internal_host}:${internal_port}" &
proxy_pid="$!"

wait -n "${dsh_pid}" "${proxy_pid}"
