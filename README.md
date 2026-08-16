# dsh-docker

DeepSeek Harness（DSH）的仓库式 Docker 开发环境。

目标：

- `git clone` 到任意目录后直接部署；
- 不依赖固定 `/var/lib/...` 路径；
- DSH、工作区和 DSH Home 均持久化；
- 浏览器访问前置用户名/密码认证；
- 支持 **localhost / SSH Tunnel**；
- 支持 **域名 + HTTP（No HTTPS）**；
- 支持 **域名 + HTTPS**；
- 支持现有 Nginx / 1Panel / OpenResty 作为外部反向代理；
- 支持 `git pull -> 删除旧容器/本地构建镜像 -> rebuild -> restart`；
- 不把 Docker Socket 暴露给 DSH 容器。

---

## 1. 架构

### 1.1 Core

```text
Browser
   │
   ▼
Caddy Basic Auth Gateway
   │
   ▼
DSH HTTP compatibility proxy
   │
   ▼
DeepSeek Harness Web
   │
   ▼
/workspace
```

Core 只有两个容器：

```text
dsh
gateway
```

`dsh` 容器内部：

```text
127.0.0.1:3079  DeepSeek Harness
        │
        ▼
0.0.0.0:3080    Node compatibility proxy
```

Gateway 只访问 `dsh:3080`。

### 1.2 为什么有 compatibility proxy

DSH Web 在本地通常通过 `localhost` 使用。远程使用纯 HTTP 域名时，浏览器可能没有 `crypto.randomUUID()`，从而导致工作区目录选择界面报错。

项目默认启用：

```dotenv
DSH_HTTP_COMPAT_SHIM=true
```

兼容代理只对 HTML 注入：

```text
/__dsh_http_compat.js
```

行为：

- 浏览器已经有原生 `crypto.randomUUID()`：什么也不做；
- 原生 API 缺失，但 `crypto.getRandomValues()` 可用：补充 UUID v4 兼容实现；
- JS/CSS/API/SSE/WebSocket：正常代理；
- 不修改 DSH npm 包源码；
- 可以通过 `.env` 完全关闭。

这主要用于 **domain-http**。

> 这不是把普通 HTTP 变成 HTTPS。它只解决当前 DSH Web 对 `crypto.randomUUID()` 的兼容问题。若未来 DSH 新增其他必须依赖 Secure Context 的浏览器 API，HTTPS 仍然是最完整的标准方案。

---

## 2. 三种访问模式

项目统一通过：

```dotenv
ACCESS_MODE=
```

选择模式。

### 2.1 `local`

默认：

```dotenv
ACCESS_MODE=local
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

入口：

```text
http://127.0.0.1:3080
```

适合：

- 本机服务器；
- SSH Tunnel；
- 1Panel / Nginx / OpenResty 外部反向代理；
- 不希望 Core 直接暴露公网。

### 2.2 `domain-http`

正式支持 **域名 + No HTTPS**。

典型配置：

```dotenv
ACCESS_MODE=domain-http
BIND_ADDRESS=0.0.0.0
DSH_PORT=80
DSH_DOMAIN=dsh.example.com
```

入口：

```text
http://dsh.example.com
```

要求：

1. 域名 A/AAAA 记录已经指向服务器；
2. 服务器安全组/防火墙允许对应 HTTP 端口；
3. 80 端口未被其他服务占用。

一条命令配置并部署：

```bash
./scripts/deploy.sh domain-http dsh.example.com
```

该命令会自动把：

```dotenv
ACCESS_MODE=domain-http
BIND_ADDRESS=0.0.0.0
DSH_PORT=80
DSH_DOMAIN=dsh.example.com
```

写入 `.env`。

> **安全边界**：No HTTPS 模式下 Basic Auth 凭据没有 TLS 链路保护。它适合可信局域网、VPN、内网或你明确接受风险的环境。技术上支持，不等于适合裸露公网长期使用。

### 2.3 `domain-https`

使用仓库自带 Caddy HTTPS Edge：

```dotenv
ACCESS_MODE=domain-https
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080

