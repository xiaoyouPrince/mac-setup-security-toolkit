#!/usr/bin/env bash
set -euo pipefail

# Interactive entrypoint for the clean Mac setup scripts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

paint() {
  local color="$1"
  shift
  printf '%s%s%s' "$color" "$*" "$C_RESET"
}

status_color() {
  case "$1" in
    reachable|set|success|OK) printf '%s' "$C_GREEN" ;;
    unreachable|failed|MISS|ERROR) printf '%s' "$C_RED" ;;
    checking*|not\ set|WARN|warning) printf '%s' "$C_YELLOW" ;;
    *) printf '%s' "$C_RESET" ;;
  esac
}

print_status_line() {
  local label="$1"
  local value="$2"
  local color
  color="$(status_color "$value")"
  printf '  %s: %s%s%s\n' "$label" "$color" "$value" "$C_RESET"
}

die() {
  printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
  exit 1
}

pause() {
  printf '\n%sPress Enter to return to the menu...%s ' "$C_DIM" "$C_RESET"
  read -r _
}

confirm() {
  local prompt="$1"
  local answer

  printf '%s%s%s [y/N] ' "$C_YELLOW" "$prompt" "$C_RESET"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

script_path() {
  local script="$1"
  local path="$SCRIPT_DIR/$script"
  [[ -f "$path" ]] || die "Missing script: $path"
  printf '%s' "$path"
}

run_script() {
  local script="$1"
  shift

  local path
  path="$(script_path "$script")"

  printf '\n%s== Running %s ==%s\n\n' "$C_BLUE" "$script" "$C_RESET"
  if bash "$path" "$@"; then
    printf '\n%s== %s finished successfully ==%s\n' "$C_GREEN" "$script" "$C_RESET"
  else
    local status=$?
    printf '\n%s== %s failed with status %s ==%s\n' "$C_RED" "$script" "$status" "$C_RESET" >&2
  fi
  pause
}

run_security_incident_check() {
  run_script "cleanup_security_incident.sh" check
}

run_security_incident_clean_user() {
  if confirm "This will remove known user/project malware persistence after backing up files. Continue?"; then
    run_script "cleanup_security_incident.sh" clean
  fi
}

run_security_incident_clean_system() {
  if confirm "This may ask for sudo and remove system LaunchDaemons matching known malicious payload traits. Continue?"; then
    run_script "cleanup_security_incident.sh" clean --system
  fi
}

run_setup_shell_proxy() {
  local path
  path="$(script_path "setup_shell_proxy.sh")"

  printf '\n%s== Running setup_shell_proxy.sh ==%s\n\n' "$C_BLUE" "$C_RESET"
  if bash "$path"; then
    printf '\n%s== setup_shell_proxy.sh finished successfully ==%s\n' "$C_GREEN" "$C_RESET"
    printf '\n%sTo use the proxy for Homebrew cask downloads in this terminal:%s\n' "$C_YELLOW" "$C_RESET"
    printf '  1. Quit this menu with 0\n'
    printf '  2. Run: %ssource ~/.zshrc%s\n' "$C_CYAN" "$C_RESET"
    printf '  3. Run: %sproxy_on 7890%s\n' "$C_CYAN" "$C_RESET"
    printf '  4. Run: %s./start.sh%s and choose %s2%s\n' "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
  else
    local status=$?
    printf '\n%s== setup_shell_proxy.sh failed with status %s ==%s\n' "$C_RED" "$status" "$C_RESET" >&2
  fi
  pause
}

run_install_base_env() {
  local path
  path="$(script_path "install_base_env.sh")"

  local git_name=""
  local git_email=""

  if confirm "Set global Git user.name and user.email during install?"; then
    printf '%sGit user.name:%s ' "$C_CYAN" "$C_RESET"
    read -r git_name
    printf '%sGit user.email:%s ' "$C_CYAN" "$C_RESET"
    read -r git_email
  fi

  printf '\n%s== Running install_base_env.sh ==%s\n\n' "$C_BLUE" "$C_RESET"
  if [[ -n "$git_name" || -n "$git_email" ]]; then
    if GIT_USER_NAME="$git_name" GIT_USER_EMAIL="$git_email" bash "$path"; then
      printf '\n%s== install_base_env.sh finished successfully ==%s\n' "$C_GREEN" "$C_RESET"
    else
      local status=$?
      printf '\n%s== install_base_env.sh failed with status %s ==%s\n' "$C_RED" "$status" "$C_RESET" >&2
    fi
  else
    if bash "$path"; then
      printf '\n%s== install_base_env.sh finished successfully ==%s\n' "$C_GREEN" "$C_RESET"
    else
      local status=$?
      printf '\n%s== install_base_env.sh failed with status %s ==%s\n' "$C_RED" "$status" "$C_RESET" >&2
    fi
  fi
  pause
}

show_docs() {
  printf '\n%sManual checklists:%s\n' "$C_BOLD" "$C_RESET"
  printf '  %s%s%s\n' "$C_CYAN" "$SCRIPT_DIR/README.md" "$C_RESET"
  printf '  %s%s%s\n' "$C_CYAN" "$SCRIPT_DIR/ACCOUNT_SECURITY.md" "$C_RESET"
  printf '  %s%s%s\n' "$C_CYAN" "$SCRIPT_DIR/MIGRATION_CHECKLIST.md" "$C_RESET"
  pause
}

show_action_help() {
  cat <<'EOF'

Action guide
============

1) Install or refresh shell proxy helpers
   Script: setup_shell_proxy.sh
   What it does:
     - Writes ~/.config/new-mac/proxy.zsh.
     - Adds a loader line to ~/.zshrc and ~/.zprofile if missing.
     - Provides proxy_set, proxy_on, proxy_off, proxy_status, proxy_test,
       git_proxy_on, git_proxy_off, and git_proxy_status.
   Existing installs:
     - Rewrites ~/.config/new-mac/proxy.zsh.
     - Does not duplicate the loader line.
   After running:
     - Quit this menu, run `source ~/.zshrc`, then run `proxy_on <port>`.
     - Run ./start.sh again and choose 2 for base environment install.

2) Install base environment
   Script: install_base_env.sh
   What it does:
     - Checks Apple Silicon, Xcode, Brewfile, and Homebrew installer network access.
       If GitHub raw is unreachable, it can fall back to the Tsinghua Homebrew mirror.
     - Initializes Xcode command line tools.
     - Installs or updates Homebrew.
     - Installs Brewfile CLI tools and apps.
     - Installs Oh My Zsh when missing.
     - Sets Oh My Zsh theme/plugins and basic Git defaults.
     - Prints key tool versions.
   Existing installs:
     - Homebrew is updated, not reinstalled.
     - Brewfile packages are installed when missing; installed items are usually skipped by Homebrew.
     - Existing Oh My Zsh is not reinstalled.
     - ~/.zshrc ZSH_THEME and plugins lines may be replaced.
     - Git global defaults are overwritten.
   Does not:
     - Set shell proxy helpers.
     - Generate SSH keys.
     - Scan or clean Git hooks.

