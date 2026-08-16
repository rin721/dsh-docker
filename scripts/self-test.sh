#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

failed=0
ok() { printf '[OK] %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*" >&2; failed=1; }

while IFS= read -r file; do
    if bash -n "${file}"; then
        ok "shell: ${file#${ROOT_DIR}/}"
    else
        bad "shell: ${file#${ROOT_DIR}/}"
    fi
done < <(find "${ROOT_DIR}/scripts" -maxdepth 1 -type f -name '*.sh' -print | sort)

if bash -n "${ROOT_DIR}/start-dsh-web.sh"; then
    ok "shell: start-dsh-web.sh"
else
    bad "shell: start-dsh-web.sh"
fi

if command -v node >/dev/null 2>&1; then
    if node --check "${ROOT_DIR}/dsh-web-proxy.mjs" >/dev/null; then
        ok "node syntax: dsh-web-proxy.mjs"
    else
        bad "node syntax: dsh-web-proxy.mjs"
    fi

    if node --check "${ROOT_DIR}/dsh-http-compat.js" >/dev/null; then
        ok "node syntax: dsh-http-compat.js"
    else
        bad "node syntax: dsh-http-compat.js"
    fi
else
    echo "[SKIP] node syntax checks"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if docker compose config >/dev/null; then
        ok "compose.yaml"
    else
        bad "compose.yaml"
    fi
else
    echo "[SKIP] Docker Compose runtime validation"
fi

(( failed == 0 ))
