#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

failed=0

check_shell() {
    local file="$1"
    if bash -n "${file}"; then
        printf '[OK] shell: %s\n' "${file#${ROOT_DIR}/}"
    else
        printf '[FAIL] shell: %s\n' "${file#${ROOT_DIR}/}" >&2
        failed=1
    fi
}

while IFS= read -r file; do
    check_shell "${file}"
done < <(find "${ROOT_DIR}/scripts" -maxdepth 1 -type f -name '*.sh' -print | sort)

check_shell "${ROOT_DIR}/start-dsh-web.sh"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if docker compose config >/dev/null; then
        echo "[OK] compose.yaml"
    else
        echo "[FAIL] compose.yaml" >&2
        failed=1
    fi
else
    echo "[SKIP] Docker Compose runtime validation"
fi

(( failed == 0 ))
