# dsh-docker

DeepSeek Harness（DSH）的 Docker 化浏览器开发环境。

这个仓库的重点不是“能构建”，而是**普通用户 clone 后能快速部署**：

```bash
git clone https://github.com/rin721/dsh-docker.git
cd dsh-docker
./scripts/deploy.sh
```

支持：

- `local`
- `domain-http`（域名 + No HTTPS）
- `domain-https`
- Basic Auth
- 远程 HTTP `crypto.randomUUID` 兼容层
- 仓库内 `.runtime` 持久化
- GHCR 预构建镜像
- 本地构建自动回退
- 部署前端口冲突预检
- Git Pull + 滚动重建

---

## 1. 为什么默认不再在服务器 Build

完整 DSH 开发镜像包含：

```text
Node
Go
Rust
Python
C/C++ build toolchain
DeepSeek Harness
gopls / goimports / dlv / staticcheck / task
```

第一次在服务器构建可能需要数分钟。

因此正式发行模式是：

```text
GitHub Actions
      ↓ Build once
GHCR prebuilt image
      ↓ docker pull
用户服务器
```

默认：

```dotenv
DSH_IMAGE_MODE=auto
DSH_IMAGE=ghcr.io/rin721/dsh-docker:latest
```

行为：

```text
docker pull 成功
    ↓
直接启动，不本地编译

docker pull 失败
    ↓
自动回退 Dockerfile 本地构建
```

如果仓库面向公众，请仓库维护者在 GitHub Packages 中把 GHCR package 的 Visibility 设置为 **Public**。

---

## 2. Dockerfile 本地构建也做了缓存

Fallback build 使用 BuildKit cache mounts 缓存：

```text
apt
npm
Go module/build cache
Rustup downloads
```

因此第一次本地构建仍然可能慢，但后续重建不会无意义地重新下载全部依赖。

不要在日常更新流程里执行：

```bash
docker builder prune
docker system prune -a
```

否则会主动清掉这些缓存。

---

## 3. 部署顺序

`deploy.sh` 现在严格按照：

```text
读取配置
    ↓
验证访问模式
    ↓
检查宿主机端口冲突       ← 第一时间失败
    ↓
创建 .runtime
    ↓
拉 Caddy
    ↓
创建认证用户
    ↓
验证 Caddy
    ↓
pull 预构建 DSH
    ↓
pull 失败才 local build
    ↓
启动
```

所以像：

```text
listen tcp4 0.0.0.0:80: bind: address already in use
```

这种问题不会再等几分钟 Build 完才出现。

---

## 4. 三种访问模式

### local

```bash
./scripts/deploy.sh
```

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

- SSH Tunnel
- Nginx/1Panel 反代
- 不直接暴露公网

---

### domain-http：域名 + No HTTPS

默认使用 **3080**，不再强抢 80：

```bash
./scripts/deploy.sh domain-http dsh.example.com
```

自动配置：

```dotenv
ACCESS_MODE=domain-http
BIND_ADDRESS=0.0.0.0
DSH_PORT=3080
DSH_DOMAIN=dsh.example.com
```

入口：

```text
http://dsh.example.com:3080
```

这是为了避免最常见的情况：

```text
80 已经被 Nginx / 1Panel / Apache / Caddy 占用
```

如果你确定 80 空闲，并且就是要：

```text
http://dsh.example.com
```

显式指定：

```bash
./scripts/deploy.sh domain-http dsh.example.com 80
```

脚本会**先检查 80 是否空闲**。

如果已经占用，会立即失败并显示监听进程，不会开始构建镜像。

---

### 已有 Nginx/1Panel，占用了 80

这是最推荐的 No HTTPS 域名方案。

项目保持：

```bash
./scripts/deploy.sh local
```

Core：

```text
127.0.0.1:3080
```

已有 Nginx/1Panel：

```text
http://dsh.example.com:80
          ↓
http://127.0.0.1:3080
```

这样既是：

```text
域名 + No HTTPS
```

又不会和服务器现有 80 端口服务冲突。

`examples/nginx.conf` 中有示例。

---

### domain-https

```bash
./scripts/deploy.sh \
  domain-https \
  dsh.example.com \
  admin@example.com
```

仓库自带 Caddy Edge 负责：

```text
80
443
TLS certificate
```

在执行任何耗时操作之前会先检查：

```text
3080
80
443
```

是否可用。

如果服务器已有 Nginx/1Panel 占用 80/443，应该继续使用 `local` Core，然后让现有反向代理管理 HTTPS。

---

## 5. 当前报错是什么意思

如果看到：

```text
failed to bind port 0.0.0.0:80/tcp
listen tcp4 0.0.0.0:80: bind: address already in use
```

不是 DSH 错误。

表示宿主机已经有程序监听：

```text
0.0.0.0:80
```

查看：

```bash
ss -ltnp 'sport = :80'
```

通常是：

```text
nginx
openresty
1Panel
apache
另一个 Docker container
```

新版仓库会在 Build **之前**检测到。

---

## 6. 镜像交付模式

### auto

推荐：

```dotenv
DSH_IMAGE_MODE=auto
```

```text
prebuilt pull
     ↓ failed
local build fallback
```

### pull

生产/正式发布推荐：

```dotenv
DSH_IMAGE_MODE=pull
```

预构建镜像不存在就立即失败：

```text
绝不在用户服务器现场编译
```

### build

开发仓库本身时：

```dotenv
DSH_IMAGE_MODE=build
```

或者：

```bash
make build
```

---

## 7. GHCR 发布

仓库已经包含：

```text
.github/workflows/publish-image.yml
```

触发：

- push 到 `main` 且 Docker 构建文件发生变化
- `v*` tag
- 手动 Workflow Dispatch
- 每周一次自动刷新

