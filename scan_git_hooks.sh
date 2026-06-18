#!/usr/bin/env bash
set -u

# Scan and optionally quarantine Git hook files under common user data roots.
# Default mode is dry-run.
#
# Usage:
#   ./scan_git_hooks.sh
#   ./scan_git_hooks.sh --apply
#   ./scan_git_hooks.sh --apply --remove-all-hooks

MODE="dry-run"
REMOVE_ALL_HOOKS="false"
ROOTS=(
  "$HOME/Documents"
  "$HOME/Desktop"
  "$HOME/Downloads"
)

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_ROOT="${REPORT_ROOT:-$SCRIPT_DIR/logs/git-hooks}"
REPORT_DIR="$REPORT_ROOT/git_hook_scan_$TIMESTAMP"
LOG="$REPORT_DIR/report.log"
REPO_LIST="$REPORT_DIR/git_repositories.txt"
SUSPICIOUS_LIST="$REPORT_DIR/suspicious_hooks.txt"
SUSPICIOUS_DETAILS="$REPORT_DIR/suspicious_hook_details.txt"
ALL_HOOKS_LIST="$REPORT_DIR/all_hooks.txt"
QUARANTINE_DIR="$REPORT_DIR/quarantined_hooks"
SUSPICIOUS_PATTERN='rigacdn|cdnatapple|netcdnamz|amznprod|base64 --decode|xxd -p -r|curl .*\| sh|curl .* -d "p=git"|/tmp/nq|qgbawz|lszufo|5da474|qnnx_reobnei|scxqo_rnlcx_xkn'

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
fi

log_color() {
  case "$1" in
    ERROR:*) printf '%s' "$C_RED" ;;
    WARN:*|*Suspicious*) printf '%s' "$C_YELLOW" ;;
    *complete*|*started*) printf '%s' "$C_GREEN" ;;
    Report\ directory:*|Mode:*|Remove\ all*) printf '%s' "$C_CYAN" ;;
    *) printf '%s' "$C_BLUE" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      MODE="apply"
      shift
      ;;
    --remove-all-hooks)
      REMOVE_ALL_HOOKS="true"
      shift
      ;;
    --report-dir)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --report-dir" >&2
        exit 2
      fi
      REPORT_DIR="$2"
      LOG="$REPORT_DIR/report.log"
      REPO_LIST="$REPORT_DIR/git_repositories.txt"
      SUSPICIOUS_LIST="$REPORT_DIR/suspicious_hooks.txt"
      SUSPICIOUS_DETAILS="$REPORT_DIR/suspicious_hook_details.txt"
      ALL_HOOKS_LIST="$REPORT_DIR/all_hooks.txt"
      QUARANTINE_DIR="$REPORT_DIR/quarantined_hooks"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$REPORT_DIR" "$QUARANTINE_DIR"

log() {
  local msg="$*"
  local color
  color="$(log_color "$msg")"
  printf '%s[%s]%s %s%s%s\n' "$C_DIM" "$(date '+%F %T')" "$C_RESET" "$color" "$msg" "$C_RESET" | tee -a "$LOG"
}

safe_name() {
  printf '%s' "$1" | sed 's#^/##; s#[/:]#_#g'
}

is_inside_old_malware_backup() {
  case "$1" in
    *"/malware-cleanup-backup-"*) return 0 ;;
    *"/malware_quarantine_"*) return 0 ;;
    *"/git_hook_scan_"*) return 0 ;;
    *) return 1 ;;
  esac
}

is_suspicious_hook() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  rg -q -i "$SUSPICIOUS_PATTERN" "$file" 2>/dev/null
}

write_suspicious_detail() {
  local file="$1"

  {
    printf '== %s ==\n' "$file"
    rg -n -i "$SUSPICIOUS_PATTERN" "$file" 2>/dev/null || true
    printf '\n'
  } >> "$SUSPICIOUS_DETAILS"
}

