# mac-setup-security-toolkit

[English](README.md) | [简体中文](README.zh-CN.md)

适用于 Apple Silicon Mac 的环境配置与安全恢复脚本集。

本仓库提供一套基于 Shell 的工具，用于配置全新的 macOS 开发环境、安装常用开发工具、设置终端代理辅助命令、生成 SSH 密钥，以及检查或清理已知的 Git Hook、Shell 启动文件和 LaunchDaemon 持久化风险。

所有脚本都明确展示执行过程，不会自动处理只能通过图形界面完成的设置，不会绕过账户确认，也不会隐藏需要管理员权限的操作。

## 项目背景

这个工具集最初用于一台 Apple Silicon Mac 在抹掉磁盘并重新安装 macOS 后的环境重建。重新配置开发环境时出现了几个实际问题：macOS 隐私权限可能导致终端访问目录时报 `Operation not permitted`；终端中已经存在代理变量，并不代表 GitHub Raw 或 Homebrew 镜像一定可达；部分耗时检查缺少过程提示，运行时容易被误认为卡死。

在检查一个刚克隆的 Git 仓库时，扫描发现了一个实际生效的非 sample Git Hook。继续排查后，又在 Shell 启动配置、macOS `defaults`、系统 LaunchDaemon 和 Xcode 项目中发现了相关持久化特征。分析这些文件的行为、保留排查证据、清理用户级文件，以及完成需要管理员权限的系统清理，涉及多组分散的命令和报告。

这些环境配置和安全排查命令本身可以解决问题，但不便于稳定复用；以后再次重装系统或遇到类似事件时，也容易遗漏步骤。因此，本仓库将相关操作整理成一个统一、可审查的工具集，提供网络预检、进度与状态输出、Git Hook 扫描、只读和隔离模式、已知特征检查、清理流程以及带时间戳的报告。

工具集遵循“先检查，再修改”的原则。只读检查与清理操作相互分离，可能造成文件变更的操作需要确认，管理员权限操作会明确显示在终端中。

## 功能范围

本工具集包括：

- 安装终端网络代理辅助命令
- 通过 Homebrew 和 `Brewfile` 安装基础开发环境
- 初始化 Xcode 命令行环境
- 为 Git 服务生成 SSH 密钥
- 执行安装后的环境验证
- 扫描并按需隔离 Git Hook
- 检查已知的安全事件持久化特征
- 在 `logs/` 下生成带时间戳的报告

本工具集不包括：

- 从 App Store 安装 Xcode
- 配置 VPN 或代理应用
- 将 SSH 公钥上传至 GitHub 或 GitLab
- 撤销在线令牌或登录会话
- 替代完整的终端安全软件

## 环境要求

- Apple Silicon Mac
- 已安装 Terminal 或 iTerm2 的 macOS
- 已从 App Store 安装并至少启动过一次 Xcode
- 可以访问 GitHub Raw 或可用的 Homebrew 镜像
- 可使用 `sudo`，用于初始化 Xcode、配置 Homebrew 以及执行系统级安全清理

## 手动设置

### 触控板

在“系统设置”中按个人习惯配置触控板。

常用设置位置：

- 系统设置 -> 触控板
- 系统设置 -> 辅助功能 -> 指针控制 -> 触控板选项

这些设置具有较强的个人偏好，并且依赖图形界面，因此不由脚本处理。

### Xcode

从 App Store 安装 Xcode，启动一次，并完成初始组件安装和许可确认。

可使用以下命令检查环境：

```bash
xcode-select -p
xcodebuild -version
swift --version
git --version
```

### 网络代理

运行基础安装脚本前，应准备可信的 VPN 或代理应用。本工具可以安装终端代理辅助函数，但不会安装或配置代理应用本身。

常见本地代理端口：

```text
7890
```

如果无法访问 GitHub Raw，安装脚本会在适用场景下尝试使用清华 Homebrew 镜像。

## 快速开始

在仓库目录中执行：

```bash
chmod +x *.sh
./start.sh
```

首次运行的建议顺序：

1. 选择 `1) Install or refresh shell proxy helpers`。
2. 输入 `0` 退出菜单。
3. 加载辅助函数并启用代理：

```bash
source ~/.zshrc
proxy_on 7890
```

4. 再次运行菜单：

```bash
./start.sh
```

5. 选择 `2) Install base environment`。

如果本地代理端口不是 `7890`，请替换为代理应用实际使用的端口。

## 交互菜单

`start.sh` 是工具集的主入口。

```text
1) Install or refresh shell proxy helpers
2) Install base environment
3) Generate SSH keys
4) Run security verification
5) Scan Git hooks (dry run)
6) Quarantine suspicious Git hooks
7) Quarantine all non-sample Git hooks
8) Show manual checklist paths
9) Security incident check (read-only)
10) Clean user/project incident artifacts
11) Clean system incident artifacts (sudo)
12) Explain actions and rules
0) Quit
```

选项 `12` 会显示每项操作的详细行为和安全说明。

## 日志与报告

脚本生成的内容统一保存在 `logs/` 下：

```text
logs/install/
logs/git-hooks/
logs/security-incidents/
```

`logs/` 已被 Git 忽略。报告中可能包含本地路径、被隔离的文件、命令输出或调查记录。

## 基础开发环境

基础安装脚本为 `install_base_env.sh`，可以通过 `start.sh` 的选项 `2` 运行，也可以直接执行：

```bash
./install_base_env.sh
```

可选的 Git 身份配置：

```bash
GIT_USER_NAME="Your Name" GIT_USER_EMAIL="you@example.com" ./install_base_env.sh
```

选择 Homebrew 来源：

