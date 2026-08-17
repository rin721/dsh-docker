# Authentication

Core Gateway 使用 Caddy HTTP Basic Authentication。

认证文件：

```text
.runtime/auth/users.caddy
```

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

明文密码不落盘。

SSH/Git 等开发者凭据位于 `.runtime/home/`。
