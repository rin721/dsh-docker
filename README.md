# dsh-docker

DeepSeek Harness 的通用 Docker 开发与运行环境。

项目采用 **“仓库即部署单元（repository as deployment unit）”** 的方式：仓库 clone 到任意目录即可部署，默认的运行数据、工作区、DSH 状态与登录数据都跟随该仓库保存在 `./.runtime/` 中，不依赖 `/var/lib/.dsh`、`/opt/...` 等固定宿主机路径。

同时，项目给 DeepSeek Harness 前置了一个轻量登录层：

```text
Browser
   |
   | DSH_PORT
   v
Authentication Gateway (Caddy)
   |
   | forward_auth
   v
Tinyauth
   |
   | authenticated
   v
DeepSeek Harness
   |
   v
/workspace
```

核心部署不强制：

- 域名；
- TLS/HTTPS；
- 80/443；
- 固定宿主机目录；
- SSH 隧道；
- Tailscale/VPN；
- Docker Socket 挂载。

如果需要公网正式访问，可以将 Core 监听在 `127.0.0.1`，然后使用现有 Nginx、1Panel/OpenResty、Caddy、Cloudflare Tunnel 等作为外层入口；仓库也提供一个 **可选** 的 Caddy HTTPS Edge。

---

## 1. 特性

### DeepSeek Harness

- 安装 `@deepseek-ai/dsh`；
- Web UI 运行在独立 DSH 容器；
- `/workspace` 作为 Agent 工作目录；
- DSH 配置/会话持久化；
- 默认 `workspace-write` 权限模式；
- 不挂载宿主机 Docker Socket。

### 完整开发环境

DSH 容器包含：

- Node.js LTS、npm、pnpm、TypeScript、tsx；
- Go、gopls、goimports、Delve、staticcheck、Task；
- Rust stable、cargo、rustfmt、clippy、rust-analyzer；
- Python 3、pip、pipx、venv；
- Git、Git LFS、OpenSSH Client；
- curl、wget、jq、ripgrep、fd、fzf；
- gcc/g++、make、CMake、Ninja；
- Clang、clangd、GDB、LLDB、strace；
- SQLite、OpenSSL、protobuf；
- tmux、vim、nano、rsync、zip/unzip、shellcheck；
- 常用网络排查工具。

### 登录保护

- Tinyauth 本地用户名/密码登录；
- bcrypt 密码 Hash；
- Session Cookie；
- 登录失败次数限制；
- Caddy `forward_auth`；
- DSH 与 Tinyauth 本体不直接向宿主机发布端口；
- 对外只发布 Authentication Gateway 的可配置端口。

### 生命周期

```text
git clone
   |
   v
./scripts/deploy.sh
   |
   v
running
   |
   +---- ./scripts/rebuild.sh
   |          |
   |          +--> 删除旧容器/旧 DSH 镜像
   |          +--> 重建
   |
   +---- ./scripts/update.sh
              |
              +--> git fetch / git pull --ff-only
              +--> 删除旧容器/旧 DSH 镜像
              +--> 使用刚 pull 下来的新版脚本重建
```

`.runtime/` 在 deploy / rebuild / update / stop 过程中都不会被自动删除。

---

# 2. 架构

## Core

```text
                          Docker host

Browser / Reverse Proxy
          |
          | ${DSH_PORT}
          v
+-------------------------------+
| gateway                       |
| Caddy                         |
|                               |
| :3080 protected DSH endpoint  |
| :3081 public login endpoint   |
+-------------+-----------------+
              |
              | forward_auth
              v
        +-----------+
        | Tinyauth  |
        | :3000     |
        +-----+-----+
              |
              | authenticated
              v
        +-----------+
        | DSH       |
        | :3080     |
        +-----+-----+
              |
              v
         /workspace
              |
              | bind mount
              v
<repo>/.runtime/workspace
```

宿主机不会直接映射：

```text
DSH container      :3080
Tinyauth container :3000
```

真正发布的是 Gateway：

```text
${BIND_ADDRESS}:${DSH_PORT}  -> gateway:3080
${BIND_ADDRESS}:${AUTH_PORT} -> gateway:3081
```

---

# 3. 仓库目录

