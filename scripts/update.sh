#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker

command -v git >/dev/null 2>&1 || { echo "未找到 git。" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "当前目录不是 Git 仓库。" >&2; exit 1; }

# .env and .runtime are ignored, so they do not block updates. Tracked local
# modifications are intentionally not discarded automatically.
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "存在未提交的 tracked 文件修改。为避免覆盖，请先 commit/stash/revert 后再更新。" >&2
    git status --short
    exit 1
fi

# Capture the currently running locally-built DSH image before pulling new
# repository code. The new rebuild script will remove exactly this image.
OLD_DSH_IMAGE_ID="$(docker compose images -q dsh 2>/dev/null | head -n 1 || true)"
export OLD_DSH_IMAGE_ID

old_rev="$(git rev-parse --short HEAD)"
echo "拉取仓库更新..."
git fetch --prune
git pull --ff-only
new_rev="$(git rev-parse --short HEAD)"
echo "Git: ${old_rev} -> ${new_rev}"

# exec ensures the rebuild logic comes from the newly pulled repository,
# instead of continuing to use an outdated update implementation.
exec "${ROOT_DIR}/scripts/rebuild.sh"
