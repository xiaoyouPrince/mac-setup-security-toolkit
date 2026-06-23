# mac-setup-security-toolkit

[English](README.md) | [简体中文](README.zh-CN.md)

Apple Silicon Mac setup and security recovery scripts.

This repository contains a shell-based toolkit for preparing a clean macOS development environment, installing common developer tools, configuring shell proxy helpers, generating SSH keys, and checking or cleaning known Git hook, shell startup, and LaunchDaemon persistence patterns.

The scripts are intentionally explicit. They do not automate GUI-only setup, bypass account prompts, or hide privileged operations.

## Background

This toolkit began during the rebuild of an Apple Silicon Mac after a clean disk erase and macOS installation. Reinstalling the development environment exposed several practical problems: macOS privacy controls could make terminal access fail with `Operation not permitted`, shell proxy variables did not guarantee that GitHub Raw or a Homebrew mirror was actually reachable, and long-running checks provided little visible progress.

During a review of a newly cloned Git repository, an active non-sample Git hook was detected. Further investigation found related persistence indicators in shell startup configuration, macOS `defaults`, a system LaunchDaemon, and an Xcode project. Determining what each artifact did, preserving evidence, removing user-level files, and completing privileged system cleanup required a sequence of separate commands and reports.

The original setup and investigation commands were useful, but difficult to repeat consistently and easy to omit during a future rebuild or incident. This repository consolidates that work into a single, reviewable toolkit with network preflight checks, progress and status output, Git hook scanning, dry-run and quarantine modes, known-indicator checks, cleanup routines, and timestamped reports.

The operating principle is to inspect before modifying. Read-only checks are separated from cleanup actions, destructive choices require confirmation, and privileged operations remain visible in the terminal.

## Scope

The toolkit covers:

- shell proxy helper installation for command-line network access
- base developer environment installation through Homebrew and `Brewfile`
- Xcode command-line environment initialization
- SSH key generation for Git services
- post-install verification
- Git hook scanning and optional quarantine
- security incident checks for known persistence indicators
- timestamped reports under `logs/`

The toolkit does not cover:

- installing Xcode from the App Store
- configuring VPN/proxy applications
- uploading SSH keys to GitHub or GitLab
- revoking online tokens or sessions
- replacing a full endpoint security product

## Requirements

- Apple Silicon Mac
- macOS with Terminal or iTerm2
- Xcode installed from the App Store and opened once
- network access to GitHub raw or a reachable Homebrew mirror
- `sudo` access for Xcode initialization, Homebrew-related setup, and system-level security cleanup

## Manual Setup

### Trackpad

Configure personal trackpad preferences in System Settings.

Common settings to review:

- System Settings -> Trackpad
- System Settings -> Accessibility -> Pointer Control -> Trackpad Options

These settings are not scripted because they are preference-heavy and GUI-specific.

### Xcode

Install Xcode from the App Store, open it once, and complete the initial component installation and license prompts.

Useful checks:

```bash
xcode-select -p
xcodebuild -version
swift --version
git --version
```

### Network Proxy

Prepare a trusted VPN or proxy application before running the base installer. The scripts can install shell proxy helper functions, but they do not install or configure the proxy application itself.

Common local proxy ports include:

```text
7890
```

If GitHub raw is unreachable, the installer can use the Tsinghua Homebrew mirror where applicable.

## Quick Start

From the repository directory:

```bash
chmod +x *.sh
./start.sh
```

The recommended first run is:

1. Choose `1) Install or refresh shell proxy helpers`.
2. Quit the menu with `0`.
3. Load the helper and enable the proxy:

```bash
source ~/.zshrc
proxy_on 7890
```

4. Run the menu again:

```bash
./start.sh
```

5. Choose `2) Install base environment`.

If the proxy port is different, replace `7890` with the port used by the local proxy application.

## Interactive Menu

`start.sh` is the main entry point.

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

Option `12` prints detailed behavior and safety notes for each action.

## Logs And Reports

Generated output is kept under `logs/`:

```text
logs/install/
logs/git-hooks/
logs/security-incidents/
```

`logs/` is ignored by Git. Reports may contain local paths, quarantined files, command output, or forensic notes.

## Base Environment

The base installer is `install_base_env.sh`. It can be run through option `2` in `start.sh` or directly:

```bash
./install_base_env.sh
```

Optional Git identity configuration:

```bash
GIT_USER_NAME="Your Name" GIT_USER_EMAIL="you@example.com" ./install_base_env.sh
```

Homebrew source selection:

```bash
HOMEBREW_INSTALL_FROM=github ./install_base_env.sh
HOMEBREW_INSTALL_FROM=tuna ./install_base_env.sh
```