```text
dsh-docker/
├── Dockerfile
├── compose.yaml
├── compose.edge.caddy.yaml
│
├── Caddyfile.gateway
├── Caddyfile.edge
├── start-dsh-web.sh
│
├── .env.example
├── .gitignore
├── .dockerignore
├── Makefile
├── README.md
│
├── auth/
│   └── README.md
│
├── examples/
│   └── nginx.conf
│
├── docs/
│
└── scripts/
    ├── lib.sh
    ├── init-runtime.sh
    ├── create-user.sh
    ├── list-users.sh
    ├── remove-user.sh
    ├── deploy.sh
    ├── rebuild.sh
    ├── update.sh
    ├── check.sh
    ├── doctor.sh
    ├── stop.sh
    ├── cleanup-legacy.sh
    ├── edge-up.sh
    └── edge-down.sh
```

首次运行后生成：

```text
dsh-docker/
├── .env                    # Git ignored
└── .runtime/               # Git ignored
    ├── workspace/
    ├── dsh-home/
    ├── tinyauth/
    │   ├── config.yml
    │   └── data/
    └── edge/
        └── caddy/
            ├── data/
            └── config/
```

---

# 4. 持久化模型

默认：

```dotenv
RUNTIME_DIR=./.runtime
```

所以仓库 clone 在：

```text
/var/lib/dsh-docker
```

运行数据就是：

```text
/var/lib/dsh-docker/.runtime
```

如果 clone 在：

```text
/home/xiaolin/services/dsh-docker
```

运行数据自然变成：

```text
/home/xiaolin/services/dsh-docker/.runtime
```

没有任何固定绝对路径要求。

也可以主动覆盖：

```dotenv
RUNTIME_DIR=./runtime
```

或：

```dotenv
RUNTIME_DIR=/mnt/ssd/dsh-runtime
```

### 映射关系

| 宿主机 | 容器 | 用途 |
|---|---|---|
| `${RUNTIME_DIR}/workspace` | `/workspace` | Agent 项目工作区 |
| `${RUNTIME_DIR}/dsh-home` | `/home/node/.dsh` | DSH 配置、会话、插件等 |
| `${RUNTIME_DIR}/tinyauth/config.yml` | `/config/tinyauth.yml` | 登录用户 bcrypt 配置 |
| `${RUNTIME_DIR}/tinyauth/data` | `/data` | Tinyauth SQLite/runtime |
| `${RUNTIME_DIR}/edge/caddy/*` | `/data`、`/config` | 可选 HTTPS Edge 数据 |

---

# 5. 前置要求

宿主机只需要：

- Linux；
- Git；
- Docker Engine；
- Docker Compose v2 (`docker compose`)；
- 能访问构建所需的软件源/镜像仓库。

宿主机 **不需要** 安装：

- Node.js；
- Go；
- Rust；
- Python 开发环境；
- DeepSeek Harness。

检查：

```bash
git --version
docker --version
docker compose version
docker info
```

也可以 clone 后执行：

```bash
./scripts/doctor.sh
```

---

# 6. 首次部署

## 6.1 Clone

**推荐始终通过 Git clone 部署。** `scripts/update.sh` 依赖 `.git` 来执行 `git fetch` / `git pull`。

ZIP/TAR 包更适合作为源码快照、审阅或上传到仓库；如果直接解压运行，`deploy.sh` / `rebuild.sh` 可以使用，但 `update.sh` 在没有 `.git` 时会明确拒绝执行。

仓库可以 clone 到任意目录：

```bash
git clone https://github.com/rin721/dsh-docker.git
cd dsh-docker
```

如果 Git 没有保留执行位，可执行：

```bash
chmod +x scripts/*.sh start-dsh-web.sh
```

## 6.2 默认一键部署

直接：

```bash
./scripts/deploy.sh
```

首次执行会自动：

1. 检查 Docker / Compose；
2. 从 `.env.example` 创建 `.env`；
3. 创建 `.runtime/`；
4. 初始化 workspace、DSH home、Tinyauth 数据目录；
5. 如果没有用户，进入交互式用户创建；
6. 使用 Tinyauth 官方 CLI 生成 bcrypt Hash；
7. 拉取 Tinyauth 和 Gateway Caddy；
8. 构建 DSH 开发镜像；
9. 启动完整 Compose 项目。

第一次会看到：