DSH_DOMAIN=dsh.example.com
ACME_EMAIL=admin@example.com

EDGE_BIND_ADDRESS=0.0.0.0
EDGE_HTTP_PORT=80
EDGE_HTTPS_PORT=443
```

入口：

```text
https://dsh.example.com
```

部署：

```bash
./scripts/deploy.sh domain-https dsh.example.com admin@example.com
```

结构：

```text
Internet
   │ 80 / 443
   ▼
Caddy HTTPS Edge
   │
   ▼
gateway:3080
   │ Basic Auth
   ▼
dsh:3080
```

---

## 3. 目录结构

```text
dsh-docker/
├── Dockerfile
├── compose.yaml
├── compose.edge.caddy.yaml
├── Caddyfile.gateway
├── Caddyfile.edge
│
├── dsh-web-proxy.mjs
├── dsh-http-compat.js
├── start-dsh-web.sh
│
├── .env.example
├── .dockerignore
├── .gitignore
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
    ├── set-mode.sh
    ├── rebuild.sh
    ├── update.sh
    ├── check.sh
    ├── doctor.sh
    ├── self-test.sh
    ├── stop.sh
    ├── cleanup-legacy.sh
    ├── edge-up.sh
    └── edge-down.sh
```

首次运行后：

```text
dsh-docker/
├── .env
└── .runtime/
    ├── workspace/
    │   └── projects/
    ├── dsh-home/
    ├── auth/
    │   └── users.caddy
    └── edge/
        └── caddy/
            ├── data/
            └── config/
```

`.env` 和 `.runtime/` 默认都不会进入 Git。

---

## 4. Workspace 映射

宿主机：

```text
<repo>/.runtime/workspace
```

映射到 DSH 容器：

```text
/workspace
```

推荐项目放在：

```text
<repo>/.runtime/workspace/projects/
```

容器内对应：

```text
/workspace/projects/
```

例如：

```text
/qwq/dsh-docker/.runtime/workspace/projects/my-api
```

在 DSH 中应选择：

```text
/workspace/projects/my-api
```

而不是宿主机的 `/qwq/...` 路径。

进入容器：

```bash
docker compose exec dsh bash
```

在容器内 Clone：

```bash
cd /workspace/projects
git clone https://github.com/example/project.git
```

---

## 5. 快速开始

### 5.1 Clone

```bash
git clone https://github.com/rin721/dsh-docker.git
cd dsh-docker
```

### 5.2 默认 local

```bash
./scripts/deploy.sh
```

第一次会自动：

```text
创建 .env
   ↓
初始化 .runtime
   ↓
拉取 Caddy Gateway
   ↓
创建 Basic Auth 用户
   ↓
验证 Caddy
   ↓
Build DSH
   ↓
启动
   ↓
自动状态检查
```

### 5.3 域名 + HTTP（No HTTPS）

```bash
./scripts/deploy.sh domain-http dsh.example.com
```

浏览器：

```text
http://dsh.example.com
```

### 5.4 域名 + HTTPS

```bash
./scripts/deploy.sh domain-https dsh.example.com admin@example.com
```

浏览器：

```text
https://dsh.example.com
```

---

## 6. `.env` 配置

### Runtime

```dotenv
RUNTIME_DIR=./.runtime
RUNTIME_UID=1000
RUNTIME_GID=1000
```

### Access

```dotenv
ACCESS_MODE=local
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080

