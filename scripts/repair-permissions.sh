#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

update_git_index=false
if [[ "${1:-}" == "--git-index" ]]; then
    update_git_index=true
elif [[ $# -gt 0 ]]; then
    echo "用法：bash scripts/repair-permissions.sh [--git-index]" >&2
    exit 1
fi

shopt -s nullglob
executables=(
    "${ROOT_DIR}/start-dsh-web.sh"
    "${ROOT_DIR}"/scripts/*.sh
)
shopt -u nullglob

for file in "${executables[@]}"; do
    chmod 0755 "${file}"
done

echo "已修复工作区 Shell 执行权限："
for file in "${executables[@]}"; do
    printf '  0755 %s\n' "${file#${ROOT_DIR}/}"
done

if [[ "${update_git_index}" == "true" ]]; then
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "当前目录不是 Git 仓库，无法更新 Git executable bit。" >&2
        exit 1
    fi

    tracked=()
    for file in "${executables[@]}"; do
        rel="${file#${ROOT_DIR}/}"
        if git ls-files --error-unmatch -- "${rel}" >/dev/null 2>&1; then
            tracked+=("${rel}")
        fi
    done

    if (( ${#tracked[@]} > 0 )); then
        git update-index --chmod=+x -- "${tracked[@]}"
    fi

    echo
    echo "已将 Shell 文件在 Git index 中标记为 100755。"
    echo "提交并 push 后，Linux 用户未来 git clone / git pull 会获得可执行权限。"
fi