```text
Repository runtime: /path/to/dsh-docker/.runtime

首次部署需要创建登录用户。
用户名: xiaolin
密码:
再次输入密码:
```

成功后类似：

```text
用户 'xiaolin' 创建/更新成功。
配置文件：/path/to/dsh-docker/.runtime/tinyauth/config.yml
明文密码不会保存。
```

随后继续构建并启动。

---

# 7. `.env` 完整配置

首次 `deploy.sh` 会自动执行：

```bash
cp .env.example .env
```

你也可以部署前自己创建：

```bash
cp .env.example .env
nano .env
```

## 7.1 Runtime

### `RUNTIME_DIR`

```dotenv
RUNTIME_DIR=./.runtime
```

运行数据目录。

支持：

```text
./.runtime
./runtime
../dsh-data
/mnt/ssd/dsh
```

### `RUNTIME_UID` / `RUNTIME_GID`

```dotenv
RUNTIME_UID=1000
RUNTIME_GID=1000
```

用于 root 部署时修正 DSH/Tinyauth bind mount 的数值权限。

默认镜像栈按 UID/GID `1000:1000` 运行需要持久化数据的非 root 进程。

一般不需要修改。

---

## 7.2 Core 网络

### `BIND_ADDRESS`

默认：

```dotenv
BIND_ADDRESS=127.0.0.1
```

含义：

```text
127.0.0.1
```

仅服务器本机或本机反向代理可以访问。

这是推荐默认值。

如果是受信任的 LAN 测试环境：

```dotenv
BIND_ADDRESS=0.0.0.0
```

则 Gateway 会监听所有网卡。

> 不建议直接把 HTTP 用户名/密码登录暴露到公网。

### `DSH_PORT`

```dotenv
DSH_PORT=3080
```

受保护的 DSH Gateway 端口。

可以改成：

```dotenv
DSH_PORT=13080
```

### `AUTH_PORT`

```dotenv
AUTH_PORT=3081
```

Tinyauth 登录页面 Gateway 端口。

必须和 `DSH_PORT` 不同。

### `AUTH_URL`

```dotenv
AUTH_URL=http://localhost:3081
```

这是 **用户浏览器实际访问 Tinyauth 的 URL**，不是容器内部地址。

本地测试：

```dotenv
AUTH_URL=http://localhost:3081
```

LAN：

```dotenv
AUTH_URL=http://192.168.1.20:9001
```

外部反向代理：

```dotenv
AUTH_URL=https://auth.example.com
```

---

## 7.3 Tinyauth

### `TINYAUTH_SECURE_COOKIE`

HTTP：

```dotenv
TINYAUTH_SECURE_COOKIE=false
```

HTTPS：

```dotenv
TINYAUTH_SECURE_COOKIE=true
```

如果开启 `true`，浏览器只会通过 HTTPS 发送认证 Cookie。

### `TINYAUTH_SESSION_EXPIRY`

```dotenv
TINYAUTH_SESSION_EXPIRY=86400
```

Session 有效期，单位秒。

常见：

```text
3600    = 1 小时
86400   = 1 天
604800  = 7 天
```

### `TINYAUTH_SESSION_MAX_LIFETIME`

```dotenv
TINYAUTH_SESSION_MAX_LIFETIME=0
```

最大 Session 生命周期；`0` 使用 Tinyauth 默认/不额外限制。

### `TINYAUTH_LOGIN_TIMEOUT`

```dotenv
TINYAUTH_LOGIN_TIMEOUT=300
```

登录流程超时秒数。

### `TINYAUTH_LOGIN_MAX_RETRIES`

```dotenv
TINYAUTH_LOGIN_MAX_RETRIES=3
```

允许的登录失败重试次数。

### `TINYAUTH_TRUSTED_PROXIES`

默认空：

```dotenv
TINYAUTH_TRUSTED_PROXIES=
```

只有需要让 Tinyauth 信任特定代理转发的真实客户端 IP，或者配置基于 IP 的 ACL 时再设置。

### `AUTH_UI_TITLE`

```dotenv
AUTH_UI_TITLE="DeepSeek Harness"
```

项目脚本使用无 `eval` 的 dotenv 解析器读取 `.env`；包含空格的值建议使用引号，以同时保持 Docker Compose 与人工阅读的一致性。

### `TINYAUTH_VERSION`

