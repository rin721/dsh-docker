# Authentication runtime

真实 Tinyauth 用户配置不会保存在此目录。

`./scripts/create-user.sh` 会动态写入：

```text
<repository>/.runtime/tinyauth/config.yml
```

`.runtime/` 已被 `.gitignore` 忽略。
