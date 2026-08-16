# dsh-docker

一个以 **Git 仓库本身作为部署单元** 的 DeepSeek Harness Docker 开发环境。

目标是保持部署边界简单、通用：

- 不固定宿主机 `/var/lib/.dsh` 等路径；仓库 clone 到哪里就从哪里运行；
- 默认运行数据保存在仓库自己的 `.runtime/`；
- Core 不强制域名、TLS、80/443；
- 对外端口、监听地址均由 `.env` 配置；
- DeepSeek Harness、Node.js、Go、Rust、Python 和常用开发工具都运行在 DSH 容器内；
- Caddy Gateway 在 DSH 前提供用户名/密码认证；
- 用户侧只需要浏览器，无需 SSH 隧道、VPN 或额外客户端；
- 更新仓库后可通过 `update.sh` 自动停止旧容器、删除旧 DSH 构建镜像、构建新镜像并启动；
- `.runtime` 在重建/更新过程中保持不变。

> **安全提醒**：Core 登录层使用 HTTP Basic Authentication。Basic Auth 必须运行在可信网络或 HTTPS 后面。默认 `BIND_ADDRESS=127.0.0.1`，适合由 Nginx、1Panel、Caddy 等本机反向代理提供 HTTPS。不要把明文 HTTP Basic Auth 直接暴露到公网。

---

## 1. 架构

默认 Core：

```text
Browser / Reverse Proxy
          |
          | configurable host:port
          v
+-----------------------------+
| Caddy Authentication Gateway|
| Basic Auth                  |
+--------------+--------------+
               |
               | authenticated
               v
+-----------------------------+
| DeepSeek Harness            |
| /workspace                  |
| Node / Go / Rust / Python   |
+--------------+--------------+
               |
               | bind mount
               v
<repo>/.runtime/workspace
```

Core 只有两个服务：

```text
dsh
  DeepSeek Harness + 完整开发工具链

gateway
  Caddy Basic Auth + reverse_proxy
```

可选 HTTPS Edge：

```text
Internet
   |
 HTTPS :443
   v
Caddy Edge
   |
   v
Core Gateway (Basic Auth)
   |
   v
DSH
```

也可以完全不用仓库提供的 Edge，而使用已有的 Nginx、1Panel、OpenResty、Traefik、Cloudflare 等。

---

## 2. 目录结构

仓库：

```text
dsh-docker/
├── Dockerfile
├── compose.yaml
├── compose.edge.caddy.yaml
├── Caddyfile.gateway
├── Caddyfile.edge
├── start-dsh-web.sh
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

首次运行后自动生成：

```text
dsh-docker/
├── .env                         # 本地配置，Git ignore
└── .runtime/                    # 所有运行数据，Git ignore
    ├── workspace/               # -> DSH /workspace
    ├── dsh-home/                # -> DSH /home/node/.dsh
    ├── auth/
    │   └── users.caddy          # Basic Auth 用户名 + bcrypt Hash
    └── edge/
        └── caddy/
            ├── data/            # 可选 Edge TLS/ACME 数据
            └── config/
```

没有任何必须写死到 `/var/lib/.dsh` 的路径。

例如仓库位于：

```text
/var/lib/dsh-docker
```

默认 Runtime 就是：

```text
/var/lib/dsh-docker/.runtime
```

仓库位于：

```text
/root/apps/dsh-docker
```

默认 Runtime 就是：

```text
/root/apps/dsh-docker/.runtime
```

---

## 3. 宿主机要求

宿主机只要求：

- Linux；
- Git；
- Docker Engine；
- Docker Compose v2（`docker compose`）；
- 能访问 Docker Hub、npm、Go/Rust 下载源等构建所需网络资源。

宿主机**不需要**预装 Node.js、Go、Rust、Python 开发环境，这些都在 DSH 容器中。

检查：

```bash
git --version
docker --version
docker compose version
docker info
```

---

## 4. 快速部署

### 4.1 Clone

```bash
git clone https://github.com/rin721/dsh-docker.git
cd dsh-docker
```

仓库可以 clone 到任意目录。

### 4.2 首次部署

直接执行：

```bash
./scripts/deploy.sh
```

如果 `.env` 不存在，脚本会自动：

```text
.env.example -> .env
```

如果尚未创建认证用户，会交互提示：

```text
首次部署需要创建登录用户。
用户名: xiaolin
密码:
再次输入密码:
```

密码不会明文写入磁盘。脚本通过 Caddy 官方 `hash-password` 生成 bcrypt Hash，最终写入：

```text
.runtime/auth/users.caddy
```

随后自动：

```text
初始化 .runtime
      ↓
