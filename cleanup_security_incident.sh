#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-check}"
SYSTEM_CLEANUP="false"
if [[ "${2:-}" == "--system" || "${1:-}" == "--system" ]]; then
  SYSTEM_CLEANUP="true"
  [[ "$MODE" == "--system" ]] && MODE="clean"
fi

case "$MODE" in
  check|clean) ;;
  *)
    cat >&2 <<'EOF'
Usage:
  ./cleanup_security_incident.sh check
      Read-only scan. Does not modify files or require sudo.

  ./cleanup_security_incident.sh clean
      Back up and remove known user/project persistence:
      ~/.zshrc payload, defaults domain invelc, all suspicious Git hooks,
      and malicious Xcode project build settings.

  ./cleanup_security_incident.sh clean --system
      Also unload/remove system LaunchDaemons matching known payload traits,
      then restore Software Update security response preferences. Requires sudo.
EOF
    exit 2
    ;;
esac

INCIDENT_ROOT="${INCIDENT_ROOT:-$SCRIPT_DIR/logs/security-incidents}"
INCIDENT_DIR="${INCIDENT_DIR:-$INCIDENT_ROOT/security_incident_$(date +%Y%m%d_%H%M%S)}"
REPORT="$INCIDENT_DIR/cleanup_report.txt"
ZSHRC="$HOME/.zshrc"
SCAN_GIT_HOOKS_SCRIPT="${SCAN_GIT_HOOKS_SCRIPT:-$SCRIPT_DIR/scan_git_hooks.sh}"
SYSTEM_LAUNCH_DAEMON_DIR="${SYSTEM_LAUNCH_DAEMON_DIR:-/Library/LaunchDaemons}"
SYSTEM_LAUNCH_AGENT_DIR="${SYSTEM_LAUNCH_AGENT_DIR:-/Library/LaunchAgents}"
USER_LAUNCH_AGENT_DIR="${USER_LAUNCH_AGENT_DIR:-$HOME/Library/LaunchAgents}"
SKIP_SYSTEM_PREFERENCE_RESTORE="${SKIP_SYSTEM_PREFERENCE_RESTORE:-false}"
SKIP_PROCESS_CLEANUP="${SKIP_PROCESS_CLEANUP:-false}"
SKIP_USER_DEFAULTS="${SKIP_USER_DEFAULTS:-false}"
SKIP_XCODE_PROCESS_CHECK="${SKIP_XCODE_PROCESS_CHECK:-false}"
SHELL_FILES=(
  "$HOME/.zshrc"
  "$HOME/.zprofile"
  "$HOME/.zshenv"
  "$HOME/.zlogin"
  "$HOME/.bashrc"
  "$HOME/.bash_profile"
)
PERSISTENCE_PATHS=(
  "$SYSTEM_LAUNCH_DAEMON_DIR"
  "$SYSTEM_LAUNCH_AGENT_DIR"
  "$USER_LAUNCH_AGENT_DIR"
)
SCAN_ROOTS=(
  "$HOME/Documents"
  "$HOME/Desktop"
  "$HOME/Downloads"
)
PATTERN='invelc|scxqo|qnnx|netcdn|rigacdn|cdnatapple|amzndev|netcdnamz|amznprod|base64 --decode|xxd -p -r|curl .*\| sh|curl .* -d "p=|A3DC1C3|AF17F99'
XCODE_PATTERN='A3DC1C3|AF17F99|base64 --decode|xxd -p -r|curl .*\| sh|curl .* -d "p='
PROCESS_PATTERN='invelc|scxqo|qnnx|netcdn|rigacdn|cdnatapple|amzndev|netcdnamz|amznprod|com.google.rqbcle|CloudTelemetryService'
LAUNCHD_IOC_PATTERN='invelc|scxqo|qnnx|netcdn|rigacdn|cdnatapple|amzndev|netcdnamz|amznprod|CloudTelemetryService'
LAUNCHD_EXEC_PATTERN='base64[[:space:]]+--decode|xxd[[:space:]]+-p[[:space:]]+-r|curl .*\|[[:space:]]*(ba)?sh|defaults[[:space:]]+read.*\|.*(ba)?sh'
LAUNCHD_OBFUSCATED_EXEC_PATTERN='echo[[:space:]]+[A-Za-z0-9+/=]{32,}.*\|[[:space:]]*base64[[:space:]]+--decode[[:space:]]*\|[[:space:]]*(ba)?sh'
MEMORY_PROCESS_PATTERNS=(
  '^osascript /(private/)?tmp/[A-Za-z0-9._-]+ [A-Za-z0-9+/=]{100,}'
  '^/(private/)?tmp/[A-Za-z0-9._-]+ [A-Za-z0-9+/=]{100,}'
  '/private/tmp/m\.app/Contents/MacOS/applet'
)