3) Generate SSH keys
   Script: setup_ssh_keys.sh
   What it does:
     - Creates a date-stamped GitHub ed25519 key when missing.
     - Adds SSH config entries.
     - Copies the public key to clipboard when pbcopy is available.
     - Optionally generates a GitLab/company key.
   Existing installs:
     - Existing key files with the same date-stamped path are not overwritten.
   Does not:
     - Upload keys to GitHub/GitLab.
     - Delete old SSH keys or tokens.

4) Run security verification
   Script: verify_security.sh
   What it does:
     - Reports system, Xcode, CLI tools, key versions, SSH public keys,
       known suspicious launch items/processes, hosts IOCs, and executable Git hooks.
   Existing installs:
     - Read-only. It does not delete or quarantine anything.

5) Scan Git hooks (dry run)
   Script: scan_git_hooks.sh
   What it does:
     - Scans ~/Documents, ~/Desktop, and ~/Downloads for Git hooks.
     - Writes a logs/git-hooks report directory with repositories, all hooks,
       suspicious hooks, and suspicious hook details.
   Existing installs:
     - Read-only. Nothing is changed.
   Requires:
     - rg from ripgrep. Install with: brew install ripgrep

6) Quarantine suspicious Git hooks
   Script: scan_git_hooks.sh --apply
   What it does:
     - Copies suspicious hooks into the report quarantine directory.
     - Removes those suspicious hook files from their repositories.
   Safety:
     - This modifies files. start.sh asks for confirmation first.

