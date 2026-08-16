#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "== Compose =="
docker compose ps

echo
echo "== Published ports =="
docker compose ps --format 'table {{.Name}}\t{{.Ports}}'

echo
echo "预期：只有 Caddy 发布 80/443；DSH:3080 和 Tinyauth:3000 不应出现宿主机公网映射。"