mkdir -p "$INCIDENT_DIR/backups"
: > "$REPORT"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$REPORT"
}

backup_file() {
  local file="$1"
  local label="$2"
  if [[ -e "$file" || -L "$file" ]]; then
    local dst="$INCIDENT_DIR/backups/${label}"
    cp -p "$file" "$dst"
    log "Backed up $file -> $dst"
  else
    log "Not present: $file"
  fi
}

snapshot_command() {
  local name="$1"
  shift
  {
    printf '\n== %s ==\n' "$name"
    "$@" 2>&1 || true
  } >> "$REPORT"
}

snapshot_processes() {
  {
    printf '\n== suspicious memory processes ==\n'
    local pid found="false"
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      found="true"
      ps -p "$pid" -ww -o user,pid,ppid,lstart,command 2>&1 || true
    done < <(find_suspicious_memory_processes)
    [[ "$found" == "true" ]] || printf 'No suspicious memory process found.\n'

    printf '\n== legacy IOC process-name matches (informational) ==\n'
    pgrep -af "$PROCESS_PATTERN" 2>&1 || true
  } >> "$REPORT"
}

find_suspicious_memory_processes() {
  local pattern
  for pattern in "${MEMORY_PROCESS_PATTERNS[@]}"; do
    pgrep -f "$pattern" 2>/dev/null || true
  done | sort -nu
}

suspicious_memory_process_count() {
  find_suspicious_memory_processes | awk 'NF { count++ } END { print count + 0 }'
}

clean_suspicious_memory_processes() {
  local list="$INCIDENT_DIR/suspicious_memory_processes.txt"
  local pid
  find_suspicious_memory_processes > "$list"

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    ps -p "$pid" -ww -o user,pid,ppid,lstart,command >> "$REPORT" 2>&1 || true
    kill -KILL "$pid" >/dev/null 2>&1 || {
      if [[ "$SYSTEM_CLEANUP" == "true" ]]; then
        sudo kill -KILL "$pid" >/dev/null 2>&1 || true
      fi
    }
    log "Terminated suspicious memory process PID $pid"
  done < "$list"

  sleep 1
  if [[ "$(suspicious_memory_process_count)" -gt 0 ]]; then
    log "ERROR: suspicious memory processes remain after termination."
    return 1
  fi

  local path backup
  for path in /tmp/vk /tmp/pb /private/tmp/m.app; do
    if [[ -e "$path" || -L "$path" ]]; then
      backup="$INCIDENT_DIR/backups/temp-$(basename "$path").before"
      cp -Rp "$path" "$backup"
      rm -rf "$path"
      log "Backed up and removed malicious temporary artifact: $path"
    fi
  done
}

matching_files() {
  local paths=()
  local path project
  for path in "${SHELL_FILES[@]}" "${PERSISTENCE_PATHS[@]}"; do
    [[ -e "$path" ]] && paths+=("$path")
  done

  if [[ "${#paths[@]}" -gt 0 ]]; then
    rg -n -i "$PATTERN" "${paths[@]}" 2>/dev/null || true
  fi

  while IFS= read -r project; do
    [[ -f "$project" ]] || continue
    rg -n -i "$XCODE_PATTERN" "$project" 2>/dev/null || true
  done < <(find_xcode_projects)
}

find_xcode_projects() {
  local root project
  for root in "${SCAN_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' project; do
      printf '%s\n' "$project"
    done < <(
      find "$root" \
        -path '*malware-cleanup-backup-*' -prune -o \
        -path '*malware_quarantine_*' -prune -o \
        -path '*git_hook_scan_*' -prune -o \
        -path '*security_incident_*' -prune -o \
        -name project.pbxproj -type f -print0 2>/dev/null
    )
  done | sort -u
}

find_suspicious_xcode_projects() {
  local project
  while IFS= read -r project; do
    [[ -f "$project" ]] || continue
    if rg -q -i "$XCODE_PATTERN" "$project" 2>/dev/null; then
      printf '%s\n' "$project"
    fi
  done < <(find_xcode_projects)
}