copy_and_remove() {
  local file="$1"
  local dst="$QUARANTINE_DIR/$(safe_name "$file")"
  mkdir -p "$(dirname "$dst")"
  cp -p "$file" "$dst" 2>>"$LOG" || log "WARN: failed to copy $file"
  rm -f "$file" 2>>"$LOG" || log "WARN: failed to remove $file"
}

log "Git hook scan started."
log "Mode: $MODE"
log "Remove all hooks: $REMOVE_ALL_HOOKS"
log "Report directory: $REPORT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  log "ERROR: ripgrep is required for Git hook scanning."
  log "Install it with: brew install ripgrep"
  log "It is also included in Brewfile and installed by install_base_env.sh."
  exit 1
fi

log "Finding Git repositories..."
: > "$REPO_LIST"
for root in "${ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  while IFS= read -r -d '' gitdir; do
    repo="${gitdir%/.git}"
    if is_inside_old_malware_backup "$repo"; then
      continue
    fi
    printf '%s\n' "$repo" >> "$REPO_LIST"
  done < <(find "$root" -path '*malware-cleanup-backup-*' -prune -o -path '*malware_quarantine_*' -prune -o -path '*git_hook_scan_*' -prune -o -name .git -type d -print0 2>/dev/null)
done
sort -u "$REPO_LIST" -o "$REPO_LIST"
log "Repository count: $(wc -l < "$REPO_LIST" | tr -d ' ')"

log "Scanning hook files..."
: > "$ALL_HOOKS_LIST"
: > "$SUSPICIOUS_LIST"
: > "$SUSPICIOUS_DETAILS"
while IFS= read -r repo; do
  hooks="$repo/.git/hooks"
  [[ -d "$hooks" ]] || continue
  while IFS= read -r -d '' hook; do
    printf '%s\n' "$hook" >> "$ALL_HOOKS_LIST"
    if [[ "$hook" != *.sample ]] && is_suspicious_hook "$hook"; then
      printf '%s\n' "$hook" >> "$SUSPICIOUS_LIST"
      write_suspicious_detail "$hook"
    fi
  done < <(find "$hooks" -maxdepth 1 -type f -print0 2>/dev/null)
done < "$REPO_LIST"

log "Hook file count: $(wc -l < "$ALL_HOOKS_LIST" | tr -d ' ')"
suspicious_count="$(wc -l < "$SUSPICIOUS_LIST" | tr -d ' ')"
log "Suspicious executable hook count: $suspicious_count"

if [[ "$suspicious_count" -gt 0 ]]; then
  log "Suspicious hook paths:"
  while IFS= read -r hook; do
    [[ -n "$hook" ]] || continue
    log "WARN: $hook"
  done < "$SUSPICIOUS_LIST"
  log "Review suspicious details: $SUSPICIOUS_DETAILS"
fi

if [[ "$MODE" == "dry-run" ]]; then
  log "Dry run only. Nothing was changed."
  log "Review: $REPO_LIST"
  log "Review: $ALL_HOOKS_LIST"
  log "Review: $SUSPICIOUS_LIST"
  log "Review: $SUSPICIOUS_DETAILS"
  log "Finished. Report directory: $REPORT_DIR"
  exit 0
fi

log "Applying cleanup of suspicious hooks..."
while IFS= read -r hook; do
  [[ -n "$hook" ]] || continue
  log "Quarantine suspicious hook: $hook"
  copy_and_remove "$hook"
done < "$SUSPICIOUS_LIST"

if [[ "$REMOVE_ALL_HOOKS" == "true" ]]; then
  log "Removing every non-sample hook from migration repositories..."
  while IFS= read -r hook; do
    [[ -n "$hook" ]] || continue
    [[ "$hook" == *.sample ]] && continue
    [[ -f "$hook" ]] || continue
    log "Quarantine non-sample hook: $hook"
    copy_and_remove "$hook"
  done < "$ALL_HOOKS_LIST"
fi

log "Finished. Report directory: $REPORT_DIR"
