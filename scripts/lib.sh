#!/usr/bin/env bash

project_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# 安全的简单 dotenv 读取器：不 source、不 eval，因此 .env 内容不会被当成 shell 命令执行。
load_env() {
    local root="$1"
    local file="${root}/.env"
    local line key value

    [[ -f "${file}" ]] || return 0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue

        line="${line#export }"
        [[ "${line}" == *=* ]] || continue

        key="${line%%=*}"
        value="${line#*=}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"

        [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

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
        echo "Docker daemon 不可用，或当前用户无权限访问 Docker。" >&2
        exit 1
    }
}

validate_port() {
    local name="$1"
    local value="$2"
    [[ "${value}" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 )) || {
        echo "${name} 必须是 1-65535 的端口，当前值：${value}" >&2
        return 1
    }
}

users_file() {
    local root="$1"
    local runtime
    runtime="$(runtime_dir_abs "${root}")"
    printf '%s/auth/users.caddy\n' "${runtime}"
}

has_auth_user() {
    local file="$1"
    [[ -s "${file}" ]] || return 1
    LC_ALL=C grep -Eq '^[A-Za-z0-9._@-]+[[:space:]]+\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}[[:space:]]*$' "${file}"
}

compose_project_name() {
    local root="$1"
    basename "${root}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g'
}

gateway_image() {
    printf 'caddy:%s\n' "${GATEWAY_CADDY_VERSION:-2.11.4}"
}

validate_gateway_config() {
    docker compose run --rm --no-deps \
        --entrypoint caddy \
        gateway \
        validate \
        --config /etc/caddy/Caddyfile \
        --adapter caddyfile
}

validate_gateway_config_or_die() {
    local output
    if ! output="$(validate_gateway_config 2>&1)"; then
        echo "Gateway Caddy 配置验证失败：" >&2
        printf '%s\n' "${output}" >&2
        return 1
    fi
}

validate_edge_config() {
    docker compose -f compose.yaml -f compose.edge.caddy.yaml run --rm --no-deps \
        --entrypoint caddy \
        edge \
        validate \
        --config /etc/caddy/Caddyfile \
        --adapter caddyfile
}

validate_edge_config_or_die() {
    local output
    if ! output="$(validate_edge_config 2>&1)"; then
        echo "HTTPS Edge Caddy 配置验证失败：" >&2
        printf '%s\n' "${output}" >&2
        return 1
    fi
}
