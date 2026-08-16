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


if grep -q 'header_up Host' "${ROOT_DIR}/Caddyfile.gateway"; then
    bad "Caddyfile.gateway: must preserve external Host"
else
    ok "Caddyfile.gateway: external Host preserved"
fi

if grep -q 'DSH_EXTRA_TRUSTED_HOSTS' "${ROOT_DIR}/compose.yaml" "${ROOT_DIR}/.env.example" "${ROOT_DIR}/start-dsh-web.sh"; then
    bad "dynamic authority: per-domain trusted-host config still present"
else
    ok "dynamic authority: no per-domain trusted-host config"
fi

if grep -q 'origin-host-mismatch' "${ROOT_DIR}/dsh-web-proxy.mjs" \
    && grep -q 'result.host = internalAuthority' "${ROOT_DIR}/dsh-web-proxy.mjs" \
    && grep -q 'result.origin = internalOrigin' "${ROOT_DIR}/dsh-web-proxy.mjs"; then
    ok "dynamic authority: validation and internal normalization present"
else
    bad "dynamic authority: validation/normalization missing"
fi

copy_line="$(grep -n 'COPY --chmod=0755 start-dsh-web.sh' "${ROOT_DIR}/Dockerfile" | cut -d: -f1)"
go_line="$(grep -n 'go install golang.org/x/tools/gopls' "${ROOT_DIR}/Dockerfile" | cut -d: -f1)"
if [[ -n "${copy_line}" && -n "${go_line}" ]] && (( copy_line > go_line )); then
    ok "Dockerfile: runtime COPY is after expensive toolchain layers"
else
    bad "Dockerfile: runtime COPY should be after Rust/npm/Go layers"
fi


if grep -q 'source: ./dsh-web-proxy.mjs' "${ROOT_DIR}/compose.yaml" \
    && grep -q 'target: /usr/local/lib/dsh-web-proxy.mjs' "${ROOT_DIR}/compose.yaml" \
    && grep -q 'source: ./start-dsh-web.sh' "${ROOT_DIR}/compose.yaml"; then
    ok "compose: runtime bridge files are repository-mounted"
else
    bad "compose: runtime bridge files must be repository-mounted"
fi

if grep -q 'DSH_DELIVERY=local' "${ROOT_DIR}/scripts/lib.sh"; then
    ok "image delivery: auto can reuse an existing local image"
else
    bad "image delivery: local image reuse missing"
fi

(( failed == 0 ))
