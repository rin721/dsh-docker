# syntax=docker/dockerfile:1.7

ARG NODE_VERSION=24.18.0
FROM node:${NODE_VERSION}-bookworm-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG GO_VERSION=1.26.5
ARG GO_SHA256_AMD64=5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053
ARG GO_SHA256_ARM64=fe4789e92b1f33358680864bbe8704289e7bb5fc207d80623c308935bd696d49
ARG RUST_TOOLCHAIN=stable
ARG PNPM_VERSION=11.7.0
ARG DSH_VERSION=latest
ARG INSTALL_GO_DEV_TOOLS=true

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    HOME=/home/node \
    XDG_CACHE_HOME=/home/node/.cache \
    GOPATH=/home/node/go \
    GOMODCACHE=/home/node/go/pkg/mod \
    GOCACHE=/home/node/.cache/go-build \
    RUSTUP_HOME=/home/node/.rustup \
    CARGO_HOME=/home/node/.cargo \
    NPM_CONFIG_PREFIX=/home/node/.local \
    DSH_HOME=/home/node/.dsh \
    DSH_PERMISSION_MODE=workspace-write \
    DSH_TELEMETRY_DISABLED=1 \
    NODE_USE_ENV_PROXY=1 \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH=/usr/local/go/bin:/home/node/go/bin:/home/node/.cargo/bin:/home/node/.local/bin:${PATH}

# 通用开发、编译、调试、网络和终端工具。
# 使用 Debian/glibc，降低 Node 原生依赖与开发工具的兼容性问题。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash \
        bash-completion \
        ca-certificates \
        curl \
        wget \
        git \
        git-lfs \
        openssh-client \
        gnupg \
        dirmngr \
        build-essential \
        make \
        cmake \
        ninja-build \
        pkg-config \
        autoconf \
        automake \
        libtool \
        clang \
        clangd \
        lldb \
        gdb \
        strace \
        libclang-dev \
        libssl-dev \
        openssl \
        zlib1g-dev \
        libsqlite3-dev \
        sqlite3 \
        protobuf-compiler \
        musl-tools \
        python3 \
        python3-pip \
        python3-venv \
        python-is-python3 \
        pipx \
        jq \
        ripgrep \
        fd-find \
        fzf \
        tree \
        less \
        nano \
        vim-tiny \
        tmux \
        file \
        rsync \
        unzip \
        zip \
        xz-utils \
        zstd \
        shellcheck \
        dnsutils \
        iproute2 \
        iputils-ping \
        netcat-openbsd \
        procps \
        psmisc \
        lsof \
        socat \
        tini; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    git lfs install --system; \
    rm -rf /var/lib/apt/lists/*

# Go，支持 linux/amd64 与 linux/arm64，并校验官方 SHA256。
RUN set -eux; \
    deb_arch="$(dpkg --print-architecture)"; \
    case "${deb_arch}" in \
        amd64) go_arch='amd64'; go_sha256="${GO_SHA256_AMD64}" ;; \
        arm64) go_arch='arm64'; go_sha256="${GO_SHA256_ARM64}" ;; \
        *) echo "Unsupported architecture: ${deb_arch}" >&2; exit 1 ;; \
    esac; \
    archive="go${GO_VERSION}.linux-${go_arch}.tar.gz"; \
    curl --fail --show-error --location --retry 5 \
        "https://go.dev/dl/${archive}" \
        --output "/tmp/${archive}"; \
    echo "${go_sha256}  /tmp/${archive}" | sha256sum --check --strict; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf "/tmp/${archive}"; \
    rm -f "/tmp/${archive}"; \
    go version

# node 官方镜像内置 UID/GID 1000 的非 root 用户 node。
RUN set -eux; \
    mkdir -p \
        /workspace \
        /home/node/.dsh \
        /home/node/.local/bin \
        /home/node/.local/share/pnpm/store \
        /home/node/.cache/go-build \
        /home/node/go/bin \
        /home/node/go/pkg/mod \
        /home/node/.cargo \
        /home/node/.rustup; \
    chown -R node:node /workspace /home/node; \
    git config --system --add safe.directory /workspace

COPY --chmod=0755 start-dsh-web.sh /usr/local/bin/start-dsh-web

USER node
WORKDIR /workspace

# Rust：rustup + stable + 常用开发组件。
RUN set -eux; \
    curl --proto '=https' --tlsv1.2 --fail --show-error --silent \
        https://sh.rustup.rs \
        --output /tmp/rustup-init.sh; \
    sh /tmp/rustup-init.sh \
        -y \
        --profile minimal \
        --default-toolchain "${RUST_TOOLCHAIN}"; \
    rm -f /tmp/rustup-init.sh; \
    rustup component add rustfmt clippy rust-analyzer; \
    rustc --version; \
    cargo --version

# Node.js 开发工具与 DeepSeek Harness。
RUN set -eux; \
    npm install --global --no-audit --no-fund \
        "pnpm@${PNPM_VERSION}" \
        typescript@latest \
        tsx@latest; \
    npm install --global --no-audit --no-fund \
        "@deepseek-ai/dsh@${DSH_VERSION}"; \
    npm cache clean --force; \
    node --version; \
    npm --version; \
    pnpm --version; \
    dsh --version

# Go 开发工具：语言服务器、导入整理、调试、静态检查、任务运行器。
RUN set -eux; \
    if [[ "${INSTALL_GO_DEV_TOOLS}" == 'true' ]]; then \
        go install golang.org/x/tools/gopls@latest; \
        go install golang.org/x/tools/cmd/goimports@latest; \
        go install github.com/go-delve/delve/cmd/dlv@latest; \
        go install honnef.co/go/tools/cmd/staticcheck@latest; \
        go install github.com/go-task/task/v3/cmd/task@latest; \
        go clean -cache -modcache; \
    fi

EXPOSE 3080

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/usr/local/bin/start-dsh-web"]
