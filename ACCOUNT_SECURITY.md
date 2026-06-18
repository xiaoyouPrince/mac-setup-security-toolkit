# 账号与凭据安全清单

这些步骤不适合脚本自动执行，需要你手动确认。

## GitHub

打开：

```text
https://github.com/settings/keys
https://github.com/settings/tokens
https://github.com/settings/personal-access-tokens
https://github.com/settings/applications
https://github.com/settings/security
```

操作：

1. 添加新生成的 SSH public key。
2. 删除旧 SSH key。
3. 撤销旧 classic token。
4. 撤销旧 fine-grained token。
5. 撤销不认识或不再使用的 OAuth Apps。
6. 检查 active sessions，退出不认识的 session。

测试：

```bash
ssh -T git@github.com
```

## GitLab / 公司 Git

操作：

1. 添加新生成的 SSH public key。
2. 删除旧 SSH key。
3. 撤销旧 access token。
4. 检查 OAuth / application 授权。

## Apple ID

打开：

```text
https://account.apple.com/
```

操作：

1. 修改 Apple ID 密码。
2. 确认双重认证开启。
3. 检查受信任设备。
4. 移除不认识的设备。
5. 删除不认识的 app-specific passwords。

## 浏览器与 App

1. 不迁移旧 Chrome profile。
2. 重新登录 Chrome。
3. 检查 Chrome 扩展，只安装明确需要的扩展。
4. 重要账号优先改密码。
5. Cursor、Codex、GitHub Desktop 重新登录。
6. 不迁移旧 auth、history、sqlite、token 文件。

