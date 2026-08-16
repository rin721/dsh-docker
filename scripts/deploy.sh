#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

command -v docker >/dev/null 2>&1 || { echo "未找到 docker。" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "未找到 docker compose v2。" >&2; exit 1; }

if [[ ! -f .env ]]; then
    cp .env.example .env
    echo "已创建 .env，请先修改 DSH_DOMAIN、AUTH_DOMAIN、ACME_EMAIL，然后重新执行部署。" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
source ./.env
set +a

: "${DSH_DOMAIN:?DSH_DOMAIN 未设置}"
: "${AUTH_DOMAIN:?AUTH_DOMAIN 未设置}"
: "${ACME_EMAIL:?ACME_EMAIL 未设置}"

if [[ "${DSH_DOMAIN}" == *example.com || "${AUTH_DOMAIN}" == *example.com || "${ACME_EMAIL}" == *example.com ]]; then
    echo "请先把 .env 中的 example.com 示例值改成真实域名/邮箱。" >&2
    exit 1
fi

parent_domain="${AUTH_DOMAIN#*.}"
if [[ "${DSH_DOMAIN}" != *."${parent_domain}" ]]; then
    echo "警告：AUTH_DOMAIN 与 DSH_DOMAIN 看起来没有共享同一父域。" >&2
    echo "Tinyauth 的跨子域 Cookie 推荐使用类似 auth.example.com + dsh.example.com。" >&2
fi

"${ROOT_DIR}/scripts/init-host.sh"

if ! grep -Eq '^[[:space:]]*-[[:space:]]*"[^:]+:\$2' auth/tinyauth.yml; then
    echo "尚未创建 Tinyauth 登录用户。请先运行：" >&2
    echo "  ./scripts/create-user.sh" >&2
    exit 1
fi

# 先验证 Compose 变量和结构。
docker compose config >/dev/null

# Caddy/Tinyauth 拉取固定镜像；DSH 开发镜像本地构建。
docker compose pull caddy tinyauth
docker compose build --pull dsh
docker compose up -d

echo
echo "部署完成。"
echo "DSH:  https://${DSH_DOMAIN}"
echo "登录: https://${AUTH_DOMAIN}"
echo
echo "查看状态: docker compose ps"
echo "查看日志: docker compose logs -f --tail=200"
