# dsh-docker

DeepSeek Harness（DSH）的 Docker 开发环境。

这个仓库只负责一件事：

> 在服务器上启动一个可持久化、带登录认证、可供你自己的 Nginx / 1Panel / OpenResty 反向代理的 DSH Core。

项目**不负责**：

- 域名；
- DNS；
- TLS / HTTPS；
- ACME；
- 80 / 443；
- Nginx 配置；
- 公网入口治理。

---

## 1. 最终架构

```text
你自己的 Nginx / 1Panel / OpenResty
                │
                │ reverse proxy
                ▼
        127.0.0.1:3080
                │
                ▼
      Caddy Basic Auth Gateway
                │
                ▼
       DSH compatibility proxy
                │
                ▼
        DeepSeek Harness Web
                │
                ▼
            /workspace
```

默认 Core 只监听：

```text
127.0.0.1:3080
```

部署完成后，你只需要让自己的反向代理把请求转发到：

```text
http://127.0.0.1:3080
```

---

## 2. 快速部署

```bash
git clone https://github.com/rin721/dsh-docker.git
cd dsh-docker

./scripts/deploy.sh
```

首次运行会自动：

```text
创建 .env
    ↓
端口预检
    ↓
创建 .runtime
    ↓
拉 Caddy Gateway
    ↓
创建登录用户
    ↓
验证 Gateway
    ↓
优先拉 GHCR 预构建 DSH
    ↓
拉不到才本地 Build
    ↓
启动
    ↓
状态检查
```

正常情况下不需要修改 Shell 脚本、Compose 或 Caddyfile。

---

## 3. 部署完成后

默认：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

因此你的反向代理上游始终可以写：

```text
http://127.0.0.1:3080
```

仓库不会帮你创建域名或配置 Nginx。

---

## 4. 配置

第一次 `deploy.sh` 会从 `.env.example` 创建：

```text
.env
```

### Core 监听

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

如果服务器 3080 已被占用，可以直接改：

```dotenv
DSH_PORT=13080
```

你的反向代理上游随之改为：

```text
http://127.0.0.1:13080
```

如果明确需要直接对其他机器暴露 Core：

```dotenv
BIND_ADDRESS=0.0.0.0
```

但如果本来就使用 Nginx / 1Panel，一般没必要。

---

## 5. 部署前端口预检

仓库会在任何耗时的镜像 Build 之前检查：

```text
DSH_PORT
```

如果已经被其他程序占用，会立即失败。

例如：

```text
端口预检失败：宿主机端口 3080 已被其他进程占用。
```

同时尽量打印：

```bash
ss -ltnp
```

结果。

因此不会再发生：

```text
等待几分钟 Build
        ↓
最后才发现端口冲突
```

---

## 6. 快速镜像交付

默认：

```dotenv
DSH_IMAGE_MODE=auto
DSH_IMAGE=ghcr.io/rin721/dsh-docker:latest
```

三种模式：

### auto

```dotenv
DSH_IMAGE_MODE=auto
```

行为：

```text
尝试 pull 预构建镜像
        │
   ┌────┴────┐
   │         │
 成功       失败
   │         │
直接启动   本地 Build
```

推荐默认使用。

### pull

```dotenv
DSH_IMAGE_MODE=pull
```

只允许预构建镜像。

拉取失败立即退出，不在用户服务器编译。

### build

```dotenv
DSH_IMAGE_MODE=build
```

强制使用本仓库 Dockerfile 构建。

---

## 7. GHCR

部署前可以检查预构建镜像是否已经可匿名拉取：

```bash
./scripts/check-image.sh
```

仓库包含：

```text
.github/workflows/publish-image.yml
```

用于构建：

```text
linux/amd64
linux/arm64
```

并发布：

```text
ghcr.io/rin721/dsh-docker:latest
```

正式给别人使用前，维护者应先让 GitHub Actions 成功发布镜像，并确保这个 GHCR Package 是 **Public**。

否则普通用户匿名 `docker pull` 会失败；`DSH_IMAGE_MODE=auto` 会进入本地 Build fallback，因此第一次部署仍然会比较慢。

如果你不希望正式用户现场编译，发布镜像后建议把默认配置改为：

```dotenv
DSH_IMAGE_MODE=pull
```

这样镜像不可用时会立即失败，而不是现场构建。

---

## 8. 本地 Build 为什么比以前快

Fallback Dockerfile 使用 BuildKit Cache Mount 缓存：

```text
apt
npm
Go module
Go build cache
```

Rustup **不对 `.rustup/tmp` / `.rustup/toolchains` 使用 cache mount**。Rustup 安装过程中会把临时文件移动到 toolchain 目录，把两者放到不同挂载文件系统会触发 Linux `EXDEV / Invalid cross-device link`。Rust 工具链本身依靠正常的 Docker RUN layer cache 复用。

因此：

- 第一次完整 Build 仍然可能慢；
- 后续 Build 会明显减少重复下载；
- `update.sh` 不会主动清空 BuildKit cache。

