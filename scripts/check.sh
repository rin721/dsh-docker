#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
load_env "${ROOT_DIR}"
RUNTIME_ABS="$(runtime_dir_abs "${ROOT_DIR}")"

echo "Repository: ${ROOT_DIR}"
echo "Runtime:    ${RUNTIME_ABS}"
echo
docker compose ps

echo
echo "Published ports:"
docker compose port gateway 3080 2>/dev/null || true
docker compose port gateway 3081 2>/dev/null || true

echo
echo "Recent logs:"
docker compose logs --tail=30 gateway tinyauth dsh
