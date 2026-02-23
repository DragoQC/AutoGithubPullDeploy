#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

DB_CREDENTIALS_FILE_GLOBAL="/etc/agpd/db-credentials.env"

to_db_identifier() {
  local s="$1"
  s="${s,,}"
  s="$(printf '%s' "$s" | sed 's/[^a-z0-9_]/_/g; s/__*/_/g; s/^_//; s/_$//')"
  [[ -n "$s" ]] || s="appdb"
  printf '%s' "$s"
}

generate_password() {
  tr -dc 'A-Za-z0-9@#%+=_' < /dev/urandom | head -c 32
}

install_mariadb() {
  local os
  os="$(detect_os)"
  case "$os" in
    debian)
      sudo_if_needed apt-get update
      sudo_if_needed apt-get install -y mariadb-server mariadb-client
      sudo_if_needed systemctl enable --now mariadb
      ;;
    alpine)
      sudo_if_needed apk update
      sudo_if_needed apk add --no-cache mariadb mariadb-client
      if [[ ! -d /var/lib/mysql/mysql ]]; then
        sudo_if_needed mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1 || true
      fi
      sudo_if_needed rc-update add mariadb default || true
      sudo_if_needed rc-service mariadb start || true
      ;;
    *)
      echo "Unsupported OS"
      exit 1
      ;;
  esac
}

run_sql() {
  local sql="$1"
  if sudo_if_needed mariadb -e "$sql" >/dev/null 2>&1; then
    return 0
  fi
  local rootpw
  read -r -s -p "$(c_db "MariaDB root password: ")" rootpw
  echo
  sudo_if_needed env MYSQL_PWD="$rootpw" mariadb -uroot -e "$sql" >/dev/null
}

main() {
  load_config

  local app_name app_dir backend_rel backend_dir db_name db_user db_password bind_choice db_host
  app_name="${APP_NAME:-}"
  app_dir="${APP_DIR:-}"
  backend_rel="${BACKEND_REL:-Backend}"

  if [[ -z "$app_name" || -z "$app_dir" ]]; then
    echo "$(c_db "Project is not configured. Run option 2 first.")"
    exit 1
  fi

  backend_dir="$app_dir/$backend_rel"
  sudo_if_needed mkdir -p "$backend_dir"

  print_header
  echo "$(c_db "Install/Configure MariaDB")"

  install_mariadb

  db_name="$(to_db_identifier "$app_name")"
  db_user="${db_name}_user"
  db_user="${db_user:0:48}"
  db_password="$(generate_password)"

  echo "$(c_db "Connection mode:")"
  echo "$(c_db "1) Localhost only")"
  echo "$(c_db "2) Allow external connections")"
  read -r -p "$(c_db "Choose [1-2]: ")" bind_choice

  case "$bind_choice" in
    1) db_host="localhost" ;;
    2) db_host="%" ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac

  run_sql "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  run_sql "CREATE USER IF NOT EXISTS '${db_user}'@'${db_host}' IDENTIFIED BY '${db_password}';"
  run_sql "ALTER USER '${db_user}'@'${db_host}' IDENTIFIED BY '${db_password}';"
  run_sql "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'${db_host}'; FLUSH PRIVILEGES;"

  sudo_if_needed mkdir -p /etc/agpd
  sudo_if_needed tee "$DB_CREDENTIALS_FILE_GLOBAL" >/dev/null <<EOF_CREDS
APP_NAME="$app_name"
DB_ENGINE="mariadb"
DB_NAME="$db_name"
DB_USER="$db_user"
DB_PASSWORD="$db_password"
DB_USER_HOST="$db_host"
EOF_CREDS
  sudo_if_needed chmod 600 "$DB_CREDENTIALS_FILE_GLOBAL"

  local backend_creds_file="$backend_dir/db-credentials.env"
  sudo_if_needed tee "$backend_creds_file" >/dev/null <<EOF_CREDS
APP_NAME="$app_name"
DB_ENGINE="mariadb"
DB_NAME="$db_name"
DB_USER="$db_user"
DB_PASSWORD="$db_password"
DB_USER_HOST="$db_host"
EOF_CREDS
  sudo_if_needed chmod 600 "$backend_creds_file"

  save_config_kv "DB_NAME" "$db_name"
  save_config_kv "DB_USER" "$db_user"
  save_config_kv "DB_PASSWORD" "$db_password"
  save_config_kv "DB_USER_HOST" "$db_host"
  save_config_kv "DB_CREDENTIALS_FILE" "$backend_creds_file"

  echo "$(c_db "MariaDB ready.")"
  echo "$(c_db "Backend credentials file: $backend_creds_file")"
}

main "$@"
