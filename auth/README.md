# Authentication

Core 使用 Caddy `basic_auth` 给 DeepSeek Harness 套一层浏览器用户名/密码认证。

真实用户数据不会保存在 Git 仓库中，而是在运行时生成到：

```text
.runtime/auth/users.caddy
```

格式：

```text
username $2a$14$...
```

密码只保存 bcrypt Hash，不保存明文。

请使用项目脚本管理用户，不建议手工编辑：

```bash
./scripts/create-user.sh
./scripts/list-users.sh
./scripts/remove-user.sh
```

HTTP Basic Auth 会把凭据随每次请求发送，因此公网访问必须置于 HTTPS 之后。Core 默认只绑定 `127.0.0.1`，可以由 Nginx、1Panel、Caddy、Cloudflare 等外层 TLS 入口反向代理。
