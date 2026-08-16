#!/usr/bin/env bash
set -Eeuo pipefail

# One-time compatibility cleanup for older releases that hard-coded:
#   name: deepseek-harness
#   container_name: deepseek-harness / dsh-tinyauth / dsh-gateway
# Only containers carrying the expected old Compose labels are removed.
legacy_project="deepseek-harness"
legacy_names=(deepseek-harness dsh-tinyauth dsh-gateway dsh-caddy dsh-edge)
removed=false

for name in "${legacy_names[@]}"; do
    if ! docker container inspect "${name}" >/dev/null 2>&1; then
        continue
    fi

    project="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "${name}" 2>/dev/null || true)"
    service="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.service" }}' "${name}" 2>/dev/null || true)"

    if [[ "${project}" == "${legacy_project}" ]]; then
        echo "清理旧版容器：${name} (service=${service:-unknown})"
        docker rm -f "${name}" >/dev/null
        removed=true
    fi
done

# Old versions explicitly tagged the DSH build with this image name. Remove it
# only after old containers are gone; ignore absence/use by unrelated containers.
if [[ "${removed}" == "true" ]] && docker image inspect local/deepseek-harness-dev:latest >/dev/null 2>&1; then
    docker image rm local/deepseek-harness-dev:latest >/dev/null 2>&1 || true
fi