校验 Compose / Gateway 配置
      ↓
拉取 Caddy Gateway 镜像
      ↓
构建 DSH 开发镜像
      ↓
启动 dsh + gateway
```

### 4.3 查看状态

```bash
./scripts/check.sh
```

或者：

```bash
docker compose ps
docker compose logs -f --tail=200
```

默认地址：

```text
http://127.0.0.1:3080
```

浏览器会显示 HTTP Basic Auth 用户名/密码弹窗；认证成功后进入 DeepSeek Harness。

---

## 5. 配置 `.env`

首次 `deploy.sh` 自动创建：

```bash
cp .env.example .env
```

可以手动编辑：

```bash
nano .env
```

### 5.1 Runtime

```dotenv
RUNTIME_DIR=./.runtime
RUNTIME_UID=1000
RUNTIME_GID=1000
```

`RUNTIME_DIR` 支持：

```dotenv
RUNTIME_DIR=./.runtime
```

```dotenv
RUNTIME_DIR=./data
```

或者绝对路径：

```dotenv
RUNTIME_DIR=/mnt/ssd/dsh-runtime
```

默认推荐仓库内 `.runtime`，这样仓库天然成为完整部署单元。

### 5.2 网络

默认：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

含义：

```text
127.0.0.1:3080 -> Gateway -> DSH
```

#### 本机反代模式（推荐服务器部署）

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=13080
```

然后让 Nginx/1Panel/Caddy：

```text
https://dsh.example.com
        ↓
http://127.0.0.1:13080
```

#### 局域网直接访问

```dotenv
BIND_ADDRESS=0.0.0.0
DSH_PORT=3080
```

浏览器：

```text
http://192.168.1.20:3080
```

仅建议可信局域网。HTTP Basic Auth 的凭据不能在不可信网络上通过明文 HTTP 传输。

#### 指定某块网卡

```dotenv
BIND_ADDRESS=192.168.1.20
DSH_PORT=9000
```

### 5.3 登录层

```dotenv
AUTH_REALM="DeepSeek Harness"
AUTH_BCRYPT_COST=14
GATEWAY_CADDY_VERSION=2.11.4
```

`AUTH_REALM` 是浏览器认证弹窗显示的 Realm。

真实用户名和 Hash 不放 `.env`，而放：

```text
.runtime/auth/users.caddy
```

避免 `$` Hash 被 Compose 环境变量插值影响。

### 5.4 DeepSeek Harness

```dotenv
DSH_VERSION=latest
DSH_PERMISSION_MODE=workspace-write
DSH_TELEMETRY_DISABLED=1
INSTALL_GO_DEV_TOOLS=true
```

长期环境建议将 `DSH_VERSION` 固定为你验证过的具体版本，以提高可重复构建能力。

### 5.5 开发工具版本

```dotenv
NODE_VERSION=24.18.0
GO_VERSION=1.26.5
RUST_TOOLCHAIN=stable
PNPM_VERSION=11.7.0
```

### 5.6 代理

如服务器构建或容器网络需要代理：

```dotenv
HTTP_PROXY=http://proxy.example:7890
HTTPS_PROXY=http://proxy.example:7890
NO_PROXY=localhost,127.0.0.1,dsh,gateway
```