7) Quarantine all non-sample Git hooks
   Script: scan_git_hooks.sh --apply --remove-all-hooks
   What it does:
     - Copies every non-sample Git hook into quarantine.
     - Removes every non-sample hook from scanned repositories.
   Safety:
     - This is the most aggressive cleanup option.
     - It modifies files. start.sh asks for confirmation first.

8) Show manual checklist paths
   What it does:
     - Prints README.md, ACCOUNT_SECURITY.md, and MIGRATION_CHECKLIST.md paths.
   Existing installs:
     - Read-only.

9) Security incident check (read-only)
   Script: cleanup_security_incident.sh check
   What it does:
     - Checks shell startup files, defaults invelc, suspicious LaunchDaemon payload traits,
       self-deleting temporary AppleScript/native processes, Git hooks,
       and known malicious indicators in every discovered Xcode project.
     - Prints a terminal summary with the overall conclusion.
     - Writes a timestamped logs/security-incidents/security_incident_*/cleanup_report.txt.
     - Returns a non-zero status when suspicious indicators remain.
   Existing installs:
     - Read-only. It does not delete or modify anything.

10) Clean user/project incident artifacts
   Script: cleanup_security_incident.sh clean
   What it does:
     - Backs up affected files into logs/security-incidents/security_incident_*/backups/.
     - Removes known malicious ~/.zshrc payload lines.
     - Deletes defaults domain invelc.
     - Scans Documents/Desktop/Downloads and quarantines every suspicious Git hook.
     - Terminates known /tmp AppleScript/native memory payload shapes.
     - Scans every project.pbxproj under Documents/Desktop/Downloads.
     - Separately backs up each affected project, then removes the complete Xcode
       shell build phase/build rule that loads known malicious payloads and the A3DC1C3/AF17F99 settings.
     - Re-scans after cleanup and returns a non-zero status if indicators remain.
   Safety:
     - This modifies user/project files. start.sh asks for confirmation first.
     - It does not run sudo and does not modify /Library.
     - Xcode must be closed first so stale in-memory project state cannot be saved back.

11) Clean system incident artifacts
   Script: cleanup_security_incident.sh clean --system
   What it does:
     - Performs everything in option 10.
     - Finds LaunchDaemons by known IOC plus shell-execution traits, or by an
       obfuscated Base64-to-shell payload shape, instead of relying on one filename.
     - Backs up, unloads, and removes every matching LaunchDaemon.
     - Restores Software Update rapid/security response preference values.
     - Attempts to kill matching suspicious processes.
     - Re-scans after cleanup and fails when suspicious indicators remain.
   Safety:
     - This may ask for sudo in your terminal.
     - Type your password only into the terminal prompt, never into chat.

Output colors
   What they mean:
     - Green: success, reachable services, OK checks.
     - Yellow: warnings, prompts, recommended next steps.
     - Red: errors, failed commands, missing required items, aggressive actions.
     - Blue: current steps.
     - Cyan: paths, commands, and selectable values.
   Disable colors:
     - Run: NO_COLOR=1 ./start.sh

0) Quit
   Exits this menu.

EOF
  pause
}

