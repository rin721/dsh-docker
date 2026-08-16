# DeepSeek Harness 多语言开发容器

## 启动

```bash
sudo mkdir -p /var/lib/.dsh/data /var/lib/.dsh/home
sudo chown -R 1000:1000 /var/lib/.dsh
sudo chmod 0750 /var/lib/.dsh /var/lib/.dsh/data
sudo chmod 0700 /var/lib/.dsh/home

docker compose build --pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 -f dsh
```

在服务器本机访问：`http://localhost:3080`。

远程服务器建议使用 SSH 隧道：

```bash
ssh -N -L 3080:127.0.0.1:3080 user@server
```

然后在本地浏览器访问：`http://localhost:3080`，并在 DSH 中选择 `/workspace`。

## 常用操作

```bash
# 进入开发容器
docker compose exec dsh bash

# 检查工具链
docker compose exec dsh bash -lc '\
  node -v && npm -v && pnpm -v && \
  go version && gopls version && \
  rustc -V && cargo -V && \
  python3 --version && curl --version | head -1 && \
  dsh --version'

# 停止
docker compose down
```

不要把 `/var/run/docker.sock`、宿主机根目录或 SSH 私钥直接挂载给该容器，除非你明确接受相应权限风险。