```dotenv
TINYAUTH_VERSION=v5.1.3
```

建议使用明确版本，不建议生产环境随意使用 `latest`。

---

## 7.4 DSH

### `DSH_VERSION`

默认：

```dotenv
DSH_VERSION=latest
```

表示 Docker build 时：

```bash
npm install -g @deepseek-ai/dsh@latest
```

长期运行时建议在验证后固定版本，例如：

```dotenv
DSH_VERSION=0.1.0-rc.x
```

### `DSH_PERMISSION_MODE`

```dotenv
DSH_PERMISSION_MODE=workspace-write
```

表示 DSH 可操作 `/workspace`。

### `DSH_TELEMETRY_DISABLED`

```dotenv
DSH_TELEMETRY_DISABLED=1
```

### `INSTALL_GO_DEV_TOOLS`

```dotenv
INSTALL_GO_DEV_TOOLS=true
```

关闭可减少镜像构建时间：

```dotenv
INSTALL_GO_DEV_TOOLS=false
```

---

## 7.5 开发工具版本

```dotenv
NODE_VERSION=24.18.0
GO_VERSION=1.26.5
RUST_TOOLCHAIN=stable
PNPM_VERSION=11.7.0
```

修改以后需要重新 build：

```bash
./scripts/rebuild.sh
```

---

## 7.6 容器内代理

例如：

```dotenv
HTTP_PROXY=http://proxy.example.com:7890
HTTPS_PROXY=http://proxy.example.com:7890
NO_PROXY=localhost,127.0.0.1,dsh,tinyauth,gateway
```

这些变量会进入 DSH 容器，供：

```text
git
curl
npm/pnpm
go
cargo
pip
```

等工具使用。

---

# 8. 三种典型部署模式

## 模式 A：服务器本机 / 本地反向代理

最安全的默认 Core：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
AUTH_PORT=3081
AUTH_URL=http://localhost:3081
TINYAUTH_SECURE_COOKIE=false
```

只有宿主机可以连接：

```text
127.0.0.1:3080
127.0.0.1:3081
```

适合：

- 同机 Nginx；
- 同机 1Panel；
- 同机 Caddy；
- 调试。

---

## 模式 B：局域网直接访问

假设服务器：

```text
192.168.1.20
```

配置：

```dotenv
BIND_ADDRESS=0.0.0.0
DSH_PORT=9000
AUTH_PORT=9001
AUTH_URL=http://192.168.1.20:9001
TINYAUTH_SECURE_COOKIE=false
```

访问：

```text
http://192.168.1.20:9000
```

未登录时会跳到：

```text
http://192.168.1.20:9001
```

此模式仅建议受信任网络/临时测试。

---

## 模式 C：已有 Nginx / 1Panel / OpenResty

Core：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=13080
AUTH_PORT=13081
AUTH_URL=https://auth.example.com
TINYAUTH_SECURE_COOKIE=true
```

反向代理：

```text
https://dsh.example.com
        -> http://127.0.0.1:13080

https://auth.example.com
        -> http://127.0.0.1:13081
```

项目附带：

```text
examples/nginx.conf
```

正式的多子域认证建议：

```text
auth.example.com
dsh.example.com
```

使用相同父域。

---

# 9. 可选 Caddy HTTPS Edge

Core 本身不会要求 80/443。

如果你没有现成反向代理，但主动希望仓库自己提供域名 + 自动 HTTPS，可以启用：

```text
compose.edge.caddy.yaml
Caddyfile.edge
```

## 9.1 配置

编辑 `.env`：

```dotenv
DSH_DOMAIN=dsh.example.com
AUTH_DOMAIN=auth.example.com
ACME_EMAIL=admin@example.com

AUTH_URL=https://auth.example.com
TINYAUTH_SECURE_COOKIE=true

EDGE_BIND_ADDRESS=0.0.0.0
EDGE_HTTP_PORT=80
EDGE_HTTPS_PORT=443
```

DNS：

```text
dsh.example.com  -> server IP
auth.example.com -> server IP
```

## 9.2 启动

```bash
./scripts/edge-up.sh
```

## 9.3 停止

```bash
./scripts/edge-down.sh
```

Edge 数据保存在：

```text
.runtime/edge/caddy
```

---

# 10. 登录用户管理

