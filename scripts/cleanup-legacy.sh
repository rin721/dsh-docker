#!/usr/bin/env bash
set -Eeuo pipefail

# 兼容早期固定 container_name 的版本。仅在容器明确属于旧 dsh 项目时删除，避免误删同名第三方容器。
legacy_names=(deepseek-harness dsh-tinyauth dsh-gateway dsh-caddy)
for name in "${legacy_names[@]}"; do
    docker container inspect "${name}" >/dev/null 2>&1 || continue
    project="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "${name}" 2>/dev/null || true)"
    case "${project}" in
        deepseek-harness|dsh-docker)
            echo "清理旧版容器：${name}"
            docker rm -f "${name}" >/dev/null 2>&1 || true
            ;;
    esac
done
