# dsh-docker

DeepSeek Harness（DSH）的 Docker 化开发环境。

仓库只负责：

```text
DSH
+ Basic Auth
+ /workspace 持久化
+ 动态反向代理 Host/Origin 兼容
+ 浏览器 HTTP 兼容
+ 快速镜像 Pull / 本地 Build fallback
```

域名、HTTPS、Nginx、1Panel、80/443 等公网入口由部署者自己管理。

---

## 1. 架构

```text
你的 Nginx / 1Panel / OpenResty
                │
                ▼
      http://127.0.0.1:3080
                │
                ▼
        Caddy Basic Auth
                │
                ▼
     DSH Dynamic Authority Bridge
                │
                ▼
       DeepSeek Harness Web
                │
                ▼
            /workspace
```

默认：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

反向代理上游：

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

如果某个非标准文件系统、ZIP 解压器或旧仓库历史意外丢失了 executable bit，也可以直接：

```bash
bash scripts/deploy.sh
```

`deploy.sh` 会自动修复当前工作区的 Shell 文件权限。

首次运行会自动：

```text
创建 .env
    ↓
修复 Shell 文件系统权限
    ↓
端口预检
    ↓
初始化 .runtime
    ↓
创建登录用户
    ↓
验证 Gateway
    ↓
优先 Pull DSH 预构建镜像
    ↓
必要时本地 Build
    ↓
启动
    ↓
状态检查
```

---

## 3. Workspace

宿主机：

```text
<repo>/.runtime/workspace
```

容器：

```text
/workspace
```

例如：

```text
/qwq/dsh-docker/.runtime/workspace/project-a
```

对应：

```text
/workspace/project-a
```

### 3.1 为什么目录选择器以前只看到 `go`

DSH 的 Browse Directory Picker 在没有指定路径时从运行用户的 `homedir()` 开始。

容器用户是：

```text
node
```

Home：

```text
/home/node
```

Go 的默认工作目录：

```text
/home/node/go
```

所以旧版本打开目录选择器会首先看到：

```text
go
```

而 `/workspace` 在 Home 之外。

### 3.2 v4 修复

启动时自动创建：

```text
/home/node/workspace -> /workspace
```

不会修改：

```text
HOME=/home/node
GOPATH=/home/node/go
CARGO_HOME=/home/node/.cargo
RUSTUP_HOME=/home/node/.rustup
DSH_HOME=/home/node/.dsh
```

因此目录选择器现在会看到：

```text
主目录

go
workspace
```

点击：

```text
workspace
```

实际进入：

```text
/workspace
```

也就是宿主机：

```text
.runtime/workspace
```

如果 `/home/node/workspace` 已经是真实目录，启动脚本不会覆盖它，只会打印警告。

---

## 4. Git executable bit

Shell 文件必须在 Git 仓库中记录为：

```text
100755
```

而不是：

```text
100644
```

否则 Linux 用户 `git clone` / `git pull` 后不能直接：

```bash
./scripts/deploy.sh
```

### 4.1 发布包

本项目发布包中的：

```text
start-dsh-web.sh
scripts/*.sh
```

都保存为：

```text
0755
```

### 4.2 仓库维护者提交到 GitHub

在提交发布版本前运行：

```bash
bash scripts/prepare-release.sh
```

它会执行：

```text
chmod 0755
        +
git update-index --chmod=+x
        +
self-test
```

然后：

```bash
git add -A
git commit -m "fix: preserve executable scripts and workspace entry"
git push
```

之后 GitHub 仓库会真正保存 executable bit。

未来 Linux 用户：

```bash
git clone ...
```

得到的脚本就是可执行的。

### 4.3 为什么只 `chmod +x` 还不够

Git 需要在 index 中记录 executable bit。

所以维护者发布时必须保证：

```bash
git ls-files -s scripts/deploy.sh
```

类似：

```text
100755 ...
```

项目的 CI：

```text
.github/workflows/validate-repository.yml
```

会自动检查全部 Shell 文件。

如果某个文件被提交成：

```text
100644
```

CI 直接失败。

### 4.4 运行时双保险

即使某个文件系统意外丢失了：

```text
start-dsh-web.sh
```

的 `+x`，Compose 也显式使用：

```yaml
command: ["bash", "/usr/local/bin/start-dsh-web"]
```

因此容器启动不再依赖宿主机 bind mount 的 execute bit。

Makefile 同样统一使用：

```text
bash scripts/*.sh
```

---

## 5. 动态域名 / Host

项目不要求：