# DSH_DOMAIN=dsh.example.com
# ACME_EMAIL=admin@example.com
```

### HTTPS Edge

```dotenv
EDGE_BIND_ADDRESS=0.0.0.0
EDGE_HTTP_PORT=80
EDGE_HTTPS_PORT=443
EDGE_CADDY_VERSION=2.11.4
```

### Authentication

```dotenv
AUTH_REALM="DeepSeek Harness"
AUTH_BCRYPT_COST=14
GATEWAY_CADDY_VERSION=2.11.4
```

### HTTP Compatibility

```dotenv
DSH_HTTP_COMPAT_SHIM=true
```

关闭：

```dotenv
DSH_HTTP_COMPAT_SHIM=false
```

然后：

```bash
./scripts/rebuild.sh
```

### DSH

```dotenv
DSH_VERSION=latest
DSH_PERMISSION_MODE=workspace-write
DSH_TELEMETRY_DISABLED=1
INSTALL_GO_DEV_TOOLS=true
```

### Toolchain

```dotenv
NODE_VERSION=24.18.0
GO_VERSION=1.26.5
RUST_TOOLCHAIN=stable
PNPM_VERSION=11.7.0
```

---

## 7. 登录用户

创建或修改用户：

```bash
./scripts/create-user.sh
```

查看：

```bash
./scripts/list-users.sh
```

删除：

```bash
./scripts/remove-user.sh
```

用户文件：

```text
.runtime/auth/users.caddy
```

示例：

```text
xiaolin $2a$14$...
admin   $2a$14$...
```

明文密码不会写入磁盘。

---

## 8. 切换访问模式

只修改配置，不立即部署：

### Local

```bash
./scripts/set-mode.sh local
```

### Domain HTTP

```bash
./scripts/set-mode.sh domain-http dsh.example.com
```

### Domain HTTPS

```bash
./scripts/set-mode.sh domain-https dsh.example.com admin@example.com
```

然后：

```bash
./scripts/deploy.sh
```

---

## 9. 使用已有 Nginx / 1Panel

如果服务器已有 Nginx/1Panel，不需要仓库自带 HTTPS Edge。

保持 Core：

```dotenv
ACCESS_MODE=local
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

### 9.1 外部反代：Domain + HTTP

```text
http://dsh.example.com
        ↓
Nginx / 1Panel :80
        ↓
127.0.0.1:3080
        ↓
Basic Auth Gateway
        ↓
DSH
```

`examples/nginx.conf` 已包含示例。

此时浏览器仍然是纯 HTTP，但 compatibility shim 仍由 DSH 容器提供。

### 9.2 外部反代：Domain + HTTPS

```text
https://dsh.example.com
        ↓
Nginx / 1Panel :443
        ↓
127.0.0.1:3080
```

证书完全由外部反向代理管理。

---

## 10. SSH Tunnel

服务器保持：

```dotenv
ACCESS_MODE=local
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

客户端：

```bash
ssh -L 3080:127.0.0.1:3080 root@SERVER_IP
```

浏览器：

```text
http://localhost:3080
```

---

## 11. 更新

仓库更新：

```bash
./scripts/update.sh
```

流程：

```text
确认 tracked 文件无未提交修改
      ↓
记录旧 DSH image
      ↓
git fetch --prune
      ↓
git pull --ff-only
      ↓
执行更新后的 rebuild.sh
      ↓
停止旧容器
      ↓
删除旧本地 DSH 镜像
      ↓
Pull 当前模式所需 Caddy 镜像
      ↓
验证 Caddy
      ↓
Build 新 DSH
      ↓
