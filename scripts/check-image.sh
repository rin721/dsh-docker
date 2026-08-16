#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

require_docker
[[ -f .env ]] || cp .env.example .env
load_env "${ROOT_DIR}"

image="${DSH_IMAGE:-ghcr.io/rin721/dsh-docker:latest}"

echo "检查预构建镜像：${image}"

if docker manifest inspect "${image}" >/dev/null 2>&1; then
    echo "[OK] 镜像可访问。"
else
    echo "[FAIL] 镜像当前无法匿名访问。" >&2
    echo "请确认 GitHub Actions 已发布镜像，并将 GHCR Package Visibility 设置为 Public。" >&2
    exit 1
fi
