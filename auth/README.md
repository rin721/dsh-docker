# Authentication runtime

真实 Tinyauth 用户配置不保存在 Git 仓库的 `auth/` 目录中。

运行：

```bash
./scripts/create-user.sh
```

后动态生成：

```text
<repository>/.runtime/tinyauth/config.yml
```

内容类似：

```yaml
auth:
  users:
    - "xiaolin:$2a$10$..."
```

只保存 bcrypt Hash，不保存明文密码。

`.runtime/` 已被 `.gitignore` 忽略。