这些变量会传给 DSH 容器中的 Node、npm、git、curl 等工具。

---

## 6. 用户管理

### 创建用户 / 修改密码

```bash
./scripts/create-user.sh
```

同名用户再次创建 = 更新该用户密码。

脚本通过 stdin 把明文密码传给临时 Caddy 容器进行 Hash，不使用 `--plaintext <password>` 命令参数，因此明文密码不会写进仓库或用户配置文件。

### 查看用户

```bash
./scripts/list-users.sh
```

只显示用户名，不显示 Hash。

### 删除用户

```bash
./scripts/remove-user.sh
```

如果删掉最后一个用户，脚本会停止 Gateway，避免产生无认证配置的异常状态。随后必须：

```bash
./scripts/create-user.sh
```

重新创建用户。

### 用户文件

```text
.runtime/auth/users.caddy
```

示例：

```text
alice $2a$14$...
bob $2a$14$...
```

它只存 bcrypt Hash，但仍应视为敏感数据：Hash 可被离线猜解，不应提交 Git 或公开。

---

## 7. DSH 工作区

宿主机：

```text
<repo>/.runtime/workspace
```

容器：

```text
/workspace
```

直接把开发项目 clone 到：

```bash
cd .runtime/workspace
git clone https://github.com/your/project.git
```

进入容器：

```bash
docker compose exec dsh bash
```

容器内：

```bash
cd /workspace/project
```

DSH Web/Agent 对 `/workspace` 的修改会直接持久化到宿主机 `.runtime/workspace`。

---

## 8. 开发环境

DSH 镜像包含：

### Node.js

```text
node
npm
pnpm
typescript
tsx
```

### Go

```text
go
gofmt
gopls
goimports
dlv
staticcheck
task
```

### Rust

```text
rustup
rustc
cargo
rustfmt
clippy
rust-analyzer
```

### Python

```text
python3
python
pip
pipx
venv
```

### 编译/调试

```text
gcc
g++
make
cmake
ninja
clang
clangd
gdb
lldb
strace
protobuf-compiler
```

### 通用 CLI

```text
git
git-lfs
ssh
curl
wget
jq
ripgrep
fd
fzf
tree
tmux
vim
nano
rsync
zip
unzip
openssl
sqlite3
shellcheck
dig
ping
ip
lsof
socat
```

检查：

```bash
docker compose exec dsh bash

node --version
pnpm --version
go version
rustc --version
cargo --version
python --version
git --version
curl --version
dsh --version
```

---

## 9. 更新仓库并重建

日常升级只需要：

```bash
./scripts/update.sh
```

流程：

```text
检查 Git working tree
      ↓
记录当前 DSH image ID
      ↓
git fetch --prune
      ↓
git pull --ff-only
      ↓
执行“刚 pull 下来的”新版 rebuild.sh
      ↓
docker compose down --remove-orphans --rmi local
      ↓
删除残留旧 DSH build image
      ↓
pull Gateway
      ↓
build --pull dsh
      ↓
up -d
      ↓
清理 dangling images
```

不会执行：

```bash
rm -rf .runtime
docker compose down -v
```

如果更新前可选 HTTPS Edge 正在运行，`rebuild.sh` 会检测并在 Core 重建完成后恢复 Edge。

因此以下数据保留：

```text
.runtime/workspace
.runtime/dsh-home
.runtime/auth
.runtime/edge
.env
```

如果 tracked 文件存在本地修改，`update.sh` 会拒绝 pull，要求先：

```bash
git commit
```

或：

```bash
git stash
```

或撤销修改，避免自动覆盖仓库代码。

---

## 10. 只重建，不 Git pull

```bash
./scripts/rebuild.sh
```

适用于：

- 修改 `.env` 中构建参数；
- 修改 Dockerfile；
- 想刷新 DSH `latest`；
- 本地已经手工 `git pull`。

同样保留 `.runtime`。

---

## 11. 停止

```bash
./scripts/stop.sh
```

相当于：

