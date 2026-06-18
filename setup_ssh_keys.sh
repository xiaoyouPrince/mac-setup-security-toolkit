#!/usr/bin/env bash
set -euo pipefail

# Generate fresh SSH keys for Git services on the clean Mac.
# This script never deletes old keys and never uploads keys to GitHub/GitLab.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs/install}"
LOG_FILE="$LOG_DIR/ssh_keys_$(date +%Y%m%d_%H%M%S).log"
KEY_DATE="$(date +%Y%m%d)"

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
    ERROR:*|*failed*) printf '%s' "$C_RED" ;;
    *already*|Please*) printf '%s' "$C_YELLOW" ;;
    *successfully*|*Added*|*created*|*Copied*) printf '%s' "$C_GREEN" ;;
    Log\ file:*|Complete\ execution\ log:*) printf '%s' "$C_CYAN" ;;
    *) printf '%s' "$C_BLUE" ;;
  esac
}

log() {
  local msg="$*"
  local color
  color="$(log_color "$msg")"
  printf '%s[%s]%s %s%s%s\n' "$C_DIM" "$(date '+%F %T')" "$C_RESET" "$color" "$msg" "$C_RESET"
}

die() {
  log "ERROR: $*"
  exit 1
}

prompt_yes_no() {
  local prompt="$1"
  local default="$2"
  local answer

  while true; do
    printf '%s%s%s ' "$C_YELLOW" "$prompt" "$C_RESET" >&2
    read -r answer
    answer="${answer:-$default}"
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf '%sPlease answer y or n.%s\n' "$C_RED" "$C_RESET" >&2 ;;
    esac
  done
}

ensure_log() {
  mkdir -p "$LOG_DIR"
  exec > >(tee -a "$LOG_FILE") 2>&1
  log "Log file: $LOG_FILE"
}

finish() {
  local status=$?
  if [[ "$status" -eq 0 ]]; then
    log "SSH key setup finished successfully."
  else
    log "SSH key setup failed with status: $status"
  fi
  log "Complete execution log: $LOG_FILE"
}

ensure_ssh_dir() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"
}

append_host_config_once() {
  local host="$1"
  local hostname="$2"
  local user="$3"
  local key_path="$4"

  if grep -q "IdentityFile $key_path" "$HOME/.ssh/config"; then
    log "SSH config already references: $key_path"
    return 0
  fi

  {
    printf '\nHost %s\n' "$host"
    printf '    HostName %s\n' "$hostname"
    printf '    User %s\n' "$user"
    printf '    IdentityFile %s\n' "$key_path"
    printf '    IdentitiesOnly yes\n'
  } >> "$HOME/.ssh/config"

  log "Added SSH config host: $host"
}

generate_key() {
  local service="$1"
  local key_path="$2"
  local comment="$3"

  if [[ -f "$key_path" ]]; then
    log "Key already exists, not overwriting: $key_path"
  else
    ssh-keygen -t ed25519 -a 100 -C "$comment" -f "$key_path" -N ""
    log "Generated key: $key_path"
  fi

  chmod 600 "$key_path"
  chmod 644 "$key_path.pub"
  ssh-keygen -lf "$key_path.pub"

  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy < "$key_path.pub"
    log "$service public key copied to clipboard."
  else
    log "$service public key:"
    sed -n '1p' "$key_path.pub"
  fi
}

main() {
  ensure_log
  trap finish EXIT
  ensure_ssh_dir

  local github_key="$HOME/.ssh/github_ed25519_${KEY_DATE}"
  generate_key "GitHub" "$github_key" "github-${KEY_DATE}-clean"
  append_host_config_once "github.com" "github.com" "git" "$github_key"

  log "Add the GitHub public key here:"
  log "https://github.com/settings/keys"
  log "Then remove old GitHub SSH keys and revoke old tokens:"
  log "https://github.com/settings/tokens"
  log "https://github.com/settings/personal-access-tokens"
  log "https://github.com/settings/applications"

  if prompt_yes_no "Generate a separate GitLab/company Git key too? [y/N]" "n"; then
    local gitlab_host
    local gitlab_key
    printf 'GitLab/company host. Default: gitlab.com: ' >&2
    read -r gitlab_host
    gitlab_host="${gitlab_host:-gitlab.com}"
    gitlab_key="$HOME/.ssh/gitlab_ed25519_${KEY_DATE}"

    generate_key "GitLab" "$gitlab_key" "gitlab-${KEY_DATE}-clean"
    append_host_config_once "$gitlab_host" "$gitlab_host" "git" "$gitlab_key"

    log "Add the GitLab/company public key in that service's SSH key settings."
    log "Then remove old GitLab/company keys and revoke old access tokens."
  fi

  log "After adding keys online, test:"
  log "ssh -T git@github.com"
}

main "$@"
