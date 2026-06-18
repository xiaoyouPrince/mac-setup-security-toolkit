#!/usr/bin/env bash
set -euo pipefail

# Install or refresh shell proxy helpers without rerunning the full base installer.

HELPER_DIR="$HOME/.config/new-mac"
HELPER_FILE="$HELPER_DIR/proxy.zsh"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_GREEN=""
  C_YELLOW=""
  C_CYAN=""
fi

append_line_once() {
  local file="$1"
  local line="$2"

  touch "$file"
  if ! grep -Fqx "$line" "$file"; then
    printf '%s\n' "$line" >> "$file"
  fi
}

main() {
  mkdir -p "$HELPER_DIR"

  cat > "$HELPER_FILE" <<'EOF'
# Proxy helpers for local VPN/proxy tools such as FlClash, Clash Verge, Surge, or similar apps.
# Defaults match common Clash mixed-port settings, but every value can be changed.
#
# Common usage:
#   proxy_set 7890
#   proxy_on
#   proxy_status
#   proxy_off
#
# If your tool has separate HTTP and SOCKS ports:
#   proxy_set 7897 7898
#   proxy_on
#
# If your proxy is not on localhost:
#   proxy_set 7890 7890 192.168.1.10

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  PROXY_C_RESET=$'\033[0m'
  PROXY_C_GREEN=$'\033[32m'
  PROXY_C_YELLOW=$'\033[33m'
  PROXY_C_CYAN=$'\033[36m'
else
  PROXY_C_RESET=""
  PROXY_C_GREEN=""
  PROXY_C_YELLOW=""
  PROXY_C_CYAN=""
fi

export DEV_PROXY_HOST="${DEV_PROXY_HOST:-127.0.0.1}"
export DEV_PROXY_HTTP_PORT="${DEV_PROXY_HTTP_PORT:-7890}"
export DEV_PROXY_SOCKS_PORT="${DEV_PROXY_SOCKS_PORT:-${DEV_PROXY_HTTP_PORT}}"

proxy_set() {
  export DEV_PROXY_HTTP_PORT="${1:-7890}"
  export DEV_PROXY_SOCKS_PORT="${2:-${DEV_PROXY_HTTP_PORT}}"
  export DEV_PROXY_HOST="${3:-127.0.0.1}"
  printf '%sProxy config:%s host=%s http=%s socks=%s\n' "$PROXY_C_CYAN" "$PROXY_C_RESET" "$DEV_PROXY_HOST" "$DEV_PROXY_HTTP_PORT" "$DEV_PROXY_SOCKS_PORT"
}

proxy_on() {
  local http_port="${1:-${DEV_PROXY_HTTP_PORT:-7890}}"
  local socks_port
  local host="${3:-${DEV_PROXY_HOST:-127.0.0.1}}"

  if [[ "$#" -eq 0 ]]; then
    socks_port="${DEV_PROXY_SOCKS_PORT:-${http_port}}"
  elif [[ "$#" -eq 1 ]]; then
    socks_port="${http_port}"
  else
    socks_port="$2"
  fi

  export DEV_PROXY_HOST="${host}"
  export DEV_PROXY_HTTP_PORT="${http_port}"
  export DEV_PROXY_SOCKS_PORT="${socks_port}"

  export http_proxy="http://${host}:${http_port}"
  export https_proxy="${http_proxy}"
  export HTTP_PROXY="${http_proxy}"
  export HTTPS_PROXY="${https_proxy}"
  export all_proxy="${http_proxy}"
  export ALL_PROXY="${all_proxy}"
  printf '%sProxy enabled:%s http=%s all=%s\n' "$PROXY_C_GREEN" "$PROXY_C_RESET" "$http_proxy" "$all_proxy"
}

proxy_off() {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
  printf '%sProxy disabled%s\n' "$PROXY_C_YELLOW" "$PROXY_C_RESET"
}

proxy_status() {
  printf '%sProxy config:%s host=%s http=%s socks=%s\n' "$PROXY_C_CYAN" "$PROXY_C_RESET" "${DEV_PROXY_HOST:-127.0.0.1}" "${DEV_PROXY_HTTP_PORT:-7890}" "${DEV_PROXY_SOCKS_PORT:-${DEV_PROXY_HTTP_PORT:-7890}}"
  env | grep -E '^(http_proxy|https_proxy|HTTP_PROXY|HTTPS_PROXY|all_proxy|ALL_PROXY)=' || true
}

proxy_test() {
  local url="${1:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"
  curl -I --connect-timeout 8 --max-time 20 "$url"
}

git_proxy_on() {
  local http_port="${1:-${DEV_PROXY_HTTP_PORT:-7890}}"
  local host="${2:-${DEV_PROXY_HOST:-127.0.0.1}}"
  git config --global http.proxy "http://${host}:${http_port}"
  git config --global https.proxy "http://${host}:${http_port}"
  printf '%sGit proxy enabled:%s http://%s:%s\n' "$PROXY_C_GREEN" "$PROXY_C_RESET" "$host" "$http_port"
}

git_proxy_off() {
  git config --global --unset http.proxy 2>/dev/null || true
  git config --global --unset https.proxy 2>/dev/null || true
  printf '%sGit proxy disabled%s\n' "$PROXY_C_YELLOW" "$PROXY_C_RESET"
}

git_proxy_status() {
  git config --global --get http.proxy || true
  git config --global --get https.proxy || true
}
EOF

  chmod 600 "$HELPER_FILE"

  local source_line='[ -f "$HOME/.config/new-mac/proxy.zsh" ] && source "$HOME/.config/new-mac/proxy.zsh"'
  append_line_once "$HOME/.zshrc" "$source_line"
  append_line_once "$HOME/.zprofile" "$source_line"

  printf '%sProxy helper file written:%s %s\n' "$C_GREEN" "$C_RESET" "$HELPER_FILE"
  printf '%sAdded loader line%s to ~/.zshrc and ~/.zprofile when missing.\n' "$C_GREEN" "$C_RESET"
  printf '%sRun this manually:%s source ~/.zshrc\n' "$C_YELLOW" "$C_RESET"
  printf '%sFor iTerm2:%s open a new window/tab, then run: %stype proxy_on%s\n' "$C_YELLOW" "$C_RESET" "$C_CYAN" "$C_RESET"
}

main "$@"
