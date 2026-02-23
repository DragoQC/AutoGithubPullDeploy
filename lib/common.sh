#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AutoGithubPullDeploy"
CONFIG_DIR="${AGPD_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agpd}"
CONFIG_FILE="$CONFIG_DIR/config.env"
APPS_DIR="$CONFIG_DIR/apps"

mkdir -p "$CONFIG_DIR"
mkdir -p "$APPS_DIR"

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

save_config_kv() {
  local key="$1"
  local value="$2"
  touch "$CONFIG_FILE"
  if grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$CONFIG_FILE"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$CONFIG_FILE"
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    return 1
  fi
}

detect_os() {
  local id=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
  fi

  case "$id" in
    debian|ubuntu|linuxmint|pop)
      echo "debian"
      ;;
    alpine)
      echo "alpine"
      ;;
    *)
      echo "unsupported"
      ;;
  esac
}

sudo_if_needed() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

print_header() {
  echo
  echo "=============================================="
  echo "  $APP_NAME"
  echo "=============================================="
}

supports_color() {
  if [[ "${AGPD_FORCE_COLOR:-0}" == "1" || "${CLICOLOR_FORCE:-0}" == "1" || "${FORCE_COLOR:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${AGPD_NO_COLOR:-0}" == "1" || -n "${NO_COLOR:-}" ]]; then
    return 1
  fi
  [[ -t 1 && "${TERM:-}" != "dumb" ]]
}

colorize() {
  local code="$1"
  local text="$2"
  if supports_color; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}

c_menu() { colorize "33" "$1"; }    # yellow
c_node() { colorize "32" "$1"; }    # green
c_dotnet() { colorize "35" "$1"; }  # purple
c_db() { colorize "34" "$1"; }      # blue
