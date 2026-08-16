# dsh-docker

DeepSeek Harness（DSH）的 Docker Core 运行环境。

仓库只负责：

```text
DSH + 开发工具链 + Workspace + Basic Auth + Core Gateway
```

域名、DNS、HTTP/HTTPS、证书和公网入口由部署者自己的 Nginx / 1Panel / OpenResty 负责。

---

## 1. 架构

```text
你的 Nginx / 1Panel / OpenResty
            │
            │ reverse proxy
            ▼
    127.0.0.1:<DSH_PORT>
            │
            ▼
   Caddy Basic Auth Gateway
            │
            ▼
   Dynamic Authority Bridge
   + HTTP compatibility proxy
            │
            ▼
      DeepSeek Harness
            │
            ▼
        /workspace
```

默认：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

因此反向代理上游默认是：

```text
http://127.0.0.1:3080
```

---

## 2. 动态域名：不需要配置 DSH_DOMAIN / trusted-host

用户可以在外层使用任意域名：

```text
https://a.example.com
https://b.example.net
http://dev.internal
```

**dsh-docker 不需要知道这些域名。**

不需要：

```dotenv
DSH_DOMAIN=...
DSH_EXTRA_TRUSTED_HOSTS=...
ACME_EMAIL=...
```

也不需要因为换域名重建 DSH。

### 工作原理

浏览器正常请求：

```http
Host: a.example.com
Origin: https://a.example.com
```

Core 中的 Dynamic Authority Bridge 先验证：

```text
Host 存在且是合法 authority
Sec-Fetch-Site != cross-site
Origin 存在时 Origin.host == Host
```

验证通过后才在**内部**规范化为：

```http
Host: localhost:3079
Origin: http://localhost:3079
```

于是 DSH 永远只面对 loopback authority，不需要维护每个用户的域名白名单。

如果外部请求本身是跨 Origin 的，Core Proxy 会在到达 DSH 之前直接返回：

```text
HTTP 403
```

### 反向代理唯一必要契约

你的反向代理必须保留原始 Host：

```nginx
proxy_set_header Host $host;
```

建议同时保留：

```nginx
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Real-IP $remote_addr;
```

项目不管理你的域名或 TLS，只要求上游不要把 Host 改成 `127.0.0.1:<port>`。

---

## 3. 快速部署

```bash
git clone https://github.com/rin721/dsh-docker.git
cd dsh-docker

./scripts/deploy.sh
```

首次自动执行：

```text
创建 .env
  ↓
端口预检
  ↓
初始化 .runtime
  ↓
拉取 Caddy Gateway
  ↓
创建 Basic Auth 用户
  ↓
验证 Gateway
  ↓
优先拉 GHCR 预构建 DSH 镜像
  ↓
拉不到才本地 Build
  ↓
启动服务
  ↓
状态检查
```

---

## 4. 配置

`.env`：

```dotenv
RUNTIME_DIR=./.runtime
RUNTIME_UID=1000
RUNTIME_GID=1000

BIND_ADDRESS=127.0.0.1
DSH_PORT=3080

DSH_IMAGE_MODE=auto
DSH_IMAGE=ghcr.io/rin721/dsh-docker:latest

AUTH_REALM="DeepSeek Harness"
AUTH_BCRYPT_COST=14
GATEWAY_CADDY_VERSION=2.11.4

DSH_HTTP_COMPAT_SHIM=true

DSH_VERSION=latest
DSH_PERMISSION_MODE=workspace-write
DSH_TELEMETRY_DISABLED=1
INSTALL_GO_DEV_TOOLS=true

NODE_VERSION=24.18.0
GO_VERSION=1.26.5
RUST_TOOLCHAIN=stable
PNPM_VERSION=11.7.0
```

没有任何域名配置。

---

## 5. 访问端口

如果你希望上游使用：

```text
127.0.0.1:10080
```

