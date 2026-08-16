# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.26.5
ARG NODE_VERSION=24.18.0

FROM golang:${GO_VERSION}-bookworm AS go-toolchain
FROM node:${NODE_VERSION}-bookworm-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
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

COPY --from=go-toolchain /usr/local/go /usr/local/go

# BuildKit apt caches survive local rebuilds even when this layer must run again.
RUN rm -f /etc/apt/apt.conf.d/docker-clean; \
    printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' \
      > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
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
        build-essential \
        make \
        cmake \
        ninja-build \
        pkg-config \
        clang \
        clangd \
        gdb \
        strace \
        libssl-dev \
        openssl \
        zlib1g-dev \
        libsqlite3-dev \
        sqlite3 \
        protobuf-compiler \
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
        iproute2 \
        procps \
        lsof \
        tini; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    git lfs install --system; \
    go version

RUN set -eux; \
    mkdir -p \
        /workspace \
        /home/node/.dsh \
        /home/node/.local/bin \
        /home/node/.cache/go-build \
        /home/node/go/bin \
        /home/node/go/pkg/mod \
        /home/node/.cargo \
        /home/node/.rustup \
        /home/node/.npm; \
    chown -R node:node /workspace /home/node; \
    git config --system --add safe.directory /workspace

COPY --chmod=0755 start-dsh-web.sh /usr/local/bin/start-dsh-web
COPY --chmod=0644 dsh-web-proxy.mjs dsh-http-compat.js /usr/local/lib/

USER node
WORKDIR /workspace

# Do not cache-mount RUSTUP_HOME/tmp or RUSTUP_HOME/toolchains.
# rustup installs by renaming files from tmp into toolchains; separate
# filesystems can fail with EXDEV ("Invalid cross-device link").
# The completed RUN layer is already cached normally by BuildKit.
RUN set -eux; \
    curl --proto '=https' --tlsv1.2 --fail --show-error --silent \
        https://sh.rustup.rs -o /tmp/rustup-init.sh; \
    sh /tmp/rustup-init.sh \
        -y \
        --no-modify-path \
        --profile minimal \
        --default-toolchain "${RUST_TOOLCHAIN}"; \
    rm -f /tmp/rustup-init.sh; \
    rustup component add rustfmt clippy rust-analyzer; \
    rustc --version; \
    cargo --version; \
    rustfmt --version; \
    cargo clippy --version; \
    rust-analyzer --version

RUN --mount=type=cache,target=/home/node/.npm,uid=1000,gid=1000 \
    set -eux; \
    npm install --global --no-audit --no-fund \
        "pnpm@${PNPM_VERSION}" \
        typescript@latest \
        tsx@latest \
        "@deepseek-ai/dsh@${DSH_VERSION}"; \
    node --version; \
    npm --version; \
    pnpm --version; \
    dsh --version

RUN --mount=type=cache,target=/home/node/go/pkg/mod,uid=1000,gid=1000 \
    --mount=type=cache,target=/home/node/.cache/go-build,uid=1000,gid=1000 \
    set -eux; \
    if [[ "${INSTALL_GO_DEV_TOOLS}" == "true" ]]; then \
        go install golang.org/x/tools/gopls@latest; \
        go install golang.org/x/tools/cmd/goimports@latest; \
        go install github.com/go-delve/delve/cmd/dlv@latest; \
        go install honnef.co/go/tools/cmd/staticcheck@latest; \
        go install github.com/go-task/task/v3/cmd/task@latest; \
    fi

LABEL org.opencontainers.image.source="https://github.com/rin721/dsh-docker"

EXPOSE 3080

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/usr/local/bin/start-dsh-web"]
