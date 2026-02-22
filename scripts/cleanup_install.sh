#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/deploy.sh"

remove_systemd_service() {
  local service_name="$1"
  [[ -n "$service_name" ]] || return 0

  sudo_if_needed systemctl disable --now "${service_name}.service" >/dev/null 2>&1 || true
  if [[ -f "/etc/systemd/system/${service_name}.service" ]]; then
    sudo_if_needed rm -f "/etc/systemd/system/${service_name}.service"
  fi
}

remove_systemd_update_timer() {
  local app_name="$1"
  local base="agpd-update-${app_name}"

  sudo_if_needed systemctl disable --now "${base}.timer" >/dev/null 2>&1 || true
  sudo_if_needed systemctl stop "${base}.service" >/dev/null 2>&1 || true

  [[ -f "/etc/systemd/system/${base}.timer" ]] && sudo_if_needed rm -f "/etc/systemd/system/${base}.timer"
  [[ -f "/etc/systemd/system/${base}.service" ]] && sudo_if_needed rm -f "/etc/systemd/system/${base}.service"

  sudo_if_needed systemctl daemon-reload >/dev/null 2>&1 || true
}

remove_openrc_service() {
  local service_name="$1"
  [[ -n "$service_name" ]] || return 0

  sudo_if_needed rc-service "$service_name" stop >/dev/null 2>&1 || true
  sudo_if_needed rc-update del "$service_name" default >/dev/null 2>&1 || true
  [[ -f "/etc/init.d/${service_name}" ]] && sudo_if_needed rm -f "/etc/init.d/${service_name}"
}

remove_openrc_cron_entry() {
  local app_name="$1"
  local needle="update_deployed.sh ${app_name}"
  local tmp1 tmp2

  tmp1="$(mktemp)"
  tmp2="$(mktemp)"

  sudo_if_needed sh -c "crontab -l 2>/dev/null > '$tmp1' || true"
  grep -Fv "$needle" "$tmp1" > "$tmp2" || true
  sudo_if_needed crontab "$tmp2" >/dev/null 2>&1 || true

  rm -f "$tmp1" "$tmp2"
}

remove_dotnet_profile_exports() {
  local profile
  for profile in "$HOME/.profile" "$HOME/.bashrc"; do
    [[ -f "$profile" ]] || continue
    sed -i '/DOTNET_ROOT="\$HOME\/.dotnet"/d' "$profile" || true
    sed -i '/PATH="\$HOME\/.dotnet:\$HOME\/.dotnet\/tools:\$PATH"/d' "$profile" || true
    sed -i '/DOTNET_CLI_TELEMETRY_OPTOUT=/d' "$profile" || true
    sed -i '/DOTNET_SKIP_FIRST_TIME_EXPERIENCE=/d' "$profile" || true
  done
}

remove_toolchains() {
  local os node_marker dotnet_marker
  load_config
  os="$(detect_os)"
  node_marker="${NODE_INSTALLED:-0}"
  dotnet_marker="${DOTNET_INSTALLED:-0}"

  if [[ "$node_marker" == "1" ]]; then
    echo "Removing Node.js/npm..."
    case "$os" in
      debian) sudo_if_needed apt-get remove -y nodejs npm >/dev/null 2>&1 || true ;;
      alpine) sudo_if_needed apk del nodejs npm >/dev/null 2>&1 || true ;;
    esac
  fi

  if [[ "$dotnet_marker" == "1" || -d "$HOME/.dotnet" ]]; then
    echo "Removing .NET SDK from $HOME/.dotnet..."
    rm -rf "$HOME/.dotnet"
    remove_dotnet_profile_exports
  fi

  save_config_kv "INSTALL_PROFILE" "none"
  save_config_kv "NODE_INSTALLED" "0"
  save_config_kv "DOTNET_INSTALLED" "0"
  echo "Toolchain cleanup complete."
}

cleanup_one_app() {
  local app_name="$1"
  local delete_repo="$2"
  local app_file env_dir os

  app_file="$(app_env_file "$app_name")"
  if [[ ! -f "$app_file" ]]; then
    echo "Skipping unknown app: $app_name"
    return 0
  fi

  load_app_env "$app_name"
  os="$(detect_os)"

  echo "Cleaning app: $app_name"

  case "$os" in
    debian)
      remove_systemd_service "${BACKEND_SERVICE:-}"
      remove_systemd_service "${FRONTEND_SERVICE:-}"
      remove_systemd_update_timer "$app_name"
      ;;
    alpine)
      remove_openrc_service "${BACKEND_SERVICE:-}"
      remove_openrc_service "${FRONTEND_SERVICE:-}"
      remove_openrc_cron_entry "$app_name"
      ;;
  esac

  env_dir="$(app_env_dir "$app_name")"
  rm -f "$app_file"
  rm -rf "$env_dir"

  if [[ "$delete_repo" == "1" && -n "${REPO_DIR:-}" && -d "$REPO_DIR" ]]; then
    sudo_if_needed rm -rf "$REPO_DIR"
    echo "Removed repo directory: $REPO_DIR"
  fi

  echo "Cleanup complete for $app_name"
}

main() {
  print_header
  echo "Cleanup Installed Deployments"

  local has_apps mode app_name delete_repo remove_toolchain_choice reset_markers
  has_apps=0
  if list_apps >/dev/null 2>&1; then
    has_apps=1
    echo "Existing deployments:"
    list_apps | sed 's/^/- /'
    echo
    echo "1) Cleanup one app"
    echo "2) Cleanup all apps"
    echo "3) Skip app cleanup"
    read -r -p "Choose [1-3]: " mode

    read -r -p "Delete checked-out repo directories too? [y/N]: " delete_repo
    if [[ "$delete_repo" =~ ^[Yy]$ ]]; then
      delete_repo="1"
    else
      delete_repo="0"
    fi

    case "$mode" in
      1)
        read -r -p "App name: " app_name
        cleanup_one_app "$app_name" "$delete_repo"
        ;;
      2)
        while IFS= read -r app_name; do
          cleanup_one_app "$app_name" "$delete_repo"
        done < <(list_apps)
        ;;
      3)
        ;;
      *)
        echo "Invalid choice"
        exit 1
        ;;
    esac
  else
    echo "No deployments found."
  fi

  read -r -p "Remove installed toolchains too (Node/.NET SDK)? [y/N]: " remove_toolchain_choice
  if [[ "$remove_toolchain_choice" =~ ^[Yy]$ ]]; then
    remove_toolchains
  elif [[ "$has_apps" -eq 1 ]]; then
    read -r -p "Reset toolchain install markers in config? [y/N]: " reset_markers
    if [[ "$reset_markers" =~ ^[Yy]$ ]]; then
      save_config_kv "INSTALL_PROFILE" "none"
      save_config_kv "NODE_INSTALLED" "0"
      save_config_kv "DOTNET_INSTALLED" "0"
      echo "Toolchain markers reset."
    fi
  fi

  echo "Cleanup finished."
}

main "$@"