```bash
docker compose down --remove-orphans
```

不会删除持久化文件。

重新启动：

```bash
docker compose up -d
```

或：

```bash
./scripts/deploy.sh
```

---

## 12. 使用现有 Nginx / 1Panel / OpenResty

推荐 `.env`：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=13080
```

然后 HTTPS 反向代理：

```text
https://dsh.example.com
        ↓
http://127.0.0.1:13080
        ↓
Caddy Basic Auth
        ↓
DSH
```

仓库提供示例：

```text
examples/nginx.conf
```

关键点：

- WebSocket/Upgrade 头应正常转发；
- 建议关闭代理缓冲以改善流式响应；
- 增大读写超时，避免长 Agent 任务被代理提前断开；
- TLS 在外层反向代理终止；
- Basic Auth 仍由 Core Gateway 统一处理；Gateway 验证后会移除浏览器的 Basic `Authorization` 头，再把请求交给 DSH。

---

## 13. 可选：仓库自带 Caddy HTTPS Edge

如果没有其他反向代理，可启用可选 Edge。

### DNS

例如：

```text
dsh.example.com -> 服务器公网 IP
```

### `.env`

添加：

```dotenv
DSH_DOMAIN=dsh.example.com
ACME_EMAIL=admin@example.com

EDGE_BIND_ADDRESS=0.0.0.0
EDGE_HTTP_PORT=80
EDGE_HTTPS_PORT=443
EDGE_CADDY_VERSION=2.11.4
```

Core 建议保持：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

### 启动

先保证 Core 已部署：

```bash
./scripts/deploy.sh
```

再：

```bash
./scripts/edge-up.sh
```

访问：

```text
https://dsh.example.com
```

认证依然由 Core Gateway 负责。

停止 Edge，但保留 Core：

```bash
./scripts/edge-down.sh
```

注意 Edge 默认需要宿主机 80/443 可用；如果已有 Nginx/1Panel，就不要启用此 Edge。

---

## 14. 健康检查与诊断

### 状态

```bash
./scripts/check.sh
```

未携带认证信息访问 Gateway，预期 HTTP 状态是：

```text
401 Unauthorized
```

这反而说明认证层已经正常工作。

### 综合诊断

```bash
./scripts/doctor.sh
```

会检查：

- Docker；
- Docker Compose v2；
- Docker daemon；
- `.env`；
- 端口格式；
- 用户配置；
- Compose 配置；
- Caddy Gateway Caddyfile 能否被解析。

### 日志

全部：

```bash
docker compose logs -f --tail=200
```

DSH：

```bash
docker compose logs -f --tail=200 dsh
```

Gateway：

```bash
docker compose logs -f --tail=200 gateway
```

### 容器状态

```bash
docker compose ps
```

### 实际端口

```bash
ss -lntp | grep 3080
```

按实际 `DSH_PORT` 替换即可。

---

## 15. 常见问题

### 15.1 `no configuration file provided: not found`

说明你没有在仓库目录运行 Compose。

正确：

```bash
cd /path/to/dsh-docker
docker compose ps
```

或者显式：

```bash
docker compose -f /path/to/dsh-docker/compose.yaml ps
```

### 15.2 Gateway 返回 401

如果你直接 curl：

```bash
curl -i http://127.0.0.1:3080
```

得到：

```text
HTTP/1.1 401 Unauthorized
```

这是正常行为，表示 Basic Auth 正在拦截未登录请求。

浏览器访问会弹出用户名/密码输入框。

### 15.3 忘记密码

直接重置：

```bash
./scripts/create-user.sh
```

输入相同用户名和新密码。

### 15.4 Gateway 启动失败

先：

```bash
./scripts/doctor.sh
```

再：

```bash
docker compose logs --tail=200 gateway
```

检查：

```bash
cat .runtime/auth/users.caddy
```

应至少有一行：

```text
username $2a$...
```

### 15.5 DSH unhealthy

```bash
docker compose logs --tail=200 dsh
```

进入容器：

```bash
docker compose exec dsh bash
```

检查：

```bash
dsh --version
curl -i http://127.0.0.1:3080/
```

### 15.6 端口冲突

```bash
ss -lntp | grep ':3080'
```

然后修改：

```dotenv
DSH_PORT=13080
```

重新：

```bash
docker compose up -d --force-recreate gateway
```

### 15.7 Git 更新失败

`update.sh` 只允许 fast-forward，并拒绝覆盖 tracked 本地修改。

查看：

```bash
git status
```

处理本地修改后再：

```bash
./scripts/update.sh
```

---

## 16. 数据备份

核心数据都在：

```text
.runtime/
```

最重要：

```text
.runtime/workspace
.runtime/dsh-home
.runtime/auth/users.caddy
```

简单备份：

```bash
tar -czf dsh-runtime-backup.tar.gz .runtime .env
```

如果项目代码本身已经使用 Git 管理，仍建议单独备份 `.runtime/dsh-home` 和认证配置。

---

## 17. 完全删除

停止：

```bash
docker compose down --remove-orphans --rmi local
```

如果确认所有项目、会话和认证数据都不要了：

```bash
rm -rf .runtime
rm -f .env
```

这是不可逆操作。

---

## 18. 安全边界

当前设计刻意**不挂载**：

```text
/var/run/docker.sock
/
/root
/etc
宿主机 ~/.ssh
```

因此 DSH Agent 默认：

```text
可以：
- 操作 /workspace
- 执行 Node / Go / Rust / Python
- git clone / build / test
- 访问允许的网络