发布：

```text
ghcr.io/rin721/dsh-docker:latest
```

支持：

```text
linux/amd64
linux/arm64
```

### 第一次发布后

GitHub Container Registry 的 package 可能默认不是 Public。

仓库维护者需要在 GitHub Package 设置中将：

```text
ghcr.io/rin721/dsh-docker
```

设为：

```text
Public
```

这样别人才能：

```bash
docker pull ghcr.io/rin721/dsh-docker:latest
```

而无需登录 GitHub。

---

## 8. 远程 HTTP 工作区兼容

DSH 本身通常在 localhost 使用。

远程：

```text
http://dsh.example.com
```

浏览器可能没有：

```js
crypto.randomUUID
```

项目中的 DSH 容器因此包含：

```text
dsh-web-proxy.mjs
dsh-http-compat.js
```

默认：

```dotenv
DSH_HTTP_COMPAT_SHIM=true
```

只在浏览器缺少原生 `crypto.randomUUID()` 时补兼容实现。

HTTPS/localhost 有原生实现时不覆盖。

---

## 9. Workspace

宿主机：

```text
<repo>/.runtime/workspace
```

容器：

```text
/workspace
```

推荐：

```text
<repo>/.runtime/workspace/projects
        ↕
/workspace/projects
```

例如：

```bash
docker compose exec dsh bash

cd /workspace/projects
git clone https://github.com/example/my-project.git
```

DSH 中选择：

```text
/workspace/projects/my-project
```

---

## 10. 完整配置

### Runtime

```dotenv
RUNTIME_DIR=./.runtime
RUNTIME_UID=1000
RUNTIME_GID=1000
```

### Image

```dotenv
DSH_IMAGE_MODE=auto
DSH_IMAGE=ghcr.io/rin721/dsh-docker:latest
```

### Access

```dotenv
ACCESS_MODE=local
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080

# DSH_DOMAIN=dsh.example.com
# ACME_EMAIL=admin@example.com
```

### Edge

```dotenv
EDGE_BIND_ADDRESS=0.0.0.0
EDGE_HTTP_PORT=80
EDGE_HTTPS_PORT=443
EDGE_CADDY_VERSION=2.11.4
```

### Auth

```dotenv
AUTH_REALM="DeepSeek Harness"
AUTH_BCRYPT_COST=14
GATEWAY_CADDY_VERSION=2.11.4
```

### DSH

```dotenv
DSH_HTTP_COMPAT_SHIM=true
DSH_VERSION=latest
DSH_PERMISSION_MODE=workspace-write
DSH_TELEMETRY_DISABLED=1
```

### Local-build toolchain

```dotenv
INSTALL_GO_DEV_TOOLS=true

NODE_VERSION=24.18.0
GO_VERSION=1.26.5
RUST_TOOLCHAIN=stable
PNPM_VERSION=11.7.0
```

---

## 11. 用户管理

创建/修改：

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

认证文件：

```text
.runtime/auth/users.caddy
```

明文密码不落盘。

---

## 12. 更新

```bash
./scripts/update.sh
```

新版更新流程不再为了“清理”而提前摧毁 Build cache。

流程：

```text
git fetch
git pull --ff-only
     ↓
端口预检
     ↓
pull / build 新 DSH
     ↓
验证
     ↓
docker compose up
     ↓
成功后 prune dangling images
```

`.runtime` 永远保留。

---

## 13. 重建

```bash
./scripts/rebuild.sh
```

如果：

```dotenv
DSH_IMAGE_MODE=auto
```

会优先更新预构建镜像。

强制本地：

```bash
DSH_IMAGE_MODE=build ./scripts/rebuild.sh
```

---

## 14. 状态与诊断

```bash
./scripts/check.sh
```

```bash
./scripts/doctor.sh
```

```bash
./scripts/self-test.sh
```

日志：

```bash
docker compose logs -f --tail=200
```

---

## 15. 当前服务器已有 80 端口服务时

你的情况应优先选择下面两种之一。

### 方案 A：直接使用 3080

```bash
./scripts/deploy.sh domain-http dsh.example.com 3080
```

访问：

```text
http://dsh.example.com:3080
```

### 方案 B：让现有 80 端口 Nginx/1Panel 反代

```bash
./scripts/deploy.sh local
```

反代：

```text
dsh.example.com:80
    ↓
127.0.0.1:3080
```

这是已有 Web Server 的服务器上更合理的结构。

---

## 16. 安全说明

`domain-http` 是受支持模式，但：

```text
HTTP Basic Auth + HTTP
```

没有 TLS 传输保护。

只建议：

- 局域网
- VPN
- 内网
- 可信网络
- 明确接受风险的临时环境

公网正式部署仍优先：

```text
domain-https
```

或：

```text
现有 Nginx/1Panel HTTPS -> local Core
```

---

## 17. 常用命令

```bash
# local
./scripts/deploy.sh

# domain + HTTP :3080
./scripts/deploy.sh domain-http dsh.example.com

# domain + HTTP :80
./scripts/deploy.sh domain-http dsh.example.com 80

# domain + HTTPS
./scripts/deploy.sh domain-https dsh.example.com admin@example.com

# 更新
./scripts/update.sh

# 重建
./scripts/rebuild.sh

# 强制本地构建
DSH_IMAGE_MODE=build ./scripts/rebuild.sh

# 状态
./scripts/check.sh

# 诊断
./scripts/doctor.sh

# 进入 DSH
docker compose exec dsh bash
```

---

## 18. 数据目录

```text
.runtime/
├── workspace/
│   └── projects/
├── dsh-home/
├── auth/
│   └── users.caddy
└── edge/
```

不要执行：

```bash
rm -rf .runtime
```

除非明确要删除所有持久化数据。
