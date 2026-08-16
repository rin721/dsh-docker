# DeepSeek Harness Docker

一个“仓库即部署单元”的 DeepSeek Harness Docker 环境。

核心原则：

- clone 到任意目录都能部署；
- **不写死 `/var/lib/.dsh` 或其他宿主机绝对目录**；
- 默认运行数据跟随仓库，存储于 `./.runtime/`；
- `.runtime/` 与 `.env` 自动被 Git 忽略；
- 不强制域名、TLS、80/443；
- DSH/Auth 监听地址和端口都可配置；
- DSH、Node、Go、Rust、Python 和开发工具都在容器中；
- `update.sh` 自动 `git pull`，删除旧容器与旧 DSH 构建镜像，再构建并启动新版本；
- 更新/重建不会删除 `.runtime` 中的 workspace、DSH 状态和 Tinyauth 数据。

## 目录模型

克隆到哪里，运行时数据就默认跟到哪里：

```text
/path/to/dsh-docker/
├── Dockerfile
├── compose.yaml
├── scripts/
├── .env                 # 本机配置，Git ignore
└── .runtime/            # 全部运行时数据，Git ignore
    ├── workspace/       # DSH /workspace
    ├── dsh-home/        # /home/node/.dsh
    ├── tinyauth/
    │   ├── config.yml   # bcrypt 登录用户
    │   └── data/        # SQLite/runtime
    └── edge/caddy/      # 可选 HTTPS edge 数据
```

例如：

```bash
cd /opt
git clone https://github.com/rin721/dsh-docker.git
cd dsh-docker
./scripts/deploy.sh
```

则默认持久化到：

```text
/opt/dsh-docker/.runtime/
```

如果克隆到：

```text
/home/dev/services/dsh-docker
```

则自动变为：

```text
/home/dev/services/dsh-docker/.runtime/
```

完全不依赖固定宿主机目录。


## 从旧版固定容器名迁移

旧版曾固定 `name: deepseek-harness` 以及 `container_name`。新版 `deploy.sh/rebuild.sh` 会调用 `cleanup-legacy.sh`：只在容器具有旧版 Compose project 标签时删除对应旧容器，并尝试删除旧的 `local/deepseek-harness-dev:latest` 镜像，不会按名字盲删普通容器。

## 快速部署

```bash
git clone https://github.com/rin721/dsh-docker.git
cd dsh-docker
chmod +x scripts/*.sh start-dsh-web.sh
./scripts/deploy.sh
```

第一次执行会：

1. 自动创建 `.env`；
2. 自动创建 `.runtime`；
3. 如果没有登录用户，交互创建 Tinyauth 用户；
4. 拉取 Tinyauth/Caddy；
5. 构建 DSH 开发镜像；
6. 启动容器。

默认配置：

```text
DSH  : 127.0.0.1:3080
Auth : 127.0.0.1:3081
```

修改 `.env` 即可改变监听地址、端口、AUTH_URL、DSH 版本等。

## 更新

仓库有新版本后，只执行：

```bash
./scripts/update.sh
```

流程：

```text
检查 tracked 文件是否有未提交修改
        ↓
记录当前 DSH 镜像 ID
        ↓
git fetch --prune
        ↓
git pull --ff-only
        ↓
使用刚刚 pull 下来的最新 rebuild.sh
        ↓
docker compose down --remove-orphans
        ↓
删除旧 DSH 本地构建镜像
        ↓
拉取 Tinyauth / Gateway 镜像
        ↓
重新 build DSH
        ↓
docker compose up -d
        ↓
清理 dangling images
```

`.runtime/` 不参与删除，因此以下内容继续保留：

```text
项目/workspace
DSH 配置和会话
登录用户
Tinyauth 数据库
Caddy 可选 edge 数据
```

## 为什么不设置 container_name / 固定 Compose name

项目故意不写：

```yaml
name: deepseek-harness
container_name: xxx
```

Docker Compose 会根据**克隆目录名**生成 project/service/container/image 名称。因此两个不同目录的 clone 可以作为两个独立 Compose project 管理，不会因为硬编码容器名互相冲突。

## 自定义运行数据目录

默认：

```dotenv
RUNTIME_DIR=./.runtime
```

也可以改成相对于仓库的其他目录：

```dotenv
RUNTIME_DIR=./runtime
```

或显式绝对路径：

```dotenv
RUNTIME_DIR=/mnt/ssd/dsh-runtime
```

但项目本身不再要求任何固定绝对路径。

## 端口与访问

默认 `.env`：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=3080
AUTH_PORT=3081
AUTH_URL=http://127.0.0.1:3081
TINYAUTH_SECURE_COOKIE=false
```

局域网示例：

```dotenv
BIND_ADDRESS=0.0.0.0
DSH_PORT=9000
AUTH_PORT=9001
AUTH_URL=http://192.168.1.20:9001
```

已有 Nginx/1Panel/Caddy 示例：

```dotenv
BIND_ADDRESS=127.0.0.1
DSH_PORT=13080
AUTH_PORT=13081
AUTH_URL=https://auth.example.com
TINYAUTH_SECURE_COOKIE=true
```

然后外部代理：

```text
https://dsh.example.com  -> 127.0.0.1:13080
https://auth.example.com -> 127.0.0.1:13081
```

域名和 80/443 始终不是 Core 的强制条件。

## 可选 HTTPS Edge

项目仍提供：

```text
compose.edge.caddy.yaml
Caddyfile.edge
scripts/edge-up.sh
```

只有主动执行：

```bash
./scripts/edge-up.sh
```

才启用域名/TLS Edge。

## 常用命令

```bash
# 部署
./scripts/deploy.sh

# 创建/修改登录用户
./scripts/create-user.sh

# 查看状态
./scripts/check.sh

# 更新代码 + 删除旧容器/旧 DSH 镜像 + 重建
./scripts/update.sh

# 仅按当前代码重建，不 git pull
./scripts/rebuild.sh

# 进入 DSH 容器
 docker compose exec dsh bash

# 日志
 docker compose logs -f --tail=200

# 停止（保留 .runtime）
./scripts/stop.sh
```

## DSH 工作区

宿主机：

```text
<repo>/.runtime/workspace
```

容器：

```text
/workspace
```

因此你可以直接在：

```bash
cd .runtime/workspace
git clone https://github.com/example/project.git
```

DSH 容器立即看到：

```text
/workspace/project
```

## 安全边界

- DSH 不挂载 `/var/run/docker.sock`；
- DSH 不直接控制宿主机 Docker；
- DSH 和 Tinyauth 本体只暴露到 Compose 内网；
- 对宿主机发布的只有 Authentication Gateway；
- `.runtime/tinyauth/config.yml` 中只保存 bcrypt Hash，不保存明文密码；
- `.runtime/` 与 `.env` 不进入 Git；
- `update.sh` 不会自动丢弃 tracked 文件的本地修改。