suspicious_xcode_project_count() {
  find_suspicious_xcode_projects | awk 'NF { count++ } END { print count + 0 }'
}

find_active_git_hooks() {
  local root hook
  for root in "${SCAN_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' hook; do
      printf '%s\n' "$hook"
    done < <(find "$root" -path '*/.git/hooks/*' -type f ! -name '*.sample' -print0 2>/dev/null)
  done
}

check_git_hooks() {
  if [[ -f "$SCAN_GIT_HOOKS_SCRIPT" ]]; then
    bash "$SCAN_GIT_HOOKS_SCRIPT"
  else
    find_active_git_hooks
  fi
}

is_suspicious_launchdaemon() {
  local plist="$1"
  [[ -f "$plist" ]] || return 1
  if rg -q -i "$LAUNCHD_IOC_PATTERN" "$plist" 2>/dev/null &&
    rg -q -i "$LAUNCHD_EXEC_PATTERN" "$plist" 2>/dev/null; then
    return 0
  fi
  rg -q -i "$LAUNCHD_OBFUSCATED_EXEC_PATTERN" "$plist" 2>/dev/null
}

find_suspicious_launchdaemons() {
  local plist
  [[ -d "$SYSTEM_LAUNCH_DAEMON_DIR" ]] || return 0
  while IFS= read -r -d '' plist; do
    if is_suspicious_launchdaemon "$plist"; then
      printf '%s\n' "$plist"
    fi
  done < <(find "$SYSTEM_LAUNCH_DAEMON_DIR" -maxdepth 1 -type f -name '*.plist' -print0 2>/dev/null)
}

suspicious_launchdaemon_count() {
  find_suspicious_launchdaemons | awk 'NF { count++ } END { print count + 0 }'
}

launchdaemon_label() {
  local plist="$1"
  local label=""
  label="$(plutil -extract Label raw -o - "$plist" 2>/dev/null || true)"
  if [[ -n "$label" ]]; then
    printf '%s' "$label"
  else
    basename "$plist" .plist
  fi
}

clean_suspicious_launchdaemons() {
  local list="$INCIDENT_DIR/suspicious_launchdaemons.txt"
  local plist label backup
  find_suspicious_launchdaemons > "$list"

  if [[ ! -s "$list" ]]; then
    log "No suspicious system LaunchDaemons found."
    return 0
  fi

  while IFS= read -r plist; do
    [[ -n "$plist" && -f "$plist" ]] || continue
    label="$(launchdaemon_label "$plist")"
    backup="$INCIDENT_DIR/backups/launchdaemon-$(basename "$plist").before"
    cp -p "$plist" "$backup"
    log "Backed up $plist -> $backup"

    if [[ "$SYSTEM_LAUNCH_DAEMON_DIR" == "/Library/LaunchDaemons" ]]; then
      sudo launchctl bootout system "$plist" >/dev/null 2>&1 ||
        sudo launchctl bootout "system/$label" >/dev/null 2>&1 || true
      sudo rm -f "$plist"
    else
      rm -f "$plist"
    fi

    if [[ -e "$plist" || -L "$plist" ]]; then
      log "ERROR: failed to remove suspicious LaunchDaemon: $plist"
    else
      log "Removed suspicious LaunchDaemon: $plist (label: $label)"
    fi
  done < "$list"
}

clean_suspicious_git_hooks() {
  local report_dir="$INCIDENT_DIR/git-hooks-cleanup"
  if [[ ! -f "$SCAN_GIT_HOOKS_SCRIPT" ]]; then
    log "ERROR: Git hook cleanup helper not found: $SCAN_GIT_HOOKS_SCRIPT"
    return 1
  fi

  if bash "$SCAN_GIT_HOOKS_SCRIPT" --apply --report-dir "$report_dir" >> "$REPORT" 2>&1; then
    log "Scanned and quarantined all suspicious Git hooks. Details: $report_dir"
  else
    log "ERROR: suspicious Git hook cleanup failed. Details: $report_dir"
    return 1
  fi
}

