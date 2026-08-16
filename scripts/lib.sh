#!/usr/bin/env bash

project_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Minimal dotenv reader for the shell scripts. It intentionally does NOT use
# `source`, so a value in .env cannot execute shell commands. Docker Compose
# still reads the same .env file independently for variable interpolation.
load_env() {
    local root="$1"
    local file="${root}/.env"
    local line key value

    [[ -f "${file}" ]] || return 0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue

        # Allow optional leading `export ` for convenience.
        line="${line#export }"
        [[ "${line}" == *=* ]] || continue

        key="${line%%=*}"
        value="${line#*=}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"

        [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

        # Trim surrounding whitespace from the value, then remove one matching
        # pair of simple quotes/double quotes. No eval/command substitution.
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ ${#value} -ge 2 ]]; then
            if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
                value="${value:1:${#value}-2}"
            elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
                value="${value:1:${#value}-2}"
            fi
        fi

        printf -v "${key}" '%s' "${value}"
        export "${key}"
    done < "${file}"
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
        echo "未找到 docker。请先安装 Docker Engine。" >&2
        exit 1
    }
    docker compose version >/dev/null 2>&1 || {
        echo "未找到 Docker Compose v2（docker compose）。" >&2
        exit 1
    }
    docker info >/dev/null 2>&1 || {
        echo "Docker daemon 不可用或当前用户无权限访问 Docker。" >&2
        exit 1
    }
}

has_tinyauth_user() {
    local file="$1"
    [[ -f "${file}" ]] || return 1
    LC_ALL=C grep -Eq '\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}' "${file}"
}
