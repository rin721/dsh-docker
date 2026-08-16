#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge down --remove-orphans
echo "Edge/Core 容器已停止；.runtime 数据保留。"