修改：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=10080
```

然后：

```bash
docker compose up -d --force-recreate gateway
```

检查：

```bash
curl -I http://127.0.0.1:10080
```

未带密码正常应返回：

```text
HTTP/1.1 401 Unauthorized
```

带密码：

```bash
curl -u 'username:password' -I http://127.0.0.1:10080
```

正常应返回 `200` 或 DSH 的有效响应。

---

## 6. Workspace

宿主机：

```text
<repo>/.runtime/workspace
```

容器：

```text
/workspace
```

推荐项目放到：

```text
<repo>/.runtime/workspace/projects
```

对应容器：

```text
/workspace/projects
```

例如：

```bash
docker compose exec dsh bash
cd /workspace/projects
git clone https://github.com/example/project.git
```

DSH 工作区选择器里选择：

```text
/workspace/projects/project
```

---

## 7. 为什么之前 `/api/host.listDirectory` 会 HTTP 403

错误形态：

```text
transport failure for /api/host.listDirectory: HTTP 403
```

旧版代理做了：

```text
Host   -> localhost
Origin -> 保留外部域名
```

最终 DSH 看到：

```text
Host:   localhost:3079
Origin: https://external-domain
```

Host/Origin 不一致，因此拒绝 API。

当前版会先验证外部 Host/Origin，再同时规范化 Host 和 Origin，因此不需要静态 trusted-host 域名。

---

## 8. HTTP compatibility shim

旧版 DSH Web 在普通远程 HTTP origin 下可能直接调用：

```js
crypto.randomUUID()
```

项目保留兼容层：

```dotenv
DSH_HTTP_COMPAT_SHIM=true
```

仅当浏览器缺少原生 `crypto.randomUUID()` 时补兼容实现。

较新的 DSH 已经有自己的 `crypto.getRandomValues()` UUID fallback；保留这一层主要是兼容旧镜像/旧版本。

关闭：

```dotenv
DSH_HTTP_COMPAT_SHIM=false
```

---

## 9. Basic Auth

首次 `deploy.sh` 自动提示创建用户。

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

## 10. 镜像交付

默认：

```dotenv
DSH_IMAGE_MODE=auto
```

行为：

```text
pull ghcr.io/rin721/dsh-docker:latest
       │
   ┌───┴───────────────┐
 成功                 失败
   │                    │
直接启动        本机是否已有同名镜像
                         │
                    ┌────┴────┐
                   有         无
                    │          │
                 直接复用    本地 Build
```

因此已经成功构建过一次的服务器，不会因为 GHCR 暂时不可用就每次重新编译 Rust/Go/Node。

正式公开仓库建议先通过 GitHub Actions 发布 GHCR 镜像并设置为 Public。

检查：

```bash
./scripts/check-image.sh
```

如果你要求正式用户绝不现场 Build：

```dotenv
DSH_IMAGE_MODE=pull
```

---

## 11. 本地 Build 性能

Fallback Dockerfile 缓存：

```text
apt
npm
Go module
Go build cache
```

Rustup 的 `tmp/toolchains` 不使用 cache mount，避免 `Invalid cross-device link`。

此外，当前 Dockerfile 把：

```text
start-dsh-web.sh
dsh-web-proxy.mjs
dsh-http-compat.js
```

放到 Rust/npm/Go 安装层**之后**再 COPY。

更重要的是，正常 Compose 部署还会把这三个仓库文件**只读 bind mount** 到容器中，覆盖镜像内副本。

因此：

```text
修改动态 Host/Origin 代理
修改 HTTP compatibility shim
修改 DSH 启动包装脚本
```

只需要重新创建容器，不需要重新编译 Rust/npm/Go 工具链。

例如：

```bash
docker compose up -d --force-recreate dsh gateway
```

---

## 11.1 已经构建成功过旧版镜像的服务器

如果服务器上已经存在：

```text
ghcr.io/rin721/dsh-docker:latest
```

那么更新到当前仓库后，即使 GHCR 暂时 pull 不到，`DSH_IMAGE_MODE=auto` 也会直接复用本机镜像。

动态 Host/Origin 修复来自仓库 bind mount，因此不需要为了这个修复重新跑几百秒 Rust/Go/npm Build。

直接：

```bash
./scripts/deploy.sh
```

即可。

## 12. 更新

```bash
./scripts/update.sh
```

不会删除：

```text
.env
.runtime/
```

---

## 13. 重建

```bash
./scripts/rebuild.sh
```

强制本地构建：

```bash
DSH_IMAGE_MODE=build ./scripts/rebuild.sh
```

---

## 14. 检查与诊断

状态：

```bash
./scripts/check.sh
```

诊断：

```bash
./scripts/doctor.sh
```

仓库静态自检：

```bash
./scripts/self-test.sh
```

---

## 15. 日志

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

动态代理启动日志类似：

```text
DSH compatibility proxy listening on 0.0.0.0:3080 -> 127.0.0.1:3079; authority=dynamic
```

---

## 16. 持久化

```text
.runtime/
├── workspace/
│   └── projects/
├── dsh-home/
└── auth/
    └── users.caddy
```

普通更新、重建、删除容器都不应该删除 `.runtime`。

---

## 17. Core-only 职责边界

### 本仓库负责

```text
DeepSeek Harness
开发工具链
Workspace
持久化
Basic Auth
Core Gateway
动态 Host/Origin trust bridge
旧版 HTTP 浏览器兼容
镜像 Pull/Build
部署/更新/诊断脚本
```

### 本仓库不负责

```text
域名
DNS
Nginx
1Panel
OpenResty
TLS/HTTPS
证书
ACME
Cloudflare
80/443
公网入口
```

部署完成后，你只需要拿：

```text
http://127.0.0.1:<DSH_PORT>
```

去配置自己的反向代理。
