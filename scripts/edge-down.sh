#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# Remove only the optional edge service; keep the Core stack running.
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge stop edge >/dev/null 2>&1 || true
docker compose -f compose.yaml -f compose.edge.caddy.yaml --profile edge rm -f edge >/dev/null 2>&1 || true
echo "HTTPS Edge 已停止；Core 与 .runtime 数据保留。"