```dotenv
DSH_DOMAIN=
DSH_EXTRA_TRUSTED_HOSTS=
```

外层可以随时换域名。

例如：

```text
https://dsh.example.com
https://dev.example.net
http://internal.example.local
```

不需要重建 DSH。

链路：

```text
Browser
Host: external.example.com
Origin: https://external.example.com
        ↓
Caddy Basic Auth
        ↓
Dynamic Authority Bridge
        │
        ├─ 校验 Host
        ├─ Origin 存在时校验 Origin.host == Host
        ├─ 拒绝 Sec-Fetch-Site: cross-site
        │
        ▼
内部规范化
Host: localhost:3079
Origin: http://localhost:3079
        ↓
DSH
```

因此 DSH 内部仍然只信任 loopback，不需要知道最终公网域名。

---

## 6. 远程 HTTP 浏览器兼容

默认：

```dotenv
DSH_HTTP_COMPAT_SHIM=true
```

用于兼容某些远程普通 HTTP Origin 下缺失的：

```js
crypto.randomUUID
```

它只在原生 API 不存在时补充实现。

HTTPS / localhost 中存在原生实现时不会覆盖。

---

## 7. 配置

`.env.example`：

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

---

## 8. DSH 镜像模式

### auto

```dotenv
DSH_IMAGE_MODE=auto
```

优先：

```text
docker pull ghcr.io/rin721/dsh-docker:latest
```

如果失败：

```text
复用本机已有镜像
```

仍没有才：

```text
Dockerfile 本地 Build
```

### pull

```dotenv
DSH_IMAGE_MODE=pull
```

只允许 Pull。

### build

```dotenv
DSH_IMAGE_MODE=build
```

强制本地 Build。

---

## 9. 本地 Build 缓存

Dockerfile 使用安全的 BuildKit cache：

```text
apt
npm
Go modules
Go build cache
```

Rustup 的：

```text
.rustup/tmp
.rustup/toolchains
```

不会做 cache mount，避免：

```text
Invalid cross-device link (os error 18)
```

---

## 10. 登录认证

创建或修改用户：

```bash
./scripts/create-user.sh
```

如果 executable bit 意外丢失：

```bash
bash scripts/create-user.sh
```

查看：

```bash
./scripts/list-users.sh
```

删除：

```bash
./scripts/remove-user.sh
```

认证数据：

```text
.runtime/auth/users.caddy
```

密码仅保存 bcrypt Hash。

---

## 11. 更新

```bash
./scripts/update.sh
```

即使刚 Pull 下来的新脚本 executable bit 异常，`update.sh` 在 Pull 后会先修复工作区权限，然后：

```text
exec bash scripts/rebuild.sh
```

因此不会因为新的 `rebuild.sh` 是 0644 而中断更新。

---

## 12. 状态

```bash
./scripts/check.sh
```

重点输出：

```text
Core listen
Proxy target
Auth users
Runtime
Workspace
Workspace UI
HTTP compat
```

正常：

```text
Workspace    : <repo>/.runtime/workspace <-> /workspace
Workspace UI : /home/node/workspace -> /workspace
```

---

## 13. 诊断

```bash
./scripts/doctor.sh
```

检查：

```text
Docker
Docker Compose
Core 配置
端口
认证用户
Shell execute bits
Workspace UI symlink
```

---

## 14. 发布前自检

```bash
bash scripts/prepare-release.sh
```

或者只检查：

```bash
bash scripts/self-test.sh
```

仓库模式检查：

```bash
git ls-files -s start-dsh-web.sh scripts/*.sh
```

这些文件都应该是：

```text
100755
```

---

## 15. 常用命令

```bash
# 部署
./scripts/deploy.sh

# executable bit 丢失时也能启动并自修复
bash scripts/deploy.sh

# 状态
./scripts/check.sh

# 诊断
./scripts/doctor.sh

# 更新
./scripts/update.sh

# 重建
./scripts/rebuild.sh

# 用户
./scripts/create-user.sh
./scripts/list-users.sh
./scripts/remove-user.sh

# 修复工作区权限
bash scripts/repair-permissions.sh

# 维护者：同时写入 Git index executable bit
bash scripts/repair-permissions.sh --git-index

# 发布准备
bash scripts/prepare-release.sh

# 进入 DSH
docker compose exec dsh bash
```

---

## 16. 数据目录

```text
.runtime/
├── workspace/
│   └── projects/
├── dsh-home/
└── auth/
    └── users.caddy
```

普通：

```text
deploy
update
rebuild
stop
```

都不会删除 `.runtime`。
