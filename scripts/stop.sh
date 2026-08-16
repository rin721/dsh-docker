#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
docker compose down --remove-orphans
echo "容器已停止；.runtime 持久化数据保留。"
