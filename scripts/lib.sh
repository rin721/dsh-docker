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

validate_access_mode() {
    case "${1:-}" in
        local|domain-http|domain-https) return 0 ;;
        *)
            echo "ACCESS_MODE 仅支持 local、domain-http、domain-https，当前值：${1:-<empty>}" >&2
            return 1
            ;;
    esac
}

validate_domain() {
    local domain="${1:-}"
    [[ -n "${domain}" ]] || {
        echo "DSH_DOMAIN 不能为空。" >&2
        return 1
    }

    [[ "${domain}" != *"://"* && "${domain}" != */* && "${domain}" != *:* ]] || {
        echo "DSH_DOMAIN 只填写主机名，例如 dsh.example.com；不要包含协议、端口或路径。" >&2
        return 1
    }

    [[ "${domain}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]] || {
        echo "DSH_DOMAIN 格式无效：${domain}" >&2
        return 1
    }
}

set_env_value() {
    local root="$1"
    local key="$2"
    local value="$3"
    local file="${root}/.env"
    local tmp

    [[ -f "${file}" ]] || cp "${root}/.env.example" "${file}"
    tmp="$(mktemp)"

    awk -v key="${key}" -v value="${value}" '
        BEGIN { replaced = 0 }
        $0 ~ "^" key "=" {
            print key "=" value
            replaced = 1
            next
        }
        { print }
        END {
            if (!replaced) {
                print key "=" value
            }
        }
    ' "${file}" > "${tmp}"

    mv "${tmp}" "${file}"
}

configure_access_mode() {
    local root="$1"
    local mode="$2"
    local domain="${3:-}"
    local email="${4:-}"

    validate_access_mode "${mode}"

    case "${mode}" in
        local)
            set_env_value "${root}" ACCESS_MODE local
            set_env_value "${root}" BIND_ADDRESS 127.0.0.1
            set_env_value "${root}" DSH_PORT 3080
            ;;
        domain-http)
            set_env_value "${root}" ACCESS_MODE domain-http
            set_env_value "${root}" BIND_ADDRESS 0.0.0.0
            set_env_value "${root}" DSH_PORT 80
            [[ -n "${domain}" ]] && set_env_value "${root}" DSH_DOMAIN "${domain}"
            ;;
        domain-https)
            set_env_value "${root}" ACCESS_MODE domain-https
            set_env_value "${root}" BIND_ADDRESS 127.0.0.1
            set_env_value "${root}" DSH_PORT 3080
            [[ -n "${domain}" ]] && set_env_value "${root}" DSH_DOMAIN "${domain}"
            [[ -n "${email}" ]] && set_env_value "${root}" ACME_EMAIL "${email}"
            ;;
    esac
}

active_compose() {
    case "${ACCESS_MODE:-local}" in
        domain-https)
            docker compose -f compose.yaml -f compose.edge.caddy.yaml "$@"
            ;;
        *)
            docker compose "$@"
            ;;
    esac
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

validate_mode_config() {
    local mode="${ACCESS_MODE:-local}"

    validate_access_mode "${mode}"
    validate_port DSH_PORT "${DSH_PORT:-3080}"

    case "${mode}" in
        local)
            ;;
        domain-http)
            validate_domain "${DSH_DOMAIN:-}"
            if [[ "${BIND_ADDRESS:-127.0.0.1}" == "127.0.0.1" ]]; then
                echo "domain-http 模式不能只监听 127.0.0.1；请设置 BIND_ADDRESS=0.0.0.0 或具体外部网卡 IP。" >&2
                return 1
            fi
            ;;
        domain-https)
            validate_domain "${DSH_DOMAIN:-}"
            [[ -n "${ACME_EMAIL:-}" ]] || {
                echo "domain-https 模式必须设置 ACME_EMAIL。" >&2
                return 1
            }
            validate_port EDGE_HTTP_PORT "${EDGE_HTTP_PORT:-80}"
            validate_port EDGE_HTTPS_PORT "${EDGE_HTTPS_PORT:-443}"
            ;;
    esac
}

public_url() {
    local mode="${ACCESS_MODE:-local}"
    local domain="${DSH_DOMAIN:-}"
    local port="${DSH_PORT:-3080}"

    case "${mode}" in
        local)
            printf 'http://%s:%s\n' "${BIND_ADDRESS:-127.0.0.1}" "${port}"
            ;;
        domain-http)
            if [[ "${port}" == "80" ]]; then
                printf 'http://%s\n' "${domain}"
            else
                printf 'http://%s:%s\n' "${domain}" "${port}"
            fi
            ;;
        domain-https)
            if [[ "${EDGE_HTTPS_PORT:-443}" == "443" ]]; then
                printf 'https://%s\n' "${domain}"
            else
                printf 'https://%s:%s\n' "${domain}" "${EDGE_HTTPS_PORT}"
            fi
            ;;
    esac
}

pull_mode_images() {
    docker compose pull gateway

    if [[ "${ACCESS_MODE:-local}" == "domain-https" ]]; then
        docker compose -f compose.yaml -f compose.edge.caddy.yaml pull edge
    fi
}

validate_all_caddy_or_die() {
    validate_gateway_config_or_die

    if [[ "${ACCESS_MODE:-local}" == "domain-https" ]]; then
        validate_edge_config_or_die
    fi
}
