# dsh-docker

DeepSeek Harness（DSH）的 Docker 化长期开发环境。

## 持久化

默认所有长期状态都在仓库的：

```text
.runtime/
```

```text
.runtime/
├── workspace/                -> /workspace
├── dsh-home/                 -> /home/node/.dsh
├── home/                     -> /home/node/.persist
│   ├── ssh/                  -> ~/.ssh
│   ├── gnupg/                -> ~/.gnupg
│   ├── aws/                  -> ~/.aws
│   ├── kube/                 -> ~/.kube
│   ├── docker/               -> ~/.docker
│   ├── config/               -> ~/.config
│   ├── local/share/          -> ~/.local/share
│   ├── local/state/          -> ~/.local/state
│   ├── git/config            -> ~/.gitconfig
│   ├── git/credentials       -> ~/.git-credentials
│   ├── shell/bash_history    -> ~/.bash_history
│   ├── shell/python_history  -> ~/.python_history
│   ├── npm/npmrc             -> ~/.npmrc
│   ├── cargo/config.toml     -> ~/.cargo/config.toml
│   ├── cargo/credentials.toml-> ~/.cargo/credentials.toml
│   ├── netrc                 -> ~/.netrc
│   └── pypirc                -> ~/.pypirc
└── auth/users.caddy          -> Web Basic Auth
```

### DSH 自身

整个：

```text
/home/node/.dsh
```

映射到：

```text
.runtime/dsh-home
```

因此 DSH Home 下的配置、profiles、sessions/state、credentials 等都会跟随宿主机持久化。

### Workspace

```text
.runtime/workspace
        ↕
/workspace
```

目录选择器默认从 `/home/node` 开始，因此启动时自动创建：

```text
/home/node/workspace -> /workspace
```

### Git / SSH

SSH：

```text
~/.ssh
  ↓
.runtime/home/ssh
```

Git：

```text
~/.gitconfig
  ↓
.runtime/home/git/config

~/.git-credentials
  ↓
.runtime/home/git/credentials
```

生成 Key：

```bash
docker compose exec dsh bash
ssh-keygen -t ed25519 -C "you@example.com"
```

删除或重建容器后 Key 仍然存在。

> `git credential.helper store` 会明文保存 HTTPS 凭据；GitHub 认证更推荐 SSH Key。

## 为什么不映射整个 `/home/node`

镜像中的 Go/Rust/npm/DSH 工具链有一部分位于 Home 下。整个 Home bind mount 会把镜像里的工具隐藏掉。

所以使用：

```text
.runtime/home -> /home/node/.persist
```

再把真正需要长期保存的 Home 路径链接进去。

## 旧版本迁移

`deploy.sh` 和 `rebuild.sh` 会在替换已有容器之前执行：

```bash
scripts/migrate-home-state.sh
```

如果旧容器已有 SSH Key、Git config、XDG config 等，而 `.runtime/home` 对应位置还为空，会先复制到宿主机。已有持久化数据不会被覆盖。

## 权限

自动维护：

```text
.runtime/home          0700
~/.ssh                 0700
SSH private files      0600
SSH public/known_hosts 0644
GnuPG                  0700/0600
Git/CLI secret files   0600
```

手工修复：

```bash
bash scripts/fix-home-permissions.sh
```

## 部署

```bash
git clone https://github.com/rin721/dsh-docker.git
cd dsh-docker
./scripts/deploy.sh
```

如果 executable bit 被文件系统破坏：

```bash
bash scripts/deploy.sh
```

## Core

默认：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
```

你自己的 Nginx / 1Panel upstream：

```text
http://127.0.0.1:3080
```

仓库不管理域名、TLS、80/443。

## 动态反代

不要求配置具体域名。Core 会校验外部 Host/Origin，再转换成 DSH 内部 loopback authority。

## 镜像

默认：

```dotenv
DSH_IMAGE_MODE=auto
DSH_IMAGE=ghcr.io/rin721/dsh-docker:latest
```

优先 Pull；不可用时复用本地镜像；仍没有才本地 Build。

`auto` 模式下 `docker pull` 的下载进度会**实时显示**（而不是被缓存、看起来像卡死）。
若拉取长时间无进展，见下方「镜像拉取与网络排查」。

## 状态与诊断

```bash
./scripts/check.sh
./scripts/doctor.sh
./scripts/check-image.sh
```

会检查 Workspace、Developer Home、SSH/Git 持久化以及权限；`check-image.sh` 额外检查
预构建镜像与 GHCR 网络连通性。

### 镜像拉取与网络排查

若 `deploy.sh` 在「尝试拉取预构建 DSH 镜像」后长时间无输出，按顺序排查：

1. 确认是否只是进度缓慢：`docker pull ghcr.io/rin721/dsh-docker:latest` 看是否出现
   `Pulling fs layer` / `Downloading ...`。能显示进度=正常，只是镜像较大或带宽慢。
2. 一键诊断：`./scripts/check-image.sh`（检测 manifest、GHCR Registry、Layer CDN DNS）。
3. Registry 与 Layer CDN 分开测试：

   ```bash
   time docker manifest inspect ghcr.io/rin721/dsh-docker:latest >/dev/null
   getent hosts ghcr.io
   getent hosts pkg-containers.githubusercontent.com
   curl -I --connect-timeout 10 https://ghcr.io/v2/
   ```

   - `curl -I https://ghcr.io/v2/` 返回 `HTTP/2 401` 是**正常**（说明 DNS/TCP/TLS 通）。
   - 若 manifest 秒回、而 `docker pull` 卡在 `Downloading/Waiting`，问题多在 Layer CDN
     `pkg-containers.githubusercontent.com` 或服务器出口网络。


## 备份

```bash
./scripts/backup.sh
```

备份：

```text
.env
.runtime/
```

备份文件权限为 `0600`。

**其中包含 SSH 私钥、Git/Cloud/CLI 凭据和 DSH 凭据，必须作为敏感文件保存。**

## 更新

```bash
./scripts/update.sh
```

不会删除：

```text
.env
.runtime/workspace
.runtime/dsh-home
.runtime/home
.runtime/auth
```

## 常用命令

```bash
./scripts/deploy.sh
./scripts/update.sh
./scripts/rebuild.sh
./scripts/check.sh
./scripts/doctor.sh

./scripts/create-user.sh
./scripts/list-users.sh
./scripts/remove-user.sh

bash scripts/fix-home-permissions.sh
bash scripts/migrate-home-state.sh
bash scripts/backup.sh

docker compose exec dsh bash
```