```bash
HOMEBREW_INSTALL_FROM=github ./install_base_env.sh
HOMEBREW_INSTALL_FROM=tuna ./install_base_env.sh
```

默认模式为 `auto`。

安装脚本会执行：

- 检查 Apple Silicon、Xcode、Brewfile 和网络状态
- 初始化 Xcode 命令行环境
- 安装或更新 Homebrew
- 安装 `Brewfile` 中的软件
- 在缺少 Oh My Zsh 时进行安装
- 配置基础的 Oh My Zsh 和 Git 默认值
- 检查主要工具版本

当前 `Brewfile` 中的命令行工具包括：

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
gh
```

当前 `Brewfile` 中的图形应用包括：

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

## 终端代理辅助命令

`setup_shell_proxy.sh` 会写入：

```text
~/.config/new-mac/proxy.zsh
```

同时会在以下文件中添加加载语句：

```text
~/.zshrc
~/.zprofile
```

可用的辅助函数：

```bash
proxy_set 7890
proxy_on
proxy_off
proxy_status
proxy_test
git_proxy_on
git_proxy_off
git_proxy_status
```

HTTP 和 SOCKS 使用不同端口时：

```bash
proxy_set 7897 7898
proxy_on
```

仅在当前终端会话中临时启用：

```bash
proxy_on 7897 7898
```

## SSH 密钥

`setup_ssh_keys.sh` 会创建带日期的 ed25519 SSH 密钥，并更新 SSH 配置。已存在的同路径密钥不会被覆盖。

通过选项 `3` 运行，或直接执行：

```bash
./setup_ssh_keys.sh
```

脚本不会将密钥上传到任何在线服务。

## 环境验证

`verify_security.sh` 只报告环境和安全相关状态，不会修改文件。

检查内容包括：

- 系统和 Xcode 信息
- 预期安装的命令行工具
- 主要工具版本
- SSH 公钥
- 已知的可疑启动项和进程
- hosts 文件特征
- 可执行 Git Hook

通过选项 `4` 运行，或直接执行：

```bash
./verify_security.sh
```

## Git Hook 扫描

`scan_git_hooks.sh` 会扫描以下目录中的 Git Hook：

```text
~/Documents
~/Desktop
~/Downloads
```

只扫描，不修改文件：

```bash
./scan_git_hooks.sh
```

仅隔离可疑 Hook：

```bash
./scan_git_hooks.sh --apply
```

隔离所有非 sample Hook：

```bash
./scan_git_hooks.sh --apply --remove-all-hooks
```

Git 自带的 `pre-commit.sample` 等 sample Hook 是模板，不会被 Git 执行。实际生效的 Hook 不带 `.sample` 后缀，例如 `pre-commit`、`commit-msg` 或 `pre-push`。

报告内容包括：

```text
git_repositories.txt
all_hooks.txt
suspicious_hooks.txt
suspicious_hook_details.txt
quarantined_hooks/
```

## 安全事件检查

`cleanup_security_incident.sh` 用于重复检查和清理此前调查中发现的已知持久化模式。

只读检查：

```bash
./cleanup_security_incident.sh check
```

清理用户及项目文件：

```bash
./cleanup_security_incident.sh clean
```

该模式还会以 apply 模式调用 Git Hook 扫描器。`~/Documents`、`~/Desktop` 和 `~/Downloads` 下所有命中的非 sample 可疑 Hook，都会先复制到本次事件报告的隔离目录，再从原仓库删除。清理目标来自扫描结果，不再局限于某一个仓库路径。

清理用户、项目和系统文件：

```bash
./cleanup_security_incident.sh clean --system
```

系统清理模式可能会请求 `sudo` 权限。它会扫描 `/Library/LaunchDaemons`，通过“已知 IOC 加 Shell 执行特征”或“长 Base64 载荷直接解码到 Shell”的结构识别恶意持久化。命中的 plist 会先备份，再根据解析出的 `Label` 卸载并删除；检测不再依赖固定 plist 文件名。该模式还会恢复 macOS 软件更新中快速安全响应的相关偏好设置。

检查和清理完成后，终端会显示概要结论，包括整体状态、匹配到的特征数量、`defaults invelc` 状态、可疑 LaunchDaemon 数量、活动 Hook 数量、可疑 Hook 数量和报告路径。只要仍有可疑特征，检查和清理都会返回非零退出状态；清理模式会在结束前强制重新扫描。

只读检查适合定期运行，检查范围包括：

- Shell 启动文件
- `defaults invelc`
- 可疑 LaunchDaemon 载荷特征
- 在允许枚举进程时检查匹配的进程名
- Git Hook
- 已知 Xcode 项目特征

部分受限终端环境可能不允许枚举进程。文件、defaults、launchd、Git Hook 和 Xcode 项目检查是主要判断依据。

原始安全事件的详细记录位于：

```text
SECURITY_INCIDENT_REPORT.md
```

## 手动账户安全检查

部分安全操作必须在线完成，本工具不会自动处理。

相关文档：

```text
ACCOUNT_SECURITY.md
MIGRATION_CHECKLIST.md
```

常见手动操作包括：

- 从 GitHub/GitLab 删除旧 SSH 密钥
- 撤销旧的个人访问令牌
- 检查 OAuth 应用授权
- 检查当前登录会话
- 避免迁移旧浏览器配置、令牌文件和来源不明的 Shell 配置

## 注意事项

- 使用选项 `6` 或 `7` 前，先运行选项 `5`。
- 使用选项 `10` 或 `11` 前，先运行选项 `9`。
- 密码只能输入到终端的 `sudo` 提示中。
- 不要将不可信的远程脚本通过管道直接交给 `sh` 执行。
- 删除隔离内容前，先检查 `logs/` 下的报告。