真实用户配置：

```text
.runtime/tinyauth/config.yml
```

不会提交到 Git。

## 创建用户

```bash
./scripts/create-user.sh
```

例如：

```text
用户名: xiaolin
密码:
再次输入密码:
```

脚本调用 **Tinyauth 官方 CLI** 生成 bcrypt Hash。

重要：脚本不再依赖 Tinyauth CLI 的：

```text
Environment variable:
CLI flags:
YAML config:
```

等展示文本，而是直接从完整 CLI 输出提取标准 bcrypt token，因此兼容不同 patch 版本的输出格式。

生成：

```yaml
auth:
  users:
    - "xiaolin:$2a$10$..."
```

明文密码不会写入磁盘。

如果同名用户已经存在，再运行一次 `create-user.sh` 会替换该用户的密码 Hash。

## 查看用户

```bash
./scripts/list-users.sh
```

或：

```bash
make users
```

只显示用户名，不显示 Hash。

## 删除用户

```bash
./scripts/remove-user.sh xiaolin
```

或交互：

```bash
./scripts/remove-user.sh
```

运行中的服务需要重新加载：

```bash
docker compose restart tinyauth gateway
```

---

# 11. 查看状态

```bash
./scripts/check.sh
```

或：

```bash
docker compose ps
```

日志：

```bash
docker compose logs -f --tail=200
```

只看 DSH：

```bash
docker compose logs -f --tail=200 dsh
```

Tinyauth：

```bash
docker compose logs -f --tail=200 tinyauth
```

Gateway：

```bash
docker compose logs -f --tail=200 gateway
```

---

# 12. 进入开发容器

```bash
docker compose exec dsh bash
```

默认：

```bash
pwd
```

输出：

```text
/workspace
```

验证：

```bash
node --version
npm --version
pnpm --version

go version
gopls version
dlv version

rustc --version
cargo --version
rust-analyzer --version

python --version
pip --version

git --version
curl --version

dsh --version
```

---

# 13. 项目工作区

宿主机：

```text
<repo>/.runtime/workspace
```

容器：

```text
/workspace
```

例如：

```bash
cd .runtime/workspace
git clone https://github.com/example/project.git
```

DSH 看到：

```text
/workspace/project
```

Agent 对：

```text
/workspace/project/main.go
```

的修改会直接持久化到宿主机：

```text
.runtime/workspace/project/main.go
```

---

# 14. 更新仓库

这是项目设计的主要使用方式。

以后 GitHub 仓库更新时，不需要重新 clone。

进入现有仓库：

```bash
cd /wherever/dsh-docker
```

运行：

```bash
./scripts/update.sh
```

完整流程：

```text
检查当前目录是 Git repository
        |
        v
检查 tracked 文件是否存在未提交修改
        |
        v
记录当前 DSH build image ID
        |
        v
git fetch --prune
        |
        v
git pull --ff-only
        |
        v
exec 新版本 scripts/rebuild.sh
        |
        v
docker compose down --remove-orphans --rmi local
        |
        v
删除/清理旧 DSH image
        |
        v
pull Tinyauth / Gateway
        |
        v
build --pull dsh
        |
        v
up -d --remove-orphans
        |
        v
prune dangling images
```

### 为什么使用 `exec scripts/rebuild.sh`

因为 `git pull` 可能连 `rebuild.sh` 自己也更新。

执行：

```bash
exec "${ROOT_DIR}/scripts/rebuild.sh"
```

可以确保重建阶段使用的是 **刚刚 pull 下来的新版重建逻辑**。

### 本地修改保护

如果存在：

```text
M Dockerfile
M compose.yaml
```

`update.sh` 会拒绝继续，不会自动覆盖。

先选择：

```bash
git commit
```

或者：

```bash
git stash
```

或者：

```bash
git restore ...
```

`.env` 和 `.runtime/` 已被 ignore，所以不会阻塞 update。

---

# 15. 仅重建，不 Git Pull

修改了：

```text
Dockerfile
compose.yaml
start-dsh-web.sh
.env 中的 DSH/Node/Go/Rust 版本
```

可以：

```bash
./scripts/rebuild.sh
```

它会：