print_network_status() {
  local proxy_status="not set"
  local github_status="unreachable"
  local mirror_status="unreachable"

  printf '%sNetwork status%s\n' "$C_BOLD" "$C_RESET"
  print_status_line "Shell proxy" "checking local environment..."
  if [[ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${all_proxy:-}${ALL_PROXY:-}" ]]; then
    proxy_status="set"
  fi

  print_status_line "GitHub raw" "checking HTTPS access..."
  if curl -fsSI --connect-timeout 3 --max-time 6 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh >/dev/null 2>&1; then
    github_status="reachable"
  fi

  print_status_line "TUNA Homebrew mirror" "checking Git access..."
  if git ls-remote https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git HEAD >/dev/null 2>&1; then
    mirror_status="reachable"
  fi

  printf '\n'
  printf '%sNetwork status%s\n' "$C_BOLD" "$C_RESET"
  print_status_line "Shell proxy" "$proxy_status"
  print_status_line "GitHub raw" "$github_status"
  print_status_line "TUNA Homebrew mirror" "$mirror_status"
  printf '\n'

  if [[ "$proxy_status" == "not set" ]]; then
    printf '%sNetwork note:%s base install and cask downloads may need a shell proxy.\n' "$C_YELLOW" "$C_RESET"
    printf '%sRecommended first step:%s choose %s1%s, then quit and run %ssource ~/.zshrc && proxy_on <port>%s.\n\n' "$C_YELLOW" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
  fi
}

show_menu() {
  clear 2>/dev/null || true
  printf '%sClean Mac setup%s\n' "$C_BOLD" "$C_RESET"
  printf '%s================%s\n\n' "$C_DIM" "$C_RESET"
  print_network_status
  printf '%s1%s) Install or refresh shell proxy helpers\n' "$C_CYAN" "$C_RESET"
  printf '%s2%s) Install base environment\n' "$C_CYAN" "$C_RESET"
  printf '%s3%s) Generate SSH keys\n' "$C_CYAN" "$C_RESET"
  printf '%s4%s) Run security verification\n' "$C_CYAN" "$C_RESET"
  printf '%s5%s) Scan Git hooks (dry run)\n' "$C_CYAN" "$C_RESET"
  printf '%s6%s) Quarantine suspicious Git hooks\n' "$C_YELLOW" "$C_RESET"
  printf '%s7%s) Quarantine all non-sample Git hooks\n' "$C_RED" "$C_RESET"
  printf '%s8%s) Show manual checklist paths\n' "$C_CYAN" "$C_RESET"
  printf '%s9%s) Security incident check (read-only)\n' "$C_CYAN" "$C_RESET"
  printf '%s10%s) Clean user/project incident artifacts\n' "$C_YELLOW" "$C_RESET"
  printf '%s11%s) Clean system incident artifacts (sudo)\n' "$C_RED" "$C_RESET"
  printf '%s12%s) Explain actions and rules\n' "$C_CYAN" "$C_RESET"
  printf '%s0%s) Quit\n\n' "$C_DIM" "$C_RESET"
  printf '%sChoose an action:%s ' "$C_BOLD" "$C_RESET"
}

main() {
  while true; do
    show_menu
    local choice
    read -r choice

    case "$choice" in
      1)
        run_setup_shell_proxy
        ;;
      2)
        run_install_base_env
        ;;
      3)
        run_script "setup_ssh_keys.sh"
        ;;
      4)
        run_script "verify_security.sh"
        ;;
      5)
        run_script "scan_git_hooks.sh"
        ;;
      6)
        if confirm "This will quarantine suspicious Git hooks. Continue?"; then
          run_script "scan_git_hooks.sh" --apply
        fi
        ;;
      7)
        if confirm "This will quarantine every non-sample Git hook under Documents/Desktop/Downloads. Continue?"; then
          run_script "scan_git_hooks.sh" --apply --remove-all-hooks
        fi
        ;;
      8)
        show_docs
        ;;
      9)
        run_security_incident_check
        ;;
      10)
        run_security_incident_clean_user
        ;;
      11)
        run_security_incident_clean_system
        ;;
      12|h|H|help)
        show_action_help
        ;;
      0|q|Q)
        printf '%sBye.%s\n' "$C_DIM" "$C_RESET"
        exit 0
        ;;
      *)
        printf '\n%sUnknown choice:%s %s\n' "$C_RED" "$C_RESET" "$choice"
        pause
        ;;
    esac
  done
}

main "$@"
