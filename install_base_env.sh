#!/usr/bin/env bash
set -euo pipefail

# Base environment installer for a clean Apple Silicon Mac.
#
# Preconditions are documented in README.md:
# 1. Trackpad settings are configured manually.
# 2. Xcode is installed manually from the App Store and opened once.
# 3. VPN/proxy or a reachable Homebrew mirror is configured.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$SCRIPT_DIR/Brewfile"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs/install}"
LOG_FILE="$LOG_DIR/base_env_$(date +%Y%m%d_%H%M%S).log"
HOMEBREW_INSTALL_FROM="${HOMEBREW_INSTALL_FROM:-auto}"
HOMEBREW_OFFICIAL_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
HOMEBREW_TUNA_INSTALL_GIT="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git"
HOMEBREW_TUNA_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
HOMEBREW_TUNA_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
HOMEBREW_TUNA_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
OH_MY_ZSH_INSTALL_URLS=(
  "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
  "https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh"
)
DOWNLOADED_URL=""

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
    WARN:*|No\ shell\ proxy*|If\ cask*) printf '%s' "$C_YELLOW" ;;
    *successfully*|*passed*|*reachable*) printf '%s' "$C_GREEN" ;;
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

ensure_log() {
  mkdir -p "$LOG_DIR"
  exec > >(tee -a "$LOG_FILE") 2>&1
  log "Log file: $LOG_FILE"
}

finish() {
  local status=$?
  if [[ "$status" -eq 0 ]]; then
    log "Base environment install finished successfully."
  else
    log "Base environment install failed with status: $status"
  fi
  log "Complete execution log: $LOG_FILE"
}

have_brew() {
  command -v brew >/dev/null 2>&1 || [[ -x /opt/homebrew/bin/brew ]] || [[ -x /usr/local/bin/brew ]]
}

load_brew_env() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

curl_head_ok() {
  curl -fsSI --connect-timeout 8 --max-time 20 "$1" >/dev/null 2>&1
}

download_first_available() {
  local output="$1"
  shift

  local url
  for url in "$@"; do
    log "Trying download: $url"
    if curl -fsSL --connect-timeout 8 --max-time 60 "$url" -o "$output"; then
      DOWNLOADED_URL="$url"
      return 0
    fi
  done

  return 1
}

append_once() {
  local file="$1"
  local marker="$2"
  local line="$3"

  touch "$file"
  if ! grep -Fq "$marker" "$file"; then
    {
      printf '\n%s\n' "$marker"
      printf '%s\n' "$line"
    } >> "$file"
  fi
}

should_use_tuna_homebrew() {
  case "$HOMEBREW_INSTALL_FROM" in
    tuna) return 0 ;;
    auto)
      ! curl_head_ok "$HOMEBREW_OFFICIAL_INSTALL_URL"
      ;;
    *) return 1 ;;
  esac
}

configure_tuna_homebrew_mirror() {
  log "Using Tsinghua Homebrew mirror for brew git/API/bottles."
  export HOMEBREW_BREW_GIT_REMOTE="$HOMEBREW_TUNA_BREW_GIT_REMOTE"
  export HOMEBREW_API_DOMAIN="$HOMEBREW_TUNA_API_DOMAIN"
  export HOMEBREW_BOTTLE_DOMAIN="$HOMEBREW_TUNA_BOTTLE_DOMAIN"

  append_once "$HOME/.zprofile" "# Homebrew TUNA mirror" "export HOMEBREW_BREW_GIT_REMOTE=\"$HOMEBREW_TUNA_BREW_GIT_REMOTE\""
  append_once "$HOME/.zprofile" "# Homebrew TUNA API mirror" "export HOMEBREW_API_DOMAIN=\"$HOMEBREW_TUNA_API_DOMAIN\""
  append_once "$HOME/.zprofile" "# Homebrew TUNA bottle mirror" "export HOMEBREW_BOTTLE_DOMAIN=\"$HOMEBREW_TUNA_BOTTLE_DOMAIN\""

  if have_brew; then
    load_brew_env
    git -C "$(brew --repo)" remote set-url origin "$HOMEBREW_TUNA_BREW_GIT_REMOTE" || true
  fi
}

