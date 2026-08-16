#!/usr/bin/env bash
set -Eeuo pipefail

# DSH 当前只安全地监听容器回环地址。
# socat 将容器的 0.0.0.0:3080 转发至 DSH 的 127.0.0.1:3079；
# Compose 再把宿主机 127.0.0.1:3080 映射进来，因此不会直接暴露公网。
readonly internal_host="${DSH_INTERNAL_HOST:-127.0.0.1}"
readonly internal_port="${DSH_INTERNAL_PORT:-3079}"
readonly proxy_port="${DSH_PROXY_PORT:-3080}"
readonly browser_port="${DSH_BROWSER_PORT:-3080}"

dsh_pid=''
proxy_pid=''

cleanup() {
    local status="${1:-0}"
    trap - EXIT INT TERM

    if [[ -n "${proxy_pid}" ]]; then
        kill -TERM "${proxy_pid}" 2>/dev/null || true
    fi
    if [[ -n "${dsh_pid}" ]]; then
        kill -TERM "${dsh_pid}" 2>/dev/null || true
    fi

    if [[ -n "${proxy_pid}" ]]; then
        wait "${proxy_pid}" 2>/dev/null || true
    fi
    if [[ -n "${dsh_pid}" ]]; then
        wait "${dsh_pid}" 2>/dev/null || true
    fi

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

# 逗号分隔，例如：DSH_EXTRA_TRUSTED_HOSTS='dev.example.com,dev.example.com:443'
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

# 任一进程退出，都关闭另一个进程，并把首个退出状态返回给 Docker。
wait -n "${dsh_pid}" "${proxy_pid}"
