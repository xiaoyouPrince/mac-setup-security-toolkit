#!/usr/bin/env bash
set -euo pipefail

# Post-install verification for the clean Mac.
# This script only reports; it does not delete or quarantine anything.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs/install}"
LOG_FILE="$LOG_DIR/security_verify_$(date +%Y%m%d_%H%M%S).log"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
fi

log() {
  printf '%s[%s]%s %s%s%s\n' "$C_DIM" "$(date '+%F %T')" "$C_RESET" "$C_CYAN" "$*" "$C_RESET"
}

section() {
  printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_RESET"
}

ensure_log() {
  mkdir -p "$LOG_DIR"
  exec > >(tee -a "$LOG_FILE") 2>&1
  log "Log file: $LOG_FILE"
}

finish() {
  log "Security verification complete."
  log "Complete execution log: $LOG_FILE"
}

check_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%sOK%s   %s: %s\n' "$C_GREEN" "$C_RESET" "$cmd" "$(command -v "$cmd")"
  else
    printf '%sMISS%s %s\n' "$C_RED" "$C_RESET" "$cmd"
  fi
}

main() {
  ensure_log
  trap finish EXIT

  section "System"
  sw_vers || true
  printf 'arch: %s\n' "$(uname -m)"

  section "Xcode"
  [[ -d /Applications/Xcode.app ]] && printf '%sOK%s   /Applications/Xcode.app\n' "$C_GREEN" "$C_RESET" || printf '%sMISS%s /Applications/Xcode.app\n' "$C_RED" "$C_RESET"
  xcode-select -p 2>/dev/null || true
  xcodebuild -version 2>/dev/null || true
  swift --version 2>/dev/null || true

  section "CLI"
  for cmd in brew git git-lfs node npm pod swiftlint jq rg tree wget tmux tldr; do
    check_command "$cmd"
  done

  section "Key Versions"
  brew --version 2>/dev/null | sed -n '1p' || true
  git --version 2>/dev/null || true
  git lfs version 2>/dev/null || true
  node --version 2>/dev/null || true
  npm --version 2>/dev/null || true
  pod --version 2>/dev/null || true
  swiftlint version 2>/dev/null || true
  tldr --version 2>/dev/null || true

  section "SSH Public Keys"
  if [[ -d "$HOME/.ssh" ]]; then
    find "$HOME/.ssh" -maxdepth 1 -type f -name '*.pub' -print -exec ssh-keygen -lf {} \; 2>/dev/null || true
  else
    printf '%sMISS%s ~/.ssh\n' "$C_RED" "$C_RESET"
  fi

  section "Suspicious Launch Items"
  for p in \
    /Library/LaunchDaemons/com.google.qgbawz.plist \
    /Library/LaunchDaemons/com.google.lszufo.plist \
    "$HOME/Library/LaunchAgents/com.google.qgbawz.plist" \
    "$HOME/Library/LaunchAgents/com.google.lszufo.plist"
  do
    if [[ -e "$p" || -L "$p" ]]; then
      printf '%sWARN%s present: %s\n' "$C_YELLOW" "$C_RESET" "$p"
    else
      printf '%sOK%s   absent: %s\n' "$C_GREEN" "$C_RESET" "$p"
    fi
  done

  section "Suspicious Processes"
  ps ax -o pid,ppid,command | grep -E 'rigacdn|cdnatapple|netcdnamz|amznprod|/tmp/nq|C02GC2JYQ05P|qgbawz|lszufo|5da474|qnnx_reobnei|scxqo_rnlcx_xkn' | grep -v grep || true

  section "Hosts IOC Check"
  grep -E 'rigacdn|cdnatapple|netcdnamz|amznprod' /etc/hosts || true

  section "Executable Git Hooks"
  for root in "$HOME/Documents" "$HOME/Desktop" "$HOME/Downloads"; do
    [[ -d "$root" ]] || continue
    find "$root" -path '*/.git/hooks/*' -type f ! -name '*.sample' -print 2>/dev/null || true
  done

  section "Manual Security Tasks Still Required"
  printf '%s\n' \
    'Review ACCOUNT_SECURITY.md.' \
    'Delete old GitHub/GitLab SSH keys online.' \
    'Revoke old GitHub/GitLab tokens.' \
    'Review OAuth apps and active sessions.' \
    'Do not migrate old browser profiles, old ~/.ssh, or old token files.'
}

main "$@"
