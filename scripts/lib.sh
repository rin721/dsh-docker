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

validate_image_mode() {
    case "${1:-}" in
        auto|pull|build) return 0 ;;
        *)
            echo "DSH_IMAGE_MODE 仅支持 auto、pull、build，当前值：${1:-<empty>}" >&2
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
    local extra="${4:-}"

    validate_access_mode "${mode}"

    case "${mode}" in
        local)
            set_env_value "${root}" ACCESS_MODE local
            set_env_value "${root}" BIND_ADDRESS 127.0.0.1
            set_env_value "${root}" DSH_PORT "${extra:-3080}"
            ;;
        domain-http)
            # 3080 is deliberately the default instead of 80. Port 80 is very
            # often already owned by Nginx/1Panel. Users who want standard
            # HTTP can explicitly pass 80 after the domain.
            set_env_value "${root}" ACCESS_MODE domain-http
            set_env_value "${root}" BIND_ADDRESS 0.0.0.0
            set_env_value "${root}" DSH_PORT "${extra:-3080}"
            [[ -n "${domain}" ]] && set_env_value "${root}" DSH_DOMAIN "${domain}"
            ;;
        domain-https)
            set_env_value "${root}" ACCESS_MODE domain-https
            set_env_value "${root}" BIND_ADDRESS 127.0.0.1
            set_env_value "${root}" DSH_PORT 3080
            [[ -n "${domain}" ]] && set_env_value "${root}" DSH_DOMAIN "${domain}"
            [[ -n "${extra}" ]] && set_env_value "${root}" ACME_EMAIL "${extra}"
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

active_build_compose() {
    case "${ACCESS_MODE:-local}" in
        domain-https)
            docker compose \
                -f compose.yaml \
                -f compose.build.yaml \
                -f compose.edge.caddy.yaml \
                "$@"
            ;;
        *)
            docker compose \
                -f compose.yaml \
                -f compose.build.yaml \
                "$@"
            ;;
    esac
}

project_owns_host_port() {
    local root="$1"
    local port="$2"
    local project
    local id

    project="$(compose_project_name "${root}")"

    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        if docker port "${id}" 2>/dev/null | grep -Eq "[:.]${port}$|:${port}$"; then
            return 0
        fi
    done < <(
        docker ps \
            --filter "label=com.docker.compose.project=${project}" \
            --format '{{.ID}}' 2>/dev/null
    )

    return 1
}

host_port_in_use() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .
        return
    fi

    # Fallback if ss is not available.
    python3 - "${port}" <<'PY'
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    sock.bind(("0.0.0.0", port))
except OSError:
    raise SystemExit(0)
else:
    raise SystemExit(1)
finally:
    sock.close()
PY
}

preflight_host_port() {
    local root="$1"
    local port="$2"
    local purpose="$3"

    validate_port "${purpose}" "${port}"

    if ! host_port_in_use "${port}"; then
        return 0
    fi

    if project_owns_host_port "${root}" "${port}"; then
        return 0
    fi

    echo >&2
    echo "端口预检失败：${purpose} 需要宿主机端口 ${port}，但该端口已被占用。" >&2

    if command -v ss >/dev/null 2>&1; then
        echo >&2
        echo "当前监听：" >&2
        ss -ltnp "sport = :${port}" 2>/dev/null >&2 || true
    fi

    return 1
}

preflight_access_ports() {
    local root="$1"
    local mode="${ACCESS_MODE:-local}"

    case "${mode}" in
        local)
            preflight_host_port "${root}" "${DSH_PORT:-3080}" "DSH_PORT"
            ;;
        domain-http)
            if ! preflight_host_port "${root}" "${DSH_PORT:-3080}" "DSH_PORT"; then
                echo >&2
                echo "domain-http 建议：" >&2
                echo "  1) 换一个直接访问端口：" >&2
                echo "     ./scripts/deploy.sh domain-http ${DSH_DOMAIN:-dsh.example.com} 3080" >&2
                echo "     访问 http://${DSH_DOMAIN:-dsh.example.com}:3080" >&2
                echo >&2
                echo "  2) 如果 80 已被 Nginx/1Panel 使用，让它反代到 local Core：" >&2
                echo "     ./scripts/deploy.sh local" >&2
                echo "     上游：http://127.0.0.1:3080" >&2
                return 1
            fi
            ;;
        domain-https)
            # Core stays loopback:3080; Edge owns public 80/443.
            preflight_host_port "${root}" "${DSH_PORT:-3080}" "DSH_PORT"
            preflight_host_port "${root}" "${EDGE_HTTP_PORT:-80}" "EDGE_HTTP_PORT"
            preflight_host_port "${root}" "${EDGE_HTTPS_PORT:-443}" "EDGE_HTTPS_PORT"
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
    validate_image_mode "${DSH_IMAGE_MODE:-auto}"
    validate_port DSH_PORT "${DSH_PORT:-3080}"

    case "${mode}" in
        local)
            ;;
        domain-http)
            validate_domain "${DSH_DOMAIN:-}"
            [[ "${BIND_ADDRESS:-127.0.0.1}" != "127.0.0.1" ]] || {
                echo "domain-http 直接访问模式不能只监听 127.0.0.1。" >&2
                return 1
            }
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

pull_gateway_images() {
    docker compose pull gateway

    if [[ "${ACCESS_MODE:-local}" == "domain-https" ]]; then
        docker compose -f compose.yaml -f compose.edge.caddy.yaml pull edge
    fi
}

resolve_dsh_delivery() {
    local mode="${DSH_IMAGE_MODE:-auto}"
    local image="${DSH_IMAGE:-ghcr.io/rin721/dsh-docker:latest}"
    local output

    validate_image_mode "${mode}"

    case "${mode}" in
        pull)
            echo "拉取预构建 DSH 镜像：${image}"
            docker pull "${image}"
            DSH_DELIVERY=prebuilt
            ;;
        auto)
            echo "尝试拉取预构建 DSH 镜像：${image}"
            if output="$(docker pull "${image}" 2>&1)"; then
                printf '%s\n' "${output}"
                DSH_DELIVERY=prebuilt
            else
                echo "预构建镜像不可用，自动回退本地构建。" >&2
                echo "若这是公开仓库，请确认 GHCR package 已发布且 Visibility=Public。" >&2
                DSH_DELIVERY=build
            fi
            ;;
        build)
            DSH_DELIVERY=build
            ;;
    esac

    export DSH_DELIVERY
}

prepare_dsh_image() {
    resolve_dsh_delivery

    case "${DSH_DELIVERY}" in
        prebuilt)
            echo "使用预构建 DSH 镜像；跳过服务器本地编译。"
            ;;
        build)
            echo "本地构建 DSH 镜像..."
            echo "首次构建仍可能较慢；BuildKit 会缓存 apt/npm/Go/Rust 下载供后续重建复用。"
            active_build_compose build dsh
            ;;
    esac
}

validate_all_caddy_or_die() {
    validate_gateway_config_or_die

    if [[ "${ACCESS_MODE:-local}" == "domain-https" ]]; then
        validate_edge_config_or_die
    fi
}
