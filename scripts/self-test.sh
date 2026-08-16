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
    if bash -n "${file}"; then
        ok "shell syntax: ${file#${ROOT_DIR}/}"
    else
        bad "shell syntax: ${file#${ROOT_DIR}/}"
    fi

    if [[ -x "${file}" ]]; then
        ok "filesystem mode: ${file#${ROOT_DIR}/}"
    else
        bad "filesystem mode missing +x: ${file#${ROOT_DIR}/}"
    fi
done

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for file in "${shell_files[@]}"; do
        rel="${file#${ROOT_DIR}/}"

        if ! git ls-files --error-unmatch -- "${rel}" >/dev/null 2>&1; then
            continue
        fi

        mode="$(git ls-files -s -- "${rel}" | awk 'NR == 1 { print $1 }')"
        if [[ "${mode}" == "100755" ]]; then
            ok "git mode 100755: ${rel}"
        else
            bad "git mode ${mode:-unknown}: ${rel} (expected 100755)"
        fi
    done
else
    echo "[SKIP] Git index executable-mode validation (not inside a Git repository)"
fi

if command -v node >/dev/null 2>&1; then
    node --check "${ROOT_DIR}/dsh-web-proxy.mjs" >/dev/null \
        && ok "node: dsh-web-proxy.mjs" \
        || bad "node: dsh-web-proxy.mjs"

    node --check "${ROOT_DIR}/dsh-http-compat.js" >/dev/null \
        && ok "node: dsh-http-compat.js" \
        || bad "node: dsh-http-compat.js"
else
    echo "[SKIP] Node syntax checks"
fi

if grep -Eq -- '--mount=type=cache,target=/home/node/\.rustup/(tmp|toolchains)' "${ROOT_DIR}/Dockerfile"; then
    bad "Dockerfile: rustup tmp/toolchains must not be cache mounts"
else
    ok "Dockerfile: rustup installation paths stay on one filesystem"
fi

grep -Fq 'command: ["bash", "/usr/local/bin/start-dsh-web"]' "${ROOT_DIR}/compose.yaml" \
    && ok "compose: launcher does not require host +x bit" \
    || bad "compose: launcher must be invoked through bash"

grep -Fq 'ln -s "${workspace_dir}" "${workspace_link}"' "${ROOT_DIR}/start-dsh-web.sh" \
    && ok "workspace UI symlink bootstrap" \
    || bad "workspace UI symlink bootstrap missing"

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
