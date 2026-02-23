#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/deploy.sh"

DB_CREDENTIALS_FILE="/etc/agpd/db-credentials.env"

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

remove_dotnet_home() {
  local home_dir="$1"
  local dotnet_dir
  dotnet_dir="${home_dir}/.dotnet"
  if [[ -d "$dotnet_dir" ]]; then
    rm -rf "$dotnet_dir"
    echo "Removed .NET SDK directory: $dotnet_dir"
  fi
}

read_db_credential() {
  local key="$1"
  local line
  if [[ -r "$DB_CREDENTIALS_FILE" ]]; then
    line="$(grep -E "^${key}=" "$DB_CREDENTIALS_FILE" 2>/dev/null || true)"
  else
    line="$(sudo_if_needed grep -E "^${key}=" "$DB_CREDENTIALS_FILE" 2>/dev/null || true)"
  fi
  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  printf '%s' "$line"
}

escape_sql_string() {
  printf '%s' "$1" | sed "s/'/''/g"
}

cleanup_database_assets() {
  local db_name db_user db_pass db_host client esc_db esc_user esc_host
  local root_drop_ok=0 user_drop_ok=0 user_drop_user_ok=0
  local remove_creds

  if [[ ! -f "$DB_CREDENTIALS_FILE" ]]; then
    echo "No DB credentials file found at $DB_CREDENTIALS_FILE"
    return 0
  fi

  db_name="$(read_db_credential "DB_NAME")"
  db_user="$(read_db_credential "DB_USER")"
  db_pass="$(read_db_credential "DB_PASSWORD")"
  db_host="$(read_db_credential "DB_USER_HOST")"
  db_host="${db_host:-localhost}"

  if [[ -z "$db_name" || -z "$db_user" ]]; then
    echo "DB credentials file is missing DB_NAME/DB_USER; skipping DB cleanup."
    return 0
  fi

  if command -v mariadb >/dev/null 2>&1; then
    client="mariadb"
  else
    echo "No MariaDB client found; skipping DB cleanup."
    return 0
  fi

  esc_db="$(escape_sql_string "$db_name")"
  esc_user="$(escape_sql_string "$db_user")"
  esc_host="$(escape_sql_string "$db_host")"

  echo "Attempting DB cleanup for database '$db_name' and user '$db_user'@'$db_host'..."

  if sudo_if_needed "$client" -e "DROP DATABASE IF EXISTS \`$esc_db\`; DROP USER IF EXISTS '$esc_user'@'$esc_host'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    root_drop_ok=1
    echo "Dropped database and user via privileged DB connection."
  fi

  if [[ $root_drop_ok -eq 0 ]]; then
    if [[ -n "$db_pass" ]] && MYSQL_PWD="$db_pass" "$client" -u"$db_user" -e "DROP DATABASE IF EXISTS \`$esc_db\`;" >/dev/null 2>&1; then
      user_drop_ok=1
      echo "Dropped database using app DB credentials."
    fi

    if [[ -n "$db_pass" ]] && MYSQL_PWD="$db_pass" "$client" -u"$db_user" -e "DROP USER IF EXISTS '$esc_user'@'$esc_host';" >/dev/null 2>&1; then
      user_drop_user_ok=1
      echo "Dropped DB user using app DB credentials."
    fi
  fi

  if [[ $root_drop_ok -eq 0 && $user_drop_ok -eq 0 ]]; then
    echo "Could not drop database automatically. Check DB root access and credentials."
    return 0
  fi

  read -r -p "Delete saved DB credentials file ($DB_CREDENTIALS_FILE)? [y/N]: " remove_creds
  if [[ "$remove_creds" =~ ^[Yy]$ ]]; then
    sudo_if_needed rm -f "$DB_CREDENTIALS_FILE"
    echo "Removed $DB_CREDENTIALS_FILE"
  fi
}

remove_toolchains() {
  local os node_marker dotnet_marker
  load_config
  os="$(detect_os)"
  node_marker="${NODE_INSTALLED:-0}"
  dotnet_marker="${DOTNET_INSTALLED:-0}"

  if [[ "$node_marker" == "1" || -x "$(command -v node 2>/dev/null || true)" || -x "$(command -v npm 2>/dev/null || true)" ]]; then
    echo "Removing Node.js/npm..."
    case "$os" in
      debian)
        sudo_if_needed apt-get remove -y nodejs npm >/dev/null 2>&1 || true
        sudo_if_needed apt-get autoremove -y >/dev/null 2>&1 || true
        ;;
      alpine)
        sudo_if_needed apk del nodejs npm >/dev/null 2>&1 || true
        ;;
    esac
  fi

  if [[ "$dotnet_marker" == "1" || -d "$HOME/.dotnet" || -d "/root/.dotnet" ]]; then
    echo "Removing user-local .NET SDK directories..."
    remove_dotnet_home "$HOME"
    remove_dotnet_home "/root"
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

  local has_apps mode app_name delete_repo remove_toolchain_choice reset_markers remove_db_choice
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

  read -r -p "Delete configured database (drop DB/user) using saved credentials? [y/N]: " remove_db_choice
  if [[ "$remove_db_choice" =~ ^[Yy]$ ]]; then
    cleanup_database_assets
  fi

  echo "Cleanup finished."
}

main "$@"