preflight() {
  log "Running preflight checks..."

  [[ "$(uname -m)" == "arm64" ]] || die "This script is intended for Apple Silicon Macs."
  [[ -d /Applications/Xcode.app ]] || die "Xcode.app not found. Install Xcode from the App Store first."
  [[ -d "$XCODE_DEVELOPER_DIR" ]] || die "Xcode developer directory not found: $XCODE_DEVELOPER_DIR"
  [[ -f "$BREWFILE" ]] || die "Missing Brewfile: $BREWFILE"

  if xcode-select -p >/dev/null 2>&1; then
    log "Current developer directory: $(xcode-select -p)"
  else
    log "Current developer directory is not configured yet."
  fi
  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild -version

  log "Checking Homebrew installer network access..."
  case "$HOMEBREW_INSTALL_FROM" in
    auto)
      if curl_head_ok "$HOMEBREW_OFFICIAL_INSTALL_URL"; then
        log "GitHub raw is reachable."
      elif git ls-remote "$HOMEBREW_TUNA_INSTALL_GIT" HEAD >/dev/null 2>&1; then
        log "GitHub raw is unreachable; Tsinghua Homebrew mirror is reachable."
      else
        die "Cannot reach GitHub raw or Tsinghua Homebrew mirror. Enable VPN/proxy or set HOMEBREW_INSTALL_FROM=github/tuna, then rerun this script."
      fi
      ;;
    github)
      curl_head_ok "$HOMEBREW_OFFICIAL_INSTALL_URL" \
        || die "Cannot reach GitHub raw. Enable VPN/proxy first, or rerun with HOMEBREW_INSTALL_FROM=tuna."
      ;;
    tuna)
      git ls-remote "$HOMEBREW_TUNA_INSTALL_GIT" HEAD >/dev/null 2>&1 \
        || die "Cannot reach Tsinghua Homebrew mirror. Enable VPN/proxy first, or rerun with HOMEBREW_INSTALL_FROM=github."
      ;;
    *)
      die "Invalid HOMEBREW_INSTALL_FROM=$HOMEBREW_INSTALL_FROM. Use auto, github, or tuna."
      ;;
  esac

  log "Preflight checks passed."
}

init_xcode_cli() {
  log "Initializing Xcode command line environment..."
  sudo xcode-select -s "$XCODE_DEVELOPER_DIR"
  sudo xcodebuild -license accept || true
  sudo xcodebuild -runFirstLaunch || true
  xcode-select -p
  xcodebuild -version
}

install_homebrew() {
  log "Setting up Homebrew..."

  if should_use_tuna_homebrew; then
    configure_tuna_homebrew_mirror
  fi

  if have_brew; then
    load_brew_env
    log "Homebrew already installed: $(command -v brew)"
    brew update
  else
    log "Installing Homebrew from $HOMEBREW_INSTALL_FROM..."
    install_homebrew_fresh
    load_brew_env
  fi

  command -v brew >/dev/null 2>&1 || die "brew is still unavailable after installation."

  append_once "$HOME/.zprofile" "# Homebrew" 'if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi'

  brew --version
  brew doctor || true
}

install_homebrew_fresh() {
  if [[ "$HOMEBREW_INSTALL_FROM" == "github" ]]; then
    install_homebrew_from_github
    return
  fi

  if [[ "$HOMEBREW_INSTALL_FROM" == "tuna" ]]; then
    install_homebrew_from_tuna
    return
  fi

  if curl_head_ok "$HOMEBREW_OFFICIAL_INSTALL_URL"; then
    install_homebrew_from_github
  else
    log "GitHub raw is unavailable; falling back to Tsinghua Homebrew mirror."
    install_homebrew_from_tuna
  fi
}

install_homebrew_from_github() {
  local installer
  installer="$(mktemp)"
  download_first_available "$installer" "$HOMEBREW_OFFICIAL_INSTALL_URL" \
    || die "Failed to download Homebrew installer from GitHub raw."
  NONINTERACTIVE=1 /bin/bash "$installer"
}

