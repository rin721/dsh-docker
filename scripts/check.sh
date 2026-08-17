#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

require_docker
[[ -f .env ]] && load_env "${ROOT_DIR}"

docker compose ps

echo
runtime="$(runtime_dir_abs "${ROOT_DIR}")"

workspace_ui="not-running"
home_state_ui="not-running"
if [[ -n "$(docker compose ps -q dsh 2>/dev/null || true)" ]]; then
    if docker compose exec -T dsh sh -lc '
        test -L "$HOME/workspace" &&
        test "$(readlink "$HOME/workspace")" = "/workspace"
    ' >/dev/null 2>&1; then
        workspace_ui="/home/node/workspace -> /workspace"
    else
        workspace_ui="ERROR"
    fi
fi

if [[ -n "$(docker compose ps -q dsh 2>/dev/null || true)" ]]; then
    if docker compose exec -T dsh sh -lc '
        test -L "$HOME/.ssh" &&
        test "$(readlink "$HOME/.ssh")" = "$HOME/.persist/ssh" &&
        test -L "$HOME/.gitconfig" &&
        test "$(readlink "$HOME/.gitconfig")" = "$HOME/.persist/git/config" &&
        test -L "$HOME/.config" &&
        test "$(readlink "$HOME/.config")" = "$HOME/.persist/config"
    ' >/dev/null 2>&1; then
        home_state_ui="OK"
    else
        home_state_ui="ERROR"
    fi
fi

users="$(users_file "${ROOT_DIR}")"
count=0
[[ -f "${users}" ]] && count="$(awk 'NF >= 2 { n++ } END { print n+0 }' "${users}")"

echo "Core listen  : ${BIND_ADDRESS:-127.0.0.1}:${DSH_PORT:-3080}"
echo "Proxy target : http://127.0.0.1:${DSH_PORT:-3080}"
echo "Auth users   : ${count}"
echo "Runtime      : ${runtime}"
echo "Workspace    : ${runtime}/workspace <-> /workspace"
echo "Workspace UI : ${workspace_ui}"
echo "Developer home: ${runtime}/home <-> /home/node/.persist (${home_state_ui})"
echo "SSH keys     : ${runtime}/home/ssh <-> /home/node/.ssh"
echo "Git config   : ${runtime}/home/git/config <-> /home/node/.gitconfig"
echo "HTTP compat  : ${DSH_HTTP_COMPAT_SHIM:-true}"

host="${BIND_ADDRESS:-127.0.0.1}"
[[ "${host}" == "0.0.0.0" ]] && host="127.0.0.1"

code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
    "http://${host}:${DSH_PORT:-3080}/" 2>/dev/null || true)"

if [[ "${code}" == "401" ]]; then
    echo "HTTP check   : 401 (正常：Basic Auth 已生效)"
elif [[ -n "${code}" ]]; then
    echo "HTTP check   : ${code}"
else
    echo "HTTP check   : 无法连接"
fi
