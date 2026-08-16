#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

docker compose -f compose.yaml -f compose.edge.caddy.yaml rm -sf edge || true
echo "HTTPS Edge 已停止；Core Gateway 未停止。"