1. 停止/删除当前 Compose 容器与本项目本地构建镜像；
2. 使用更新前记录的 image ID 做兼容性残留清理；
3. 保留 `.runtime`；
4. 拉取外部镜像；
5. build 新 DSH；
6. 启动新容器。

---

# 16. 停止

```bash
./scripts/stop.sh
```

等价于核心意义上的：

```bash
docker compose down --remove-orphans
```

不会删除：

```text
.runtime/workspace
.runtime/dsh-home
.runtime/tinyauth
```

---

# 17. 完全删除运行数据

**此操作不可恢复。**

先：

```bash
./scripts/stop.sh
```

确认：

```bash
pwd
```

然后：

```bash
rm -rf .runtime
```

下次：

```bash
./scripts/deploy.sh
```

会视为首次部署。

---

# 18. 备份

最重要的是：

```text
.runtime/
.env
```

备份运行数据：

```bash
tar -czf dsh-runtime-backup.tar.gz .runtime .env
```

如果 workspace 中项目本身都已经 Git push，那么也可以只备份：

```text
.runtime/dsh-home
.runtime/tinyauth
.env
```

---

# 19. Compose project 名称

项目故意没有：

```yaml
name: deepseek-harness
```

也没有：

```yaml
container_name: deepseek-harness
```

Docker Compose 默认根据仓库目录名生成 project 名。

例如：

```text
/opt/dsh-docker
```

可能生成：

```text
dsh-docker-dsh-1
dsh-docker-tinyauth-1
dsh-docker-gateway-1
```

如果另一个 clone：

```text
/opt/dsh-docker-test
```

则成为另一个独立 Compose project。

因此不会被固定 `container_name` 卡死。

---

# 20. 旧版本迁移

旧版项目曾使用：

```text
Compose project: deepseek-harness
container_name:
  deepseek-harness
  dsh-tinyauth
  dsh-gateway
  dsh-caddy
```

现在：

```text
scripts/cleanup-legacy.sh
```

会检查 Docker Compose label：

```text
com.docker.compose.project=deepseek-harness
```

只有确认属于旧项目才清理旧容器。

不会仅根据名字盲目删除一个无关容器。

---

# 21. Git Ignore

运行时统一：

```gitignore
/.runtime/
```

本机配置：

```gitignore
.env
.env.*
!.env.example
```

所以以后仓库新增：

```text
LICENSE
Taskfile.yml
scripts/new-script.sh
docs/xxx.md
compose.xxx.yaml
```

都会正常被 Git 识别。

不需要维护：

```gitignore
!Dockerfile
!README.md
!xxx
```

这种反向白名单。

---

# 22. 安全边界

## DSH 无 Docker Socket

项目不会：

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

因此 DSH Agent 默认不能：

```text
控制宿主机 Docker
创建 privileged 容器
通过 Docker API 获得等价 host root 权限
```

DSH 能操作的是：

```text
/workspace
/home/node/.dsh
容器自己的开发环境
网络
```

## 非 root DSH

DSH 使用 Node 官方镜像中的非 root `node` 用户运行。

## 密码

Tinyauth 用户配置保存：

```text
username:bcrypt_hash
```

不保存明文密码。

`.runtime/tinyauth/config.yml` 默认权限：

```text
0600
```

root 部署时所有权会调整给容器需要的数值 UID/GID。

## 公网访问

不要使用：

```dotenv
BIND_ADDRESS=0.0.0.0
AUTH_URL=http://PUBLIC_IP:3081
```

然后直接在公网传输密码。

正式公网部署应该：

```text
Browser
  |
 HTTPS
  v
Nginx/Caddy/1Panel/Cloudflare
  |
  v
127.0.0.1:${DSH_PORT}/${AUTH_PORT}
```

---

# 23. 故障排查

## 23.1 `no configuration file provided: not found`

说明你不在仓库根目录。

错误：

```bash
cd /parent
docker compose up
```

正确：

```bash
cd /parent/dsh-docker
./scripts/deploy.sh
```

---

## 23.2 `无法从 Tinyauth CLI 输出中提取 bcrypt Hash`

新版脚本已经不再匹配固定的：

```text
TINYAUTH_AUTH_USERS=...
```

或：

```text
--auth.users=...
```

而是直接提取：

```text
$2a$10$...
$2b$10$...
$2y$10$...
```

如果仍然出现该错误，执行：

