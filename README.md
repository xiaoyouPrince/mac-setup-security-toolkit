# 新系统自动化安装前置准备

这份文档只记录脚本执行前必须手动完成的事情。后续自动化脚本默认这些条件已经满足，不再尝试替你绕过 GUI、网络或账号确认。

## 1. 手动设置触控板

先在系统设置里完成个人操作习惯配置。

建议检查：

1. 系统设置 -> 触控板
   - 轻点来点按
   - 跟踪速度
   - 滚动方向
   - 辅助点按
   - 更多手势

2. 系统设置 -> 辅助功能 -> 指针控制 -> 触控板选项
   - 开启拖移
   - 选择三指拖移

这些设置不放进脚本自动处理，避免修改系统辅助功能偏好时产生不可控差异。

## 2. 手动安装 Xcode

从 App Store 手动安装 Xcode。

安装完成后，先打开一次 Xcode，完成初始组件安装和必要授权确认。

后续脚本只负责检查和初始化 Xcode 命令行环境，例如：

```bash
xcode-select -p
xcodebuild -version
swift --version
git --version
```

如果 Xcode 没有安装完成，不要执行后续自动化脚本。

## 3. 手动配置 VPN / 代理

先手动准备并配置 VPN 或代理工具。

推荐使用：

```text
FlClash
```

也可以使用其他你确认可信的代理工具。

前置要求：

1. 代理工具已经安装。
2. 已导入你确认可信的配置。
3. 可以正常访问国际互联网，或至少可以访问清华 Homebrew 镜像。
4. 本地代理端口已经确认，例如常见端口：

```text
7890
```

5. 系统代理或命令行代理至少有一种可用。

后续脚本会优先使用 GitHub 官方源；如果 GitHub raw 不通，会自动尝试清华 Homebrew 镜像。脚本不负责下载安装 FlClash，也不在完全没有外网或镜像网络的情况下强行安装 Homebrew。

## 4. 执行安装流程

前面 3 项都完成后，再执行脚本。

推荐从交互入口开始：

```bash
cd ~/Desktop/TODO/new
chmod +x start.sh
./start.sh
```

在菜单中选择 `9) Explain actions and rules` 可以查看每个选项会做什么、是否修改文件、已安装时如何处理。

安全事件复查和清理也已经集成到菜单：

```text
10) Security incident check (read-only)
11) Clean user/project incident artifacts
12) Clean system incident artifacts (sudo)
```

日常复查优先使用 `10`。只有复查报告重新发现相同持久化项时，再使用 `11` 或 `12`。

脚本生成的报告统一放在 `logs/` 下：

```text
logs/install/
logs/git-hooks/
logs/security-incidents/
```

建议顺序：

1. 先选择 `1) Install or refresh shell proxy helpers`。
2. 退出菜单。
3. 在当前终端执行：

```bash
source ~/.zshrc
proxy_on 7890
```

4. 重新执行 `./start.sh`，选择 `2) Install base environment`。

如果你的代理端口不是 `7890`，把上面的端口替换成代理软件给出的端口。

也可以单独执行基础环境安装脚本。

如果需要写入 Git 用户名和邮箱：

```bash
GIT_USER_NAME="你的名字" GIT_USER_EMAIL="你的邮箱" ./install_base_env.sh
```

如果暂时不想设置 Git 用户名和邮箱：

```bash
./install_base_env.sh
```

脚本会执行：

1. 检查 Apple Silicon、Xcode、Homebrew 安装源网络连通性。
2. 初始化 Xcode 命令行环境，并把 active developer directory 设置为 `/Applications/Xcode.app/Contents/Developer`。
3. 安装或更新 Homebrew。
4. 使用 `Brewfile` 安装 CLI 工具和常用 App。
5. 安装 Oh My Zsh。
6. 设置 Oh My Zsh 主题为 `robbyrussell`，插件为 `(git)`。
7. 设置基础 Git 默认项。
8. 输出版本验证结果。

默认安装源选择为自动模式：

```bash
./install_base_env.sh
```

也可以手动指定：

```bash
HOMEBREW_INSTALL_FROM=github ./install_base_env.sh
HOMEBREW_INSTALL_FROM=tuna ./install_base_env.sh
```

CLI 工具包含：

```text
git
git-lfs
jq
ripgrep
tree
wget
tmux
tldr
node
swiftlint
cocoapods
```

GUI App 包含：

```text
iTerm2
Xcodes
Cursor
Codex
ChatGPT
Google Chrome
Eudic
GitHub Desktop
Charles
Lookin
Navicat Premium
```

完整日志会写到：

```text
logs/install/
```

### 代理 helper 安装与用法

`install_base_env.sh` 不设置命令行代理。代理 helper 是独立功能，需要单独执行：

```bash
cd ~/Desktop/TODO/new
chmod +x setup_shell_proxy.sh
./setup_shell_proxy.sh
```

`setup_shell_proxy.sh` 会写入：

```text
~/.config/new-mac/proxy.zsh
```

并在下面两个文件里加入加载语句：

```text
~/.zshrc
~/.zprofile
```

这样系统 Terminal 和 iTerm2 / Oh My Zsh 新窗口都能加载这些函数。

当前窗口立即生效：

```bash
source ~/.zshrc
```

常见用法：

```bash
proxy_set 7890
proxy_on
proxy_status
proxy_test
```

如果你的 VPN 工具有不同端口，例如 HTTP 是 `7897`，SOCKS 是 `7898`：

```bash
proxy_set 7897 7898
proxy_on
```

也可以不保存配置，直接临时启用：

```bash
proxy_on 7897 7898
```

Git 单独走代理：

```bash
git_proxy_on
git_proxy_status
git_proxy_off
```

## 5. 后续脚本

基础环境安装完成后，继续执行：

```bash
cd ~/Desktop/TODO/new
chmod +x setup_ssh_keys.sh verify_security.sh scan_git_hooks.sh
./setup_shell_proxy.sh
./setup_ssh_keys.sh
./verify_security.sh
./scan_git_hooks.sh
```

`scan_git_hooks.sh` 依赖 `rg` 命令；它由 Brewfile 中的 `ripgrep` 提供，也可以单独安装：

```bash
brew install ripgrep
```

手动安全操作见：

```text
ACCOUNT_SECURITY.md
MIGRATION_CHECKLIST.md
```
