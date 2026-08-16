#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"
require_docker

command -v git >/dev/null 2>&1 || { echo "未找到 git。" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "当前目录不是 Git 仓库。" >&2; exit 1; }

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "存在未提交的 tracked 文件修改。为避免 pull 覆盖，请先 commit/stash/revert。" >&2
    git status --short
    exit 1
fi

# 先保存旧镜像 ID；pull 后 Compose/Dockerfile 可能发生变化。
OLD_DSH_IMAGE_ID="$(docker compose images -q dsh 2>/dev/null | head -n 1 || true)"
export OLD_DSH_IMAGE_ID

old_rev="$(git rev-parse --short HEAD)"
echo "拉取仓库更新..."
git fetch --prune
git pull --ff-only
new_rev="$(git rev-parse --short HEAD)"
echo "Git: ${old_rev} -> ${new_rev}"

# 使用刚 pull 下来的新版 rebuild.sh。
exec "${ROOT_DIR}/scripts/rebuild.sh"
