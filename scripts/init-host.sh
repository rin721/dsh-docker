#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    SUDO=''
elif command -v sudo >/dev/null 2>&1; then
    SUDO='sudo'
else
    echo "需要 root 权限创建 /var/lib/.dsh；请使用 root 或安装 sudo。" >&2
    exit 1
fi

${SUDO} mkdir -p \
    /var/lib/.dsh/data \
    /var/lib/.dsh/home \
    /var/lib/.dsh/tinyauth \
    /var/lib/.dsh/caddy/data \
    /var/lib/.dsh/caddy/config

# DSH 镜像使用 node 用户 UID/GID 1000。
${SUDO} chown -R 1000:1000 \
    /var/lib/.dsh/data \
    /var/lib/.dsh/home

${SUDO} chmod 0750 /var/lib/.dsh/data
${SUDO} chmod 0700 /var/lib/.dsh/home
${SUDO} chmod 0750 /var/lib/.dsh/tinyauth
${SUDO} chmod 0750 /var/lib/.dsh/caddy /var/lib/.dsh/caddy/data /var/lib/.dsh/caddy/config

echo "宿主机持久化目录已初始化：/var/lib/.dsh"
