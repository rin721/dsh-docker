#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

bash "${ROOT_DIR}/scripts/repair-permissions.sh" --git-index
bash "${ROOT_DIR}/scripts/self-test.sh"

echo
echo "Release preparation completed."
echo
echo "Git executable-mode summary:"
git diff --summary --cached -- 2>/dev/null || true
git diff --summary -- 2>/dev/null || true

echo
echo "提交示例："
echo "  git add -A"
echo "  git commit -m 'fix: preserve executable scripts and workspace entry'"
echo "  git push"