不能直接：
- 控制宿主机 Docker daemon
- 读取宿主机根文件系统
- 创建 privileged 容器
```

不要为了方便加入：

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

这会显著扩大容器对宿主机的控制权限。

另外：

- Basic Auth 不是 TLS；公网必须使用 HTTPS；
- `.runtime/auth/users.caddy` 虽然只有 Hash，也不应公开；
- `.env` 可能包含代理或未来加入的敏感配置，不应提交 Git；
- `DSH_PERMISSION_MODE=workspace-write` 意味着 Agent 可以修改整个 `/workspace`，重要代码应通过 Git commit/backup 管理。

---

## 19. 日常命令速查

首次部署：

```bash
./scripts/deploy.sh
```

创建/改密码：

```bash
./scripts/create-user.sh
```

用户列表：

```bash
./scripts/list-users.sh
```

删除用户：

```bash
./scripts/remove-user.sh
```

状态：

```bash
./scripts/check.sh
```

诊断：

```bash
./scripts/doctor.sh
```

进入 DSH：

```bash
docker compose exec dsh bash
```

更新代码 + 重建：

```bash
./scripts/update.sh
```

只重建：

```bash
./scripts/rebuild.sh
```

停止：

```bash
./scripts/stop.sh
```

启用 HTTPS Edge：

```bash
./scripts/edge-up.sh
```

停止 HTTPS Edge：

```bash
./scripts/edge-down.sh
```

---

## 20. 设计原则

这个仓库的核心约束是：

```text
Repository = Deployment Unit
```

也就是：

```text
git clone
   ↓
./scripts/deploy.sh
   ↓
运行
   ↓
./scripts/update.sh
   ↓
git pull
   ↓
删除旧容器 / 旧本地 DSH 镜像
   ↓
构建新镜像
   ↓
启动新容器
   ↓
继续使用原 .runtime
```

部署代码是可更新、可替换的；运行数据是持久化、独立保留的。

---

## 21. 上游参考

- DeepSeek Harness：`@deepseek-ai/dsh`
- Caddy Basic Auth 文档：`https://caddyserver.com/docs/caddyfile/directives/basic_auth`
- Caddy CLI / `hash-password`：`https://caddyserver.com/docs/command-line`
- Node.js：`https://nodejs.org/`
- Go：`https://go.dev/`
- Rust：`https://www.rust-lang.org/`
