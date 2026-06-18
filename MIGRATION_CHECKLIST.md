# 个人数据迁移清单

原则：只迁移明确的个人文件，不迁移旧环境状态。

## 可以迁移

1. 文档。
2. 图片。
3. 视频。
4. 音频。
5. 设计稿。
6. 压缩包。
7. 数据库导出文件，例如 `.sql`、`.sqlite`、`.db`。
8. 未推送代码的 patch 或干净工作区文件。

## 不要迁移

1. `~/Library` 整体。
2. 旧 `~/.ssh` 私钥。
3. 旧浏览器 profile。
4. 旧 token 文件。
5. `/usr/local`。
6. `/opt/homebrew`。
7. `node_modules`。
8. `Pods`。
9. `DerivedData`。
10. `malware-cleanup-backup-*` 和 `malware_quarantine_*`，除非只是作为证据压缩保存。

## Git 仓库

优先级：

1. 能从 GitHub/GitLab 重新 clone 的仓库，重新 clone。
2. 有未推送内容的仓库，迁移 patch。
3. 只需要源码时，复制工作文件但排除 `.git`。

迁移后扫描：

```bash
cd ~/Desktop/TODO/new
./scan_git_hooks.sh
```

如果要最大限度降低迁移风险，隔离所有非 sample hook：

```bash
cd ~/Desktop/TODO/new
./scan_git_hooks.sh --apply --remove-all-hooks
```

## 查找可能需要人工检查的脚本

```bash
find ~/Documents ~/Desktop ~/Downloads -type f \( -name '*.sh' -o -name '*.command' -o -name '*.py' -o -name '*.rb' -o -name '*.js' \) -print
```