malicious_xcode_build_phase_ids() {
  local project="$1"
  awk '
    /Begin PBXShellScriptBuildPhase section/ { in_section = 1; next }
    /End PBXShellScriptBuildPhase section/ { in_section = 0; capturing = 0 }
    in_section && !capturing && /\/\*.*\*\/ = \{/ {
      line = $0
      sub(/^[ \t]*/, "", line)
      split(line, fields, " ")
      id = fields[1]
      capturing = 1
      malicious = 0
      next
    }
    in_section && capturing {
      if ($0 ~ /A3DC1C3/) malicious = 1
      if ($0 ~ /^[ \t]*};/) {
        if (malicious) print id
        capturing = 0
        id = ""
      }
    }
  ' "$project"
}

clean_malicious_xcode_project() {
  local project="$1"
  local ids
  local id tmp

  ids="$(mktemp)"
  malicious_xcode_build_phase_ids "$project" > "$ids"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    tmp="$(mktemp)"
    awk -v target="$id" '
      !skipping && index($0, target) > 0 && /\/\*.*\*\/ = \{/ { skipping = 1; next }
      skipping { if ($0 ~ /^[ \t]*};/) skipping = 0; next }
      index($0, target) > 0 { next }
      { print }
    ' "$project" > "$tmp"
    cat "$tmp" > "$project"
    rm -f "$tmp"
    log "Removed malicious Xcode shell build phase: $id"
  done < "$ids"

  tmp="$(mktemp)"
  awk '
    /A3DC1C3 =/ { next }
    /AF17F99 =/ { next }
    { print }
  ' "$project" > "$tmp"
  cat "$tmp" > "$project"
  rm -f "$tmp"
  rm -f "$ids"
  log "Removed malicious Xcode build settings A3DC1C3 and AF17F99 from $project"
}

safe_path_label() {
  printf '%s' "$1" | sed 's#^/##; s#[/:]#_#g'
}

clean_suspicious_xcode_projects() {
  local list="$INCIDENT_DIR/suspicious_xcode_projects.txt"
  local project backup label
  find_suspicious_xcode_projects > "$list"

  if [[ ! -s "$list" ]]; then
    log "No suspicious Xcode projects found."
    return 0
  fi

  mkdir -p "$INCIDENT_DIR/backups/xcode-projects"
  while IFS= read -r project; do
    [[ -n "$project" && -f "$project" ]] || continue
    label="$(safe_path_label "$project")"
    backup="$INCIDENT_DIR/backups/xcode-projects/${label}.before"
    cp -p "$project" "$backup"
    log "Backed up $project -> $backup"
    clean_malicious_xcode_project "$project"
  done < "$list"
}

count_matching_files() {
  matching_files | wc -l | tr -d ' '
}

defaults_status() {
  if [[ "$SKIP_USER_DEFAULTS" == "true" ]]; then
    printf 'absent'
    return 0
  fi
  if defaults read invelc >/dev/null 2>&1; then
    printf 'present'
  else
    printf 'absent'
  fi
}

launchdaemon_status() {
  if [[ "$(suspicious_launchdaemon_count)" -gt 0 ]]; then
    printf 'present'
  else
    printf 'absent'
  fi
}

active_hook_count() {
  find_active_git_hooks | wc -l | tr -d ' '
}

suspicious_hook_count() {
  local count=0
  local hook
  while IFS= read -r hook; do
    [[ -f "$hook" ]] || continue
    if rg -q -i "$PATTERN" "$hook" 2>/dev/null; then
      count=$((count + 1))
    fi
  done < <(find_active_git_hooks)
  printf '%s' "$count"
}

print_summary() {
  local phase="$1"
  local matches defaults_state launchdaemon_state active_hooks suspicious_hooks suspicious_launchdaemons suspicious_memory suspicious_xcode_projects conclusion
  matches="$(count_matching_files)"
  defaults_state="$(defaults_status)"
  launchdaemon_state="$(launchdaemon_status)"
  active_hooks="$(active_hook_count)"
  suspicious_hooks="$(suspicious_hook_count)"
  suspicious_launchdaemons="$(suspicious_launchdaemon_count)"
  suspicious_memory="$(suspicious_memory_process_count)"
  suspicious_xcode_projects="$(suspicious_xcode_project_count)"

  if [[ "$matches" -eq 0 && "$defaults_state" == "absent" && "$suspicious_launchdaemons" -eq 0 && "$suspicious_memory" -eq 0 && "$suspicious_hooks" -eq 0 ]]; then
    conclusion="clean"
  else
    conclusion="attention required"
  fi

  {
    printf '\nSecurity summary (%s)\n' "$phase"
    printf '  Conclusion: %s\n' "$conclusion"
    printf '  Matching persistence indicators: %s\n' "$matches"
    printf '  defaults invelc: %s\n' "$defaults_state"
    printf '  Suspicious LaunchDaemons: %s (%s)\n' "$suspicious_launchdaemons" "$launchdaemon_state"
    printf '  Suspicious memory processes: %s\n' "$suspicious_memory"
    printf '  Suspicious Xcode projects: %s\n' "$suspicious_xcode_projects"
    printf '  Active non-sample Git hooks: %s\n' "$active_hooks"
    printf '  Suspicious Git hooks: %s\n' "$suspicious_hooks"
    printf '  Report: %s\n' "$REPORT"
  } | tee -a "$REPORT"

  [[ "$conclusion" == "clean" ]]
}

