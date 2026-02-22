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

  if ! list_apps >/dev/null 2>&1; then
    echo "No deployments found."
    exit 0
  fi

  echo "Existing deployments:"
  list_apps | sed 's/^/- /'

  local mode app_name delete_repo reset_markers
  echo
  echo "1) Cleanup one app"
  echo "2) Cleanup all apps"
  read -r -p "Choose [1-2]: " mode

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
    *)
      echo "Invalid choice"
      exit 1
      ;;
  esac

  read -r -p "Reset toolchain install markers in config? [y/N]: " reset_markers
  if [[ "$reset_markers" =~ ^[Yy]$ ]]; then
    save_config_kv "INSTALL_PROFILE" "none"
    save_config_kv "NODE_INSTALLED" "0"
    save_config_kv "DOTNET_INSTALLED" "0"
    echo "Toolchain markers reset."
  fi

  echo "Cleanup finished."
}

main "$@"
