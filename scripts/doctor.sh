#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

errors=0
ok() { printf '[OK] %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*" >&2; errors=$((errors + 1)); }
warn() { printf '[WARN] %s\n' "$*" >&2; }

command -v docker >/dev/null 2>&1 && ok "docker found" || bad "docker not found"
docker compose version >/dev/null 2>&1 && ok "docker compose v2" || bad "docker compose v2 unavailable"
docker info >/dev/null 2>&1 && ok "docker daemon reachable" || bad "docker daemon unavailable"

if [[ -f .env ]]; then
    ok ".env exists"
    load_env "${ROOT_DIR}"
else
    warn ".env 不存在；deploy.sh 会自动创建"
fi

validate_core_config >/dev/null 2>&1 && ok "core config" || bad "core config invalid"
preflight_core_port "${ROOT_DIR}" >/dev/null 2>&1 \
    && ok "DSH_PORT available / owned by this project" \
    || bad "DSH_PORT conflict"

FILE="$(users_file "${ROOT_DIR}")"
has_auth_user "${FILE}" && ok "Basic Auth user exists" || warn "尚未创建认证用户"

docker compose config >/dev/null 2>&1 && ok "compose config" || bad "compose config invalid"

if [[ "${BIND_ADDRESS:-127.0.0.1}" == "0.0.0.0" ]]; then
    warn "BIND_ADDRESS=0.0.0.0；如果使用外部 Nginx，通常建议改回 127.0.0.1"
fi

echo "Reverse proxy upstream: http://127.0.0.1:${DSH_PORT:-3080}"


permission_error=0
shopt -s nullglob
permission_files=("${ROOT_DIR}/start-dsh-web.sh" "${ROOT_DIR}"/scripts/*.sh)
shopt -u nullglob
for file in "${permission_files[@]}"; do
    [[ -x "${file}" ]] || permission_error=1
done
if (( permission_error == 0 )); then
    ok "shell executable permissions"
else
    bad "shell executable permissions"
fi

if [[ -n "$(docker compose ps -q dsh 2>/dev/null || true)" ]]; then
    if docker compose exec -T dsh sh -lc '
        test -L "$HOME/workspace" &&
        test "$(readlink "$HOME/workspace")" = "/workspace"
    ' >/dev/null 2>&1; then
        ok "workspace UI link: /home/node/workspace -> /workspace"
    else
        bad "workspace UI link missing or incorrect"
    fi
fi


HOME_STATE="$(runtime_dir_abs "${ROOT_DIR}")/home"

if [[ -d "${HOME_STATE}/ssh" && -d "${HOME_STATE}/git" && -d "${HOME_STATE}/config" ]]; then
    ok "developer home persistence directories"
else
    bad "developer home persistence directories missing"
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
        ok "developer home persistence links"
    else
        bad "developer home persistence links"
    fi
fi

ssh_mode="$(stat -c '%a' "${HOME_STATE}/ssh" 2>/dev/null || true)"
[[ "${ssh_mode}" == "700" ]] \
    && ok "SSH directory mode 0700" \
    || bad "SSH directory mode is ${ssh_mode:-missing}, expected 700"

(( errors == 0 )) || exit 1
