#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

command -v git >/dev/null 2>&1 || {
    echo "未找到 git。" >&2
    exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "当前目录不是 Git 仓库。" >&2
    exit 1
}

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "存在未提交的 tracked 文件修改。为避免 pull 覆盖，请先 commit/stash/revert。" >&2
    git status --short
    exit 1
fi

old_rev="$(git rev-parse --short HEAD)"
echo "拉取仓库更新..."
git fetch --prune
git pull --ff-only
new_rev="$(git rev-parse --short HEAD)"
echo "Git: ${old_rev} -> ${new_rev}"

exec "${ROOT_DIR}/scripts/rebuild.sh"
