# DeepSeek Harness Docker + Tinyauth 登录层

一个可直接部署的 DeepSeek Harness 开发容器，前置 Caddy HTTPS 与 Tinyauth 用户名/密码登录层。

## 架构

```text
Internet
   |
   | HTTPS :443
   v
 Caddy
   |-- auth.example.com --> Tinyauth 登录页面
   |
   `-- dsh.example.com
          |
          | forward_auth
          v
       Tinyauth
          |
          | 登录通过
          v
         DSH :3080
          |
          v
 /var/lib/.dsh/data
```

公网只发布 Caddy 的 `80/443`。`DSH:3080` 与 `Tinyauth:3000` 都只存在于 Docker 网络中。

## 开发环境

DSH 镜像包含：

- Node.js 24.18.0、npm、pnpm、TypeScript、tsx
- Go 1.26.5、gopls、goimports、Delve、staticcheck、Task
- Rust stable、cargo、rustfmt、clippy、rust-analyzer
- Python 3、pip、pipx、venv
- Git、Git LFS、OpenSSH、curl、wget、jq、ripgrep、fd、fzf
- gcc/g++、make、CMake、Ninja、Clang、GDB、LLDB、strace
- SQLite、OpenSSL、protobuf、rsync、tmux、shellcheck、网络排查工具

## 持久化目录

```text
/var/lib/.dsh/data          -> /workspace
/var/lib/.dsh/home          -> /home/node/.dsh
/var/lib/.dsh/tinyauth      -> Tinyauth SQLite/运行数据
/var/lib/.dsh/caddy/data    -> Caddy TLS/证书数据
/var/lib/.dsh/caddy/config  -> Caddy 运行配置数据
```

其中 `/var/lib/.dsh/data` 就是 DSH 的容器工作区。

## 1. DNS

准备两个同父域子域：

```text
dsh.example.com  -> 服务器公网 IP
auth.example.com -> 服务器公网 IP
```

推荐同父域，是因为 Tinyauth 使用父域 Cookie 在登录域与受保护应用域之间共享认证状态。

服务器防火墙需要允许 TCP `80/443`；如果要用 HTTP/3，可同时允许 UDP `443`。

## 2. 配置环境变量

```bash
cp .env.example .env
nano .env
```

例如：

```dotenv
DSH_DOMAIN=dsh.example.com
AUTH_DOMAIN=auth.example.com
ACME_EMAIL=admin@example.com
DSH_VERSION=latest
TINYAUTH_SESSION_EXPIRY=86400
```

## 3. 创建登录用户

```bash
chmod +x scripts/*.sh start-dsh-web.sh
./scripts/create-user.sh
```

脚本会调用 Tinyauth 官方 CLI，通过 bcrypt 生成密码 Hash，并写入：

```text
auth/tinyauth.yml
```

不会把明文密码写入磁盘。

再次运行脚本可以增加用户；使用相同用户名会替换该账号密码。

## 4. 一键部署

```bash
./scripts/deploy.sh
```

脚本会：

1. 创建 `/var/lib/.dsh` 持久化目录；
2. 修正 DSH 工作目录权限；
3. 校验 `.env` 和 Tinyauth 用户；
4. 校验 Compose；
5. 拉取 Caddy/Tinyauth；
6. 构建 DSH 开发镜像；
7. 启动完整服务。

## 5. 查看状态

```bash
./scripts/check.sh
```

或：

```bash
docker compose ps
docker compose logs -f --tail=200
```

正常情况下只有 Caddy 发布宿主机端口：

```text
80/tcp
443/tcp
443/udp
```

不应看到：

```text
0.0.0.0:3080
0.0.0.0:3000
```

## 6. 访问

打开：

```text
https://dsh.example.com
```

流程：

```text
DSH 域名
  -> Tinyauth 检查 Session
  -> 未登录则跳转 auth.example.com
  -> 用户名/密码
  -> 登录成功
  -> 返回 DSH
```

用户端只需要浏览器，不需要 SSH、VPN、Tailscale 或其他客户端。

## 7. 进入开发容器

```bash
docker compose exec dsh bash
```

默认目录：

```text
/workspace
```

验证开发工具：

```bash
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

## 8. 放入项目

宿主机：

```bash
cd /var/lib/.dsh/data
git clone https://github.com/your/repo.git
```

容器里自动对应：

```text
/workspace/repo
```

## 9. 停止

```bash
./scripts/stop.sh
```

这不会删除 `/var/lib/.dsh` 的持久化数据。

## 安全边界

- 不向公网发布 DSH `3080`。
- 不向公网发布 Tinyauth `3000`。
- Caddy 自动处理 HTTPS 证书申请和续期。
- DSH 只有通过 Tinyauth Session 后才由 Caddy 反向代理。
- Tinyauth 密码使用 bcrypt Hash。
- `auth/tinyauth.yml` 与 `.env` 已加入 `.gitignore`，不要提交真实凭据配置。
- 不挂载 `/var/run/docker.sock`，避免 DSH 获得宿主机 Docker/root 等价控制能力。

## 版本

当前包固定：

```text
Caddy       2.11.4
Tinyauth    5.1.3
Node.js     24.18.0
Go          1.26.5
Rust        stable
DSH         latest（可通过 .env 固定）
```

DeepSeek Harness 目前仍处于 developer preview；如果用于长期运行，建议把 `DSH_VERSION` 固定到你验证过的版本。