```bash
docker run --rm \
  ghcr.io/tinyauthapp/tinyauth:v5.1.3 \
  user create --username test --password test123456
```

把完整输出与：

```bash
./scripts/doctor.sh
```

结果一起检查。

---

## 23.3 `Permission denied`

查看：

```bash
ls -ln .runtime
ls -ln .runtime/tinyauth
```

默认需要 UID/GID：

```text
1000:1000
```

root 下重新初始化：

```bash
./scripts/init-runtime.sh
```

---

## 23.4 端口被占用

查看：

```bash
ss -lntp | grep -E ':(3080|3081)\\b'
```

修改 `.env`：

```dotenv
DSH_PORT=13080
AUTH_PORT=13081
```

然后：

```bash
./scripts/rebuild.sh
```

---

## 23.5 登录后反复跳回登录页

重点检查：

```dotenv
AUTH_URL=
TINYAUTH_SECURE_COOKIE=
```

HTTP：

```dotenv
AUTH_URL=http://...
TINYAUTH_SECURE_COOKIE=false
```

HTTPS：

```dotenv
AUTH_URL=https://...
TINYAUTH_SECURE_COOKIE=true
```

如果使用两个域名，建议使用同一父域：

```text
auth.example.com
dsh.example.com
```

浏览器旧 Cookie 也可能影响测试，可清除对应站点 Cookie 后重试。

---

## 23.6 DSH unhealthy

```bash
docker compose ps
docker compose logs --tail=200 dsh
```

进入：

```bash
docker compose exec dsh bash
```

检查：

```bash
dsh --version
ps aux
curl -v http://127.0.0.1:3080/
```

---

## 23.7 构建时网络失败

如果：

```text
go.dev
npm registry
crates.io
GitHub
```

访问受限，在 `.env` 配置：

```dotenv
HTTP_PROXY=http://...
HTTPS_PROXY=http://...
```

再：

```bash
./scripts/rebuild.sh
```

注意：Docker **build 阶段**的网络代理还取决于 Docker daemon/buildkit 自己的代理配置；DSH 容器环境变量主要影响运行时。

---

# 24. 常用命令速查

```bash
# 首次/常规部署
./scripts/deploy.sh

# 环境诊断
./scripts/doctor.sh

# 状态 + 日志摘要
./scripts/check.sh

# 创建/修改用户
./scripts/create-user.sh

# 查看用户
./scripts/list-users.sh

# 删除用户
./scripts/remove-user.sh xiaolin

# 当前代码重新构建
./scripts/rebuild.sh

# git pull + 删除旧运行实例 + 重建
./scripts/update.sh

# 查看完整日志
docker compose logs -f --tail=200

# 进入 DSH
docker compose exec dsh bash

# 停止
./scripts/stop.sh

# 启用可选 HTTPS Edge
./scripts/edge-up.sh

# 停止可选 Edge
./scripts/edge-down.sh
```

Makefile 等价入口：

```bash
make doctor
make deploy
make user
make users
make rebuild
make update
make check
make logs
make shell
make stop
make edge-up
```

---

# 25. 更新策略建议

生产/长期运行建议固定：

```dotenv
TINYAUTH_VERSION=v5.1.3
GATEWAY_CADDY_VERSION=2.11.4
NODE_VERSION=24.18.0
GO_VERSION=1.26.5
```

DSH 如果已经验证稳定，也建议从：

```dotenv
DSH_VERSION=latest
```

切换成明确版本。

然后仓库升级统一：

```bash
./scripts/update.sh
```

而不是手工：

```bash
docker rm ...
docker rmi ...
docker build ...
```

这样部署生命周期保持一致。

---

# 26. 设计原则

这个仓库最终遵循以下边界：

```text
Git repository
      |
      +-- declarative deployment code
      |     Dockerfile
      |     compose.yaml
      |     scripts/
      |
      +-- local configuration
      |     .env
      |
      +-- local persistent state
            .runtime/
```

部署代码可以随 Git 更新。

本机配置和运行数据不参与 Git pull，也不会在更新过程中被删除。

因此生命周期就是：

```text
clone once
   |
   v
deploy
   |
   v
use
   |
   v
update.sh
   |
   +--> pull repository
   +--> replace old containers/image
   +--> reuse persistent runtime
   |
   v
continue
```