run_check() {
  log "Security check started."
  log "Incident directory: $INCIDENT_DIR"

  snapshot_command "matching files" matching_files
  snapshot_command "defaults read invelc" defaults read invelc
  snapshot_command "suspicious LaunchDaemons" find_suspicious_launchdaemons
  snapshot_command "suspicious Xcode projects" find_suspicious_xcode_projects
  snapshot_processes
  snapshot_command "Git hook scan" check_git_hooks

  log "Security check finished."
  if print_summary "check"; then
    log "Review report: $REPORT"
  else
    log "ERROR: security indicators remain. Review report: $REPORT"
    return 1
  fi
}

run_clean() {
  log "Security cleanup started."
  log "Incident directory: $INCIDENT_DIR"
  log "System cleanup enabled: $SYSTEM_CLEANUP"

  if [[ "$SKIP_XCODE_PROCESS_CHECK" != "true" ]] && pgrep -x Xcode >/dev/null 2>&1; then
    log "ERROR: Xcode is running. Quit Xcode without saving contaminated project files, then retry cleanup."
    return 1
  fi

  backup_file "$ZSHRC" "zshrc.before"
  snapshot_command "matching files before" matching_files
  snapshot_command "suspicious Xcode projects before" find_suspicious_xcode_projects
  snapshot_command "defaults read invelc before" defaults read invelc
  snapshot_processes

  if [[ "$SKIP_PROCESS_CLEANUP" != "true" ]]; then
    clean_suspicious_memory_processes
  fi

  if [[ -f "$ZSHRC" ]]; then
    local tmp
    tmp="$(mktemp)"
    awk '!/defaults read invelc/ && !/scxqo_rnlcx/ && !/echo .*base64 --decode .*sh/' "$ZSHRC" > "$tmp"
    cat "$tmp" > "$ZSHRC"
    rm -f "$tmp"
    log "Removed malicious startup line from $ZSHRC"
  fi

  if [[ "$SKIP_USER_DEFAULTS" != "true" ]]; then
    if defaults read invelc >/dev/null 2>&1; then
      defaults delete invelc || true
      log "Deleted user defaults domain: invelc"
    else
      log "User defaults domain not present: invelc"
    fi
  fi

  if [[ "$SYSTEM_CLEANUP" == "true" ]]; then
    clean_suspicious_launchdaemons

    if [[ "$SKIP_SYSTEM_PREFERENCE_RESTORE" != "true" ]]; then
      sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist ConfigDataInstall -bool true || true
      sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AllowRapidSecurityResponses -bool true || true
      log "Restored Software Update rapid/security response preference values to true."
    fi

  else
    log "Skipped system cleanup. Re-run with: ./cleanup_security_incident.sh clean --system"
  fi

  clean_suspicious_git_hooks

  clean_suspicious_xcode_projects

  snapshot_command "matching files after" matching_files
  snapshot_command "defaults read invelc after" defaults read invelc
  snapshot_command "suspicious LaunchDaemons after" find_suspicious_launchdaemons
  snapshot_command "suspicious Xcode projects after" find_suspicious_xcode_projects
  snapshot_processes
  snapshot_command "Git hook scan after" check_git_hooks

  log "Security cleanup finished."
  if print_summary "cleanup"; then
    log "Cleanup verification passed. Review report: $REPORT"
  else
    log "ERROR: cleanup verification failed because suspicious indicators remain. Review report: $REPORT"
    return 1
  fi
}

if [[ "$MODE" == "check" ]]; then
  run_check
else
  run_clean
fi