Default mode is `auto`.

The installer performs:

- Apple Silicon, Xcode, Brewfile, and network preflight checks
- Xcode command-line environment initialization
- Homebrew install or update
- `Brewfile` installation
- Oh My Zsh installation when missing
- basic Oh My Zsh and Git defaults
- version verification

CLI tools in the current `Brewfile` include:

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

GUI applications in the current `Brewfile` include:

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

## Shell Proxy Helpers

`setup_shell_proxy.sh` writes:

```text
~/.config/new-mac/proxy.zsh
```

It also adds a loader line to:

```text
~/.zshrc
~/.zprofile
```

Available helper functions:

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

For separate HTTP and SOCKS ports:

```bash
proxy_set 7897 7898
proxy_on
```

For a one-off shell session:

```bash
proxy_on 7897 7898
```

## SSH Keys

`setup_ssh_keys.sh` creates date-stamped ed25519 SSH keys and updates SSH config entries. Existing keys with the same generated path are not overwritten.

Run through option `3` or directly:

```bash
./setup_ssh_keys.sh
```

The script does not upload keys to any online service.

## Verification

`verify_security.sh` reports environment and security-related state without modifying files.

It checks:

- system and Xcode information
- expected CLI tools
- key tool versions
- SSH public keys
- known suspicious launch items and processes
- hosts file indicators
- executable Git hooks

Run through option `4` or directly:

```bash
./verify_security.sh
```

## Git Hook Scanning

`scan_git_hooks.sh` scans Git hooks under:

```text
~/Documents
~/Desktop
~/Downloads
```

Dry run:

```bash
./scan_git_hooks.sh
```

Quarantine suspicious hooks only:

```bash
./scan_git_hooks.sh --apply
```

Quarantine all non-sample hooks:

```bash
./scan_git_hooks.sh --apply --remove-all-hooks
```

Git sample hooks such as `pre-commit.sample` are templates and are not executed by Git. Active hooks are files without the `.sample` suffix, such as `pre-commit`, `commit-msg`, or `pre-push`.

Reports include:

```text
git_repositories.txt
all_hooks.txt
suspicious_hooks.txt
suspicious_hook_details.txt
quarantined_hooks/
```

## Security Incident Checks

`cleanup_security_incident.sh` provides reusable checks and cleanup for known persistence patterns found during a prior investigation.

Read-only check:

```bash
./cleanup_security_incident.sh check
```

Clean user and project artifacts:

```bash
./cleanup_security_incident.sh clean
```

This mode also runs the Git hook scanner in apply mode. Every suspicious non-sample hook under `~/Documents`, `~/Desktop`, and `~/Downloads` is copied into the incident report quarantine directory before removal. Cleanup is driven by scan results rather than a single repository path.

Clean user, project, and system artifacts:

```bash
./cleanup_security_incident.sh clean --system
```

The system cleanup mode may request `sudo`. It scans `/Library/LaunchDaemons` and identifies malicious persistence using known IOC plus shell-execution traits, or a long Base64 payload decoded directly into a shell. Matching plist files are backed up, unloaded by their parsed `Label`, and removed. Detection does not depend on a fixed plist filename. The mode also restores Software Update rapid/security response preference values.

The check and cleanup modes print a terminal summary with the overall conclusion, matching indicator count, `defaults invelc` status, suspicious LaunchDaemon count, active hook count, suspicious hook count, and report path. Both modes return a non-zero exit status while suspicious indicators remain. Cleanup always re-scans before deciding its final status.

The check mode is intended for periodic use. It examines:

- shell startup files
- `defaults invelc`
- suspicious LaunchDaemon payload traits
- matching process names when process enumeration is available
- Git hooks
- known Xcode project indicators

Process enumeration can be unavailable in restricted terminal contexts. The file, defaults, launchd, Git hook, and Xcode project checks are the primary signals.

Details from the original incident are documented in:

```text
SECURITY_INCIDENT_REPORT.md
```

## Manual Account Security

Some security work must be completed online and is not automated here.

See:

```text
ACCOUNT_SECURITY.md
MIGRATION_CHECKLIST.md
```

Typical manual tasks include:

- removing old SSH keys from GitHub/GitLab
- revoking old personal access tokens
- reviewing OAuth applications
- reviewing active sessions
- avoiding migration of old browser profiles, token files, and unknown shell config

## Notes

- Use option `5` before using `6` or `7`.
- Use option `9` before using `10` or `11`.
- Type passwords only into the terminal's `sudo` prompt.
- Do not pipe untrusted remote scripts into `sh`.
- Review reports under `logs/` before deleting quarantine data.
