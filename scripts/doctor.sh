#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"
cd "${ROOT_DIR}"

fail=0
check() { printf '%-34s' "$1"; shift; if "$@" >/dev/null 2>&1; then echo "OK"; else echo "FAIL"; fail=1; fi; }

check "docker command" command -v docker
check "docker compose v2" docker compose version
check "docker daemon" docker info
check "git command" command -v git
check ".env.example" test -f .env.example
check "compose.yaml" test -f compose.yaml
check "Dockerfile" test -f Dockerfile
check "gateway Caddyfile" test -f Caddyfile.gateway
check "start-dsh-web.sh executable" test -x start-dsh-web.sh

if [[ -f .env ]]; then
    load_env "${ROOT_DIR}"
    runtime="$(runtime_dir_abs "${ROOT_DIR}")"
    echo "Runtime: ${runtime}"
    [[ -f "${runtime}/tinyauth/config.yml" ]] && {
        if has_tinyauth_user "${runtime}/tinyauth/config.yml"; then
            echo "Tinyauth user configuration: OK"
        else
            echo "Tinyauth user configuration: MISSING USER"
        fi
    }
    if docker compose config >/dev/null 2>&1; then
        echo "docker compose config: OK"
    else
        echo "docker compose config: FAIL"
        fail=1
    fi
else
    echo ".env: not created yet (deploy.sh will create it)"
fi

exit "${fail}"
