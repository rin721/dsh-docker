# Authentication

Core Gateway 使用 Caddy HTTP Basic Authentication。

用户数据默认保存在：

```text
.runtime/auth/users.caddy
```

格式：

```text
username $2a$14$...
```

明文密码不落盘。

## 创建 / 修改密码

```bash
./scripts/create-user.sh
```

同名用户再次创建即更新该用户密码。

## 查看用户

```bash
./scripts/list-users.sh
```

## 删除用户

```bash
./scripts/remove-user.sh
```

## 安全说明

`domain-http` 是项目正式支持的部署模式，但 HTTP Basic Auth 在纯 HTTP 上传输时不提供链路加密。它只适合可信局域网、VPN、内网或你明确接受该风险的环境。

公网正式部署优先使用 `domain-https` 或在项目 Core 前面放置你自己的 HTTPS 反向代理。
