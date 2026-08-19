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
registry="ghcr.io"
cdn="pkg-containers.githubusercontent.com"

echo "检查预构建镜像：${image}"
echo

fails=0
ok() { printf '[OK]   %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*" >&2; fails=$((fails + 1)); }
info() { printf '[INFO] %s\n' "$*"; }

# 1) Registry + Authentication + Manifest：整体能否拿到 manifest
if docker manifest inspect "${image}" >/dev/null 2>&1; then
    ok "manifest 可获取（Registry/认证 正常）"
else
    bad "镜像无法匿名访问；请确认 GitHub Actions 已发布镜像，且 GHCR Package Visibility 为 Public"
fi

# 2) GHCR Registry 端点：DNS + TCP + TLS（对 /v2/ 返回 401 是正常行为）
status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
    "https://${registry}/v2/" 2>/dev/null || true)"
if [[ -n "${status}" ]]; then
    if [[ "${status}" == "401" ]]; then
        ok "GHCR Registry 可达（HTTP 401 正常：认证前要求 token）"
    else
        info "GHCR Registry 探测返回 HTTP ${status}"
    fi
else
    bad "无法连接 GHCR Registry（${registry}）：请检查 DNS/TCP/TLS 或代理"
fi

# 3) Layer CDN：镜像层下载所依赖的端点 DNS 是否可解析
if getent hosts "${cdn}" >/dev/null 2>&1; then
    ok "Layer CDN DNS 可解析（${cdn}）"
else
    bad "Layer CDN DNS 无法解析（${cdn}），镜像层下载会卡住"
fi

echo
echo "若 manifest 正常但 docker pull 卡在 Downloading/Waiting，问题通常出在 Layer CDN（${cdn}）"
echo "或服务器出口带宽。可执行：docker pull ${image} 观察实时进度。"

(( fails == 0 )) || exit 1
