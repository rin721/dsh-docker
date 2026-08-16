#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

failed=0
ok() { printf '[OK] %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*" >&2; failed=1; }

while IFS= read -r file; do
    bash -n "${file}" \
        && ok "shell: ${file#${ROOT_DIR}/}" \
        || bad "shell: ${file#${ROOT_DIR}/}"
done < <(find "${ROOT_DIR}/scripts" -maxdepth 1 -type f -name '*.sh' -print | sort)

bash -n "${ROOT_DIR}/start-dsh-web.sh" \
    && ok "shell: start-dsh-web.sh" \
    || bad "shell: start-dsh-web.sh"

if command -v node >/dev/null 2>&1; then
    node --check "${ROOT_DIR}/dsh-web-proxy.mjs" >/dev/null \
        && ok "node: dsh-web-proxy.mjs" \
        || bad "node: dsh-web-proxy.mjs"

    node --check "${ROOT_DIR}/dsh-http-compat.js" >/dev/null \
        && ok "node: dsh-http-compat.js" \
        || bad "node: dsh-http-compat.js"
fi

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


if grep -Eq -- '--mount=type=cache,target=/home/node/\.rustup/(tmp|toolchains)' "${ROOT_DIR}/Dockerfile"; then
    bad "Dockerfile: rustup tmp/toolchains must not be cache mounts"
else
    ok "Dockerfile: rustup installation paths are on one filesystem"
fi

(( failed == 0 ))