install_homebrew_from_tuna() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  log "Cloning Homebrew installer mirror..."
  git clone --depth 1 "$HOMEBREW_TUNA_INSTALL_GIT" "$tmpdir/install"
  HOMEBREW_BREW_GIT_REMOTE="$HOMEBREW_TUNA_BREW_GIT_REMOTE" \
    NONINTERACTIVE=1 /bin/bash "$tmpdir/install/install.sh"
}

install_brew_packages() {
  log "Installing Brewfile packages..."
  load_brew_env
  warn_if_proxy_is_not_enabled_for_casks
  brew bundle --file "$BREWFILE"
}

warn_if_proxy_is_not_enabled_for_casks() {
  if [[ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${all_proxy:-}${ALL_PROXY:-}" ]]; then
    log "Proxy environment detected for Homebrew downloads."
    return
  fi

  log "No shell proxy environment detected."
  log "Homebrew formula bottles can use mirrors, but casks such as codex/google-chrome download from vendor sites."
  log "If cask fetching stalls or fails, quit this menu and run: source ~/.zshrc && proxy_on 7890 && ./start.sh"
}

install_oh_my_zsh() {
  log "Installing Oh My Zsh if needed..."

  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    log "Oh My Zsh already exists: ~/.oh-my-zsh"
  else
    local installer
    installer="$(mktemp)"
    download_first_available "$installer" "${OH_MY_ZSH_INSTALL_URLS[@]}" \
      || die "Failed to download Oh My Zsh installer from GitHub raw or mirror."
    if [[ "$DOWNLOADED_URL" == https://gitee.com/* ]]; then
      RUNZSH=no CHSH=no KEEP_ZSHRC=yes REMOTE="https://gitee.com/mirrors/oh-my-zsh.git" sh "$installer"
    else
      RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$installer"
    fi
  fi

  touch "$HOME/.zshrc"

  if grep -q '^ZSH_THEME=' "$HOME/.zshrc"; then
    sed -i.bak 's/^ZSH_THEME=.*/ZSH_THEME="robbyrussell"/' "$HOME/.zshrc"
  else
    printf '\nZSH_THEME="robbyrussell"\n' >> "$HOME/.zshrc"
  fi

  if grep -q '^plugins=' "$HOME/.zshrc"; then
    sed -i.bak 's/^plugins=.*/plugins=(git)/' "$HOME/.zshrc"
  else
    printf '\nplugins=(git)\n' >> "$HOME/.zshrc"
  fi

  if ! grep -q 'source $ZSH/oh-my-zsh.sh' "$HOME/.zshrc"; then
    printf '\nexport ZSH="$HOME/.oh-my-zsh"\n' >> "$HOME/.zshrc"
    printf 'source $ZSH/oh-my-zsh.sh\n' >> "$HOME/.zshrc"
  fi
}

configure_git() {
  log "Configuring Git defaults..."
  git config --global init.defaultBranch main
  git config --global pull.ff only
  git config --global fetch.prune true
  git config --global credential.helper osxkeychain

  if [[ ! -f "$HOME/.gitignore_global" ]]; then
    {
      printf '.DS_Store\n'
      printf 'DerivedData/\n'
      printf 'node_modules/\n'
      printf 'Pods/\n'
    } > "$HOME/.gitignore_global"
  fi
  git config --global core.excludesfile "$HOME/.gitignore_global"

  if [[ -n "${GIT_USER_NAME:-}" ]]; then
    git config --global user.name "$GIT_USER_NAME"
  fi
  if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
    git config --global user.email "$GIT_USER_EMAIL"
  fi
}

verify_install() {
  log "Verifying installed environment..."
  xcodebuild -version
  git --version
  git lfs version
  node --version
  npm --version
  pod --version
  swiftlint version
  jq --version
  rg --version | sed -n '1p'
  tree --version
  tldr --version
  brew --version | sed -n '1p'
}

main() {
  ensure_log
  trap finish EXIT

  preflight
  init_xcode_cli
  install_homebrew
  install_brew_packages
  install_oh_my_zsh
  configure_git
  verify_install
}

main "$@"
