#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

failed=0
ok() { printf '[OK] %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*" >&2; failed=1; }

shopt -s nullglob
shell_files=("${ROOT_DIR}"/scripts/*.sh "${ROOT_DIR}/start-dsh-web.sh")
shopt -u nullglob

for file in "${shell_files[@]}"; do
    bash -n "${file}" \
        && ok "shell syntax: ${file#${ROOT_DIR}/}" \
        || bad "shell syntax: ${file#${ROOT_DIR}/}"
    [[ -x "${file}" ]] \
        && ok "filesystem mode: ${file#${ROOT_DIR}/}" \
        || bad "filesystem mode missing +x: ${file#${ROOT_DIR}/}"
done

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for file in "${shell_files[@]}"; do
        rel="${file#${ROOT_DIR}/}"
        git ls-files --error-unmatch -- "${rel}" >/dev/null 2>&1 || continue
        mode="$(git ls-files -s -- "${rel}" | awk 'NR == 1 { print $1 }')"
        [[ "${mode}" == "100755" ]] \
            && ok "git mode 100755: ${rel}" \
            || bad "git mode ${mode:-unknown}: ${rel} (expected 100755)"
    done
else
    echo "[SKIP] Git index executable-mode validation"
fi

if command -v node >/dev/null 2>&1; then
    node --check "${ROOT_DIR}/dsh-web-proxy.mjs" >/dev/null \
        && ok "node: dsh-web-proxy.mjs" \
        || bad "node: dsh-web-proxy.mjs"
    node --check "${ROOT_DIR}/dsh-http-compat.js" >/dev/null \
        && ok "node: dsh-http-compat.js" \
        || bad "node: dsh-http-compat.js"
fi

grep -Eq -- '--mount=type=cache,target=/home/node/\.rustup/(tmp|toolchains)' "${ROOT_DIR}/Dockerfile" \
    && bad "Dockerfile: rustup tmp/toolchains must not be cache mounts" \
    || ok "Dockerfile: rustup installation paths stay on one filesystem"

grep -Fq 'command: ["bash", "/usr/local/bin/start-dsh-web"]' "${ROOT_DIR}/compose.yaml" \
    && ok "compose: launcher does not require host +x bit" \
    || bad "compose: launcher must be invoked through bash"

grep -Fq 'source: "${RUNTIME_DIR:-./.runtime}/home"' "${ROOT_DIR}/compose.yaml" \
    && grep -Fq 'target: /home/node/.persist' "${ROOT_DIR}/compose.yaml" \
    && ok "compose: developer home persistence mount" \
    || bad "compose: developer home persistence mount missing"

tmp_state="$(mktemp -d)"
trap 'rm -rf "${tmp_state}"' EXIT
mkdir -p "${tmp_state}/home/.local" "${tmp_state}/home/.cargo" "${tmp_state}/persist" "${tmp_state}/workspace"

if HOME="${tmp_state}/home" \
   DSH_PERSIST_HOME="${tmp_state}/persist" \
   DSH_WORKSPACE_DIR="${tmp_state}/workspace" \
   DSH_STARTUP_PREPARE_ONLY=true \
   bash "${ROOT_DIR}/start-dsh-web.sh"; then
    ok "persistent home bootstrap simulation"
else
    bad "persistent home bootstrap simulation"
fi

check_link() {
    local link="$1"
    local target="$2"
    [[ -L "${link}" && "$(readlink "${link}")" == "${target}" ]] \
        && ok "persistent link: ${link#${tmp_state}/home/}" \
        || bad "persistent link: ${link#${tmp_state}/home/}"
}

check_link "${tmp_state}/home/workspace" "${tmp_state}/workspace"
check_link "${tmp_state}/home/.ssh" "${tmp_state}/persist/ssh"
check_link "${tmp_state}/home/.gitconfig" "${tmp_state}/persist/git/config"
check_link "${tmp_state}/home/.git-credentials" "${tmp_state}/persist/git/credentials"
check_link "${tmp_state}/home/.config" "${tmp_state}/persist/config"
check_link "${tmp_state}/home/.local/share" "${tmp_state}/persist/local/share"
check_link "${tmp_state}/home/.local/state" "${tmp_state}/persist/local/state"
check_link "${tmp_state}/home/.cargo/credentials.toml" "${tmp_state}/persist/cargo/credentials.toml"

rm -rf "${tmp_state}"
trap - EXIT

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose config >/dev/null \
        && ok "compose.yaml" \
        || bad "compose.yaml"
    docker compose -f compose.yaml -f compose.build.yaml config >/dev/null \
        && ok "compose.build.yaml" \
        || bad "compose.build.yaml"
else
    echo "[SKIP] Docker Compose runtime validation"
fi

(( failed == 0 ))
