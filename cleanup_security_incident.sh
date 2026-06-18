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
      ~/.zshrc payload, defaults domain invelc, XYDevTool hook, and
      malicious Xcode project build settings.

  ./cleanup_security_incident.sh clean --system
      Also unload/remove the known system LaunchDaemon and restore
      Software Update security response preference values. Requires sudo.
EOF
    exit 2
    ;;
esac

INCIDENT_ROOT="${INCIDENT_ROOT:-$SCRIPT_DIR/logs/security-incidents}"
INCIDENT_DIR="${INCIDENT_DIR:-$INCIDENT_ROOT/security_incident_$(date +%Y%m%d_%H%M%S)}"
REPORT="$INCIDENT_DIR/cleanup_report.txt"
ZSHRC="$HOME/.zshrc"
LAUNCHD_PLIST="/Library/LaunchDaemons/com.google.rqbcle.plist"
XY_REPO="$HOME/Documents/GitHub/XYDevTool"
XY_HOOK="$XY_REPO/.git/hooks/pre-commit"
XY_PROJECT="$XY_REPO/XYDevTool/XYDevTool.xcodeproj/project.pbxproj"
SHELL_FILES=(
  "$HOME/.zshrc"
  "$HOME/.zprofile"
  "$HOME/.zshenv"
  "$HOME/.zlogin"
  "$HOME/.bashrc"
  "$HOME/.bash_profile"
)
PERSISTENCE_PATHS=(
  /Library/LaunchDaemons
  /Library/LaunchAgents
  "$HOME/Library/LaunchAgents"
)
PATTERN='invelc|scxqo|qnnx|netcdn|rigacdn|cdnatapple|amzndev|netcdnamz|amznprod|base64 --decode|xxd -p -r|curl .*\| sh|curl .* -d "p='
PROCESS_PATTERN='invelc|scxqo|qnnx|netcdn|rigacdn|cdnatapple|amzndev|netcdnamz|amznprod|com.google.rqbcle|CloudTelemetryService'

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
    printf '\n== matching processes ==\n'
    if ! pgrep -af "$PROCESS_PATTERN" 2>&1; then
      printf 'Process enumeration unavailable or no matching process found. This check is best-effort.\n'
    fi
  } >> "$REPORT"
}

matching_files() {
  local paths=()
  local path
  for path in "${SHELL_FILES[@]}" "${PERSISTENCE_PATHS[@]}" "$XY_REPO"; do
    [[ -e "$path" ]] && paths+=("$path")
  done

  if [[ "${#paths[@]}" -eq 0 ]]; then
    return 0
  fi

  rg -n -i "$PATTERN" "${paths[@]}" 2>/dev/null || true
}

check_git_hooks() {
  if [[ -x "$SCRIPT_DIR/scan_git_hooks.sh" ]]; then
    bash "$SCRIPT_DIR/scan_git_hooks.sh"
  else
    find "$HOME/Documents" "$HOME/Desktop" "$HOME/Downloads" -path '*/.git/hooks/*' -type f ! -name '*.sample' -print 2>/dev/null || true
  fi
}

run_check() {
  log "Security check started."
  log "Incident directory: $INCIDENT_DIR"

  snapshot_command "matching files" matching_files
  snapshot_command "defaults read invelc" defaults read invelc
  snapshot_command "LaunchDaemon file" ls -l "$LAUNCHD_PLIST"
  snapshot_command "LaunchDaemon registration" launchctl print system/com.google.rqbcle
  snapshot_processes
  snapshot_command "Git hook scan" check_git_hooks

  log "Security check finished."
  log "Review report: $REPORT"
}

run_clean() {
  log "Security cleanup started."
  log "Incident directory: $INCIDENT_DIR"
  log "System cleanup enabled: $SYSTEM_CLEANUP"

  backup_file "$ZSHRC" "zshrc.before"
  backup_file "$LAUNCHD_PLIST" "com.google.rqbcle.plist.before"
  backup_file "$XY_HOOK" "XYDevTool.git-hooks-pre-commit.before"
  backup_file "$XY_PROJECT" "XYDevTool.project.pbxproj.before"
  snapshot_command "matching files before" matching_files
  snapshot_command "defaults read invelc before" defaults read invelc
  snapshot_processes

  if [[ -f "$ZSHRC" ]]; then
    local tmp
    tmp="$(mktemp)"
    awk '!/defaults read invelc/ && !/scxqo_rnlcx/ && !/echo .*base64 --decode .*sh/' "$ZSHRC" > "$tmp"
    cat "$tmp" > "$ZSHRC"
    rm -f "$tmp"
    log "Removed malicious startup line from $ZSHRC"
  fi

  if defaults read invelc >/dev/null 2>&1; then
    defaults delete invelc || true
    log "Deleted user defaults domain: invelc"
  else
    log "User defaults domain not present: invelc"
  fi

  if [[ "$SYSTEM_CLEANUP" == "true" ]]; then
    if [[ -f "$LAUNCHD_PLIST" ]]; then
      sudo launchctl bootout system "$LAUNCHD_PLIST" >/dev/null 2>&1 || true
      sudo rm -f "$LAUNCHD_PLIST"
      log "Unloaded and removed $LAUNCHD_PLIST"
    else
      log "System LaunchDaemon not present: $LAUNCHD_PLIST"
    fi

    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist ConfigDataInstall -bool true || true
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AllowRapidSecurityResponses -bool true || true
    log "Restored Software Update rapid/security response preference values to true."

    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      sudo kill -9 "$pid" >/dev/null 2>&1 || true
      log "Killed matching process PID $pid"
    done < <(pgrep -f "$PROCESS_PATTERN" || true)
  else
    log "Skipped system cleanup. Re-run with: ./cleanup_security_incident.sh clean --system"
  fi

  if [[ -f "$XY_HOOK" ]]; then
    if rg -q -i "$PATTERN" "$XY_HOOK" 2>/dev/null; then
      rm -f "$XY_HOOK"
      log "Removed malicious Git hook: $XY_HOOK"
    else
      log "Git hook exists but did not match malicious pattern: $XY_HOOK"
    fi
  fi

  if [[ -f "$XY_PROJECT" ]]; then
    local tmp
    tmp="$(mktemp)"
    awk '
      /A3DC1C3 = "\(\(/ { next }
      /AF17F99 = "\(\(/ { next }
      { print }
    ' "$XY_PROJECT" > "$tmp"
    cat "$tmp" > "$XY_PROJECT"
    rm -f "$tmp"
    log "Removed malicious Xcode build settings A3DC1C3 and AF17F99 from $XY_PROJECT"
  fi

  snapshot_command "matching files after" matching_files
  snapshot_command "defaults read invelc after" defaults read invelc
  snapshot_command "LaunchDaemon file after" ls -l "$LAUNCHD_PLIST"
  snapshot_command "LaunchDaemon registration after" launchctl print system/com.google.rqbcle
  snapshot_processes
  snapshot_command "Git hook scan after" check_git_hooks

  log "Security cleanup finished."
  log "Review report: $REPORT"
}

if [[ "$MODE" == "check" ]]; then
  run_check
else
  run_clean
fi