启动当前 ACCESS_MODE
```

不会删除：

```text
.env
.runtime/workspace
.runtime/dsh-home
.runtime/auth
.runtime/edge
```

---

## 12. 重建

不 Git Pull：

```bash
./scripts/rebuild.sh
```

适合：

- 修改 Dockerfile；
- 修改 DSH 版本；
- 修改 Node/Go/Rust 版本；
- 修改兼容代理；
- 修改 `DSH_HTTP_COMPAT_SHIM`。

---

## 13. 停止

```bash
./scripts/stop.sh
```

不会删除 `.runtime`。

不要为了普通停止执行：

```bash
rm -rf .runtime
```

---

## 14. 状态与诊断

状态：

```bash
./scripts/check.sh
```

完整诊断：

```bash
./scripts/doctor.sh
```

静态自检：

```bash
./scripts/self-test.sh
```

日志：

```bash
docker compose logs -f --tail=200
```

DSH：

```bash
docker compose logs -f dsh
```

Gateway：

```bash
docker compose logs -f gateway
```

---

## 15. `crypto.randomUUID is not a function`

如果远程纯 HTTP 页面曾出现：

```text
crypto.randomUUID is not a function
```

确认：

```dotenv
DSH_HTTP_COMPAT_SHIM=true
```

然后：

```bash
./scripts/rebuild.sh
```

兼容脚本只在原生 `crypto.randomUUID` 缺失时定义它。

可以查看 DSH 日志确认兼容代理：

```bash
docker compose logs dsh
```

启动时会出现类似：

```text
DSH compatibility proxy listening on 0.0.0.0:3080 -> 127.0.0.1:3079; HTTP compat shim=true
```

---

## 16. Domain HTTP 排障

### DNS

确认域名已经解析到服务器。

### 80 被占用

```bash
ss -lntp | grep ':80 '
```

如果 80 已由 Nginx/1Panel 占用，不要直接使用：

```text
ACCESS_MODE=domain-http
BIND_ADDRESS=0.0.0.0
DSH_PORT=80
```

改用第 9 节：

```text
Nginx/1Panel :80 -> 127.0.0.1:3080
```

### 防火墙

需要允许实际对外使用的 HTTP 端口。

---

## 17. Domain HTTPS 排障

确认：

```dotenv
DSH_DOMAIN=dsh.example.com
ACME_EMAIL=admin@example.com
EDGE_HTTP_PORT=80
EDGE_HTTPS_PORT=443
```

以及：

```bash
ss -lntp | grep -E ':(80|443) '
```

如果服务器已有 1Panel/Nginx 占用 80/443，建议不要启用仓库 Edge，直接采用外部反代模式。

---

## 18. 安全边界

默认不挂载：

```text
/var/run/docker.sock
```

因此 DSH 内的 Agent 不能直接控制宿主机 Docker。

这是有意设计。

如果未来需要 Agent 构建 Docker 镜像，优先考虑隔离的 BuildKit / rootless DinD，而不是直接暴露宿主机 Docker Socket。

### Basic Auth

- 密码明文不落盘；
- 使用 bcrypt Hash；
- HTTPS 下适合作为简单访问门禁；
- domain-http 下没有 TLS 链路保护，只适合可信环境。

---

## 19. 常用命令

```bash
# 首次 local
./scripts/deploy.sh

# Domain + HTTP
./scripts/deploy.sh domain-http dsh.example.com

# Domain + HTTPS
./scripts/deploy.sh domain-https dsh.example.com admin@example.com

# 创建/修改用户
./scripts/create-user.sh

# 查看用户
./scripts/list-users.sh

# 删除用户
./scripts/remove-user.sh

# 状态
./scripts/check.sh

# 诊断
./scripts/doctor.sh

# 静态自检
./scripts/self-test.sh

# 更新仓库并重建
./scripts/update.sh

# 仅重建
./scripts/rebuild.sh

# 停止
./scripts/stop.sh

# 进入 DSH
docker compose exec dsh bash
```

---

## 20. 数据备份

最重要：

```text
.env
.runtime/
```

例如：

```bash
tar -czf dsh-docker-backup.tar.gz .env .runtime
```

其中：

```text
.runtime/workspace   项目文件
.runtime/dsh-home    DSH 状态
.runtime/auth        登录用户
.runtime/edge        Caddy HTTPS 数据
```

---

## 21. 设计原则

这个仓库把：

```text
Repository = Deployment Unit
```

作为核心约束。

因此：

- clone 到哪里就从哪里运行；
- `.runtime` 默认跟随仓库；
- 不固定 `/var/lib/.dsh`；
- 删除容器不删除工作区；
- 更新代码与持久化数据分离；
- local / domain-http / domain-https 使用同一套 Core；
- HTTPS 是一种访问模式，不是 Core 的强制依赖。