不要日常执行：

```bash
docker builder prune
docker system prune -a
```

否则会主动删除这些缓存。

---


## 8.1 ARM64 / Rust fallback 构建

项目支持 ARM64。Rustup 会根据容器架构自动选择类似：

```text
aarch64-unknown-linux-gnu
```

如果 GHCR 预构建镜像尚未发布，`DSH_IMAGE_MODE=auto` 会进入本地 fallback build。

本地 Rust 安装步骤不再把：

```text
/home/node/.rustup/tmp
/home/node/.rustup/toolchains
```

做成 BuildKit cache mount，避免：

```text
Invalid cross-device link (os error 18)
```

如果你刚刚在旧版 Dockerfile 上遇到过这个错误，更新仓库后直接重新：

```bash
./scripts/deploy.sh
```

即可。前面的 apt 等成功层仍可继续命中 Docker 普通 layer cache，不需要执行 `docker system prune`。

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

例如进入 DSH：

```bash
docker compose exec dsh bash
```

然后：

```bash
cd /workspace/projects
git clone https://github.com/example/project.git
```

DSH 中选择：

```text
/workspace/projects/project
```

不要选择宿主机的：

```text
/qwq/dsh-docker/.runtime/...
```

DSH 实际运行在容器内。

---

## 10. 远程 HTTP 浏览器兼容

DSH 通常在 `localhost` 使用。

如果你自己的 Nginx 最终提供的是普通 HTTP 域名，浏览器可能缺少：

```js
crypto.randomUUID()
```

项目默认：

```dotenv
DSH_HTTP_COMPAT_SHIM=true
```

DSH 容器内包含：

```text
dsh-web-proxy.mjs
dsh-http-compat.js
```

兼容层只在浏览器没有原生 `crypto.randomUUID` 时补充 UUID v4 实现。

如果你的外层是 HTTPS，浏览器已有原生实现时它不会覆盖。

关闭：

```dotenv
DSH_HTTP_COMPAT_SHIM=false
```

然后：

```bash
./scripts/rebuild.sh
```

---

## 11. 登录认证

Gateway 使用 HTTP Basic Auth。

首次：

```bash
./scripts/deploy.sh
```

会提示：

```text
用户名:
密码:
再次输入密码:
```

密码以 bcrypt Hash 保存：

```text
.runtime/auth/users.caddy
```

明文密码不落盘。

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

---

## 12. 持久化目录

```text
.runtime/
├── workspace/
│   └── projects/
├── dsh-home/
└── auth/
    └── users.caddy
```

其中：

```text
workspace   项目
dsh-home    DSH 状态
auth        登录用户
```

普通升级不会删除这些数据。

---

## 13. 更新

```bash
./scripts/update.sh
```

流程：

```text
git fetch
    ↓
git pull --ff-only
    ↓
端口预检
    ↓
更新 Gateway
    ↓
pull / build DSH
    ↓
docker compose up -d
```

不会删除：

```text
.env
.runtime/
```

---

## 14. 重建

```bash
./scripts/rebuild.sh
```

强制本地 Build：

```bash
DSH_IMAGE_MODE=build ./scripts/rebuild.sh
```

---

## 15. 状态

```bash
./scripts/check.sh
```

会输出：

```text
Core listen
Proxy target
Auth users
Runtime
Workspace
HTTP compat
```

其中最关键的是：

```text
Proxy target : http://127.0.0.1:3080
```

这就是你自己的 Nginx 上游。

---

## 16. 诊断

```bash
./scripts/doctor.sh
```

检查：

```text
Docker
Docker Compose
.env
Core 配置
端口冲突
Basic Auth
Compose
```

---

## 17. 停止

```bash
./scripts/stop.sh
```

不会删除 `.runtime`。

---

## 18. 日志

全部：

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

## 19. 项目目录

```text
dsh-docker/
├── Dockerfile
├── compose.yaml
├── compose.build.yaml
├── Caddyfile.gateway
│
├── dsh-web-proxy.mjs
├── dsh-http-compat.js
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
├── .github/
│   └── workflows/
│       └── publish-image.yml
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
    ├── self-test.sh
    ├── stop.sh
    └── cleanup-legacy.sh
```

---

## 20. 职责边界

### dsh-docker 负责

```text
DSH
开发环境
Workspace
持久化
Basic Auth
Core Gateway
HTTP browser compatibility
镜像 Build / Pull
生命周期脚本
```

### dsh-docker 不负责

```text
域名
DNS
Nginx
1Panel
OpenResty
HTTPS
证书
ACME
80/443
Cloudflare
公网入口
```

这部分完全交给部署者自己的基础设施。

---

## 21. 最简使用流程

```bash
git clone https://github.com/rin721/dsh-docker.git

cd dsh-docker

./scripts/deploy.sh
```

部署成功后记住：

```text
http://127.0.0.1:3080
```

然后去你自己的 Nginx / 1Panel 配反向代理即可。
