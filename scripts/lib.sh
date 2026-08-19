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

validate_image_mode() {
    case "${1:-}" in
        auto|pull|build) return 0 ;;
        *)
            echo "DSH_IMAGE_MODE 仅支持 auto、pull、build，当前值：${1:-<empty>}" >&2
            return 1
            ;;
    esac
}

host_port_in_use() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .
        return
    fi

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

project_owns_host_port() {
    local root="$1"
    local port="$2"
    local project
    local id

    project="$(compose_project_name "${root}")"

    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        if docker port "${id}" 2>/dev/null | grep -Eq ":${port}$"; then
            return 0
        fi
    done < <(
        docker ps \
            --filter "label=com.docker.compose.project=${project}" \
            --format '{{.ID}}' 2>/dev/null
    )

    return 1
}

preflight_core_port() {
    local root="$1"
    local port="${DSH_PORT:-3080}"

    validate_port DSH_PORT "${port}"

    if ! host_port_in_use "${port}"; then
        return 0
    fi

    if project_owns_host_port "${root}" "${port}"; then
        return 0
    fi

    echo >&2
    echo "端口预检失败：宿主机端口 ${port} 已被其他进程占用。" >&2

    if command -v ss >/dev/null 2>&1; then
        echo >&2
        echo "当前监听：" >&2
        ss -ltnp "sport = :${port}" 2>/dev/null >&2 || true
    fi

    echo >&2
    echo "请修改 .env 中的 DSH_PORT，或释放该端口后再部署。" >&2
    return 1
}

validate_core_config() {
    validate_port DSH_PORT "${DSH_PORT:-3080}"
    validate_image_mode "${DSH_IMAGE_MODE:-auto}"

    case "${BIND_ADDRESS:-127.0.0.1}" in
        127.0.0.1|0.0.0.0)
            ;;
        *)
            [[ -n "${BIND_ADDRESS:-}" ]] || {
                echo "BIND_ADDRESS 不能为空。" >&2
                return 1
            }
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

resolve_dsh_delivery() {
    local mode="${DSH_IMAGE_MODE:-auto}"
    local image="${DSH_IMAGE:-ghcr.io/rin721/dsh-docker:latest}"

    validate_image_mode "${mode}"

    case "${mode}" in
        pull)
            echo "拉取预构建 DSH 镜像：${image}"
            docker pull "${image}"
            DSH_DELIVERY=prebuilt
            ;;
        auto)
            echo "尝试拉取预构建 DSH 镜像：${image}"

            if docker pull "${image}"; then
                DSH_DELIVERY=prebuilt
            elif docker image inspect "${image}" >/dev/null 2>&1; then
                echo "预构建镜像当前无法拉取；复用本机已有 DSH 镜像。" >&2
                echo "仓库内的启动/动态代理文件会通过只读 bind mount 覆盖镜像内副本。" >&2
                DSH_DELIVERY=local
            else
                echo "预构建镜像不可用且本机无可复用镜像，自动回退本地构建。" >&2
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
        local)
            echo "使用本机已有 DSH 镜像；跳过服务器本地编译。"
            ;;
        build)
            echo "本地构建 DSH 镜像..."
            echo "首次构建可能较慢；BuildKit 会缓存 apt/npm/Go/Rust 下载。"
            docker compose -f compose.yaml -f compose.build.yaml build dsh
            ;;
    esac
}

core_url() {
    local host="${BIND_ADDRESS:-127.0.0.1}"
    local port="${DSH_PORT:-3080}"

    if [[ "${host}" == "0.0.0.0" ]]; then
        host="<server-ip>"
    fi

    printf 'http://%s:%s\n' "${host}" "${port}"
}
