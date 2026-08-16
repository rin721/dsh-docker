#!/usr/bin/env bash

project_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

load_env() {
    local root="$1"
    if [[ -f "${root}/.env" ]]; then
        set -a
        # shellcheck disable=SC1091
        source "${root}/.env"
        set +a
    fi
}

runtime_dir_abs() {
    local root="$1"
    local configured="${RUNTIME_DIR:-./.runtime}"
    if [[ "${configured}" = /* ]]; then
        printf '%s\n' "${configured%/}"
    else
        printf '%s\n' "${root}/${configured#./}" | sed 's:/*$::'
    fi
}

require_docker() {
    command -v docker >/dev/null 2>&1 || {
        echo "未找到 docker。" >&2
        exit 1
    }
    docker compose version >/dev/null 2>&1 || {
        echo "未找到 Docker Compose v2。" >&2
        exit 1
    }
}
