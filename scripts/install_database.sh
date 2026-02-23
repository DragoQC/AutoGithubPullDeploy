#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

DB_CREDENTIALS_FILE="/etc/agpd/db-credentials.env"
DB_CLIENT_BIN=""

install_mariadb_debian() {
  sudo_if_needed apt-get update
  sudo_if_needed apt-get install -y mariadb-server mariadb-client
  sudo_if_needed systemctl enable --now mariadb
}

install_mariadb_alpine() {
  sudo_if_needed apk update
  sudo_if_needed apk add --no-cache mariadb mariadb-client

  if [[ ! -d /var/lib/mysql/mysql ]]; then
    sudo_if_needed mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1 || true
  fi

  sudo_if_needed rc-update add mariadb default || true
  sudo_if_needed rc-service mariadb start || true
}

install_mysql_debian() {
  sudo_if_needed apt-get update
  if sudo_if_needed apt-get install -y mysql-server mysql-client; then
    :
  else
    sudo_if_needed apt-get install -y default-mysql-server default-mysql-client
  fi

  if sudo_if_needed systemctl list-unit-files | grep -q '^mysql\.service'; then
    sudo_if_needed systemctl enable --now mysql
  else
    sudo_if_needed systemctl enable --now mariadb
  fi
}

choose_db_client() {
  if command -v mariadb >/dev/null 2>&1; then
    DB_CLIENT_BIN="mariadb"
  elif command -v mysql >/dev/null 2>&1; then
    DB_CLIENT_BIN="mysql"
  else
    echo "No mariadb/mysql client found after install."
    exit 1
  fi
}

run_sql_file() {
  local sql_file="$1"
  cat "$sql_file" | sudo_if_needed "$DB_CLIENT_BIN"
}

detect_db_config_file() {
  local engine="$1"
  local candidates=()

  if [[ "$engine" == "mariadb" ]]; then
    candidates=(
      "/etc/mysql/mariadb.conf.d/50-server.cnf"
      "/etc/my.cnf.d/mariadb-server.cnf"
      "/etc/my.cnf"
    )
  else
    candidates=(
      "/etc/mysql/mysql.conf.d/mysqld.cnf"
      "/etc/mysql/mariadb.conf.d/50-server.cnf"
      "/etc/my.cnf"
    )
  fi

  local f
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      echo "$f"
      return 0
    fi
  done

  echo ""
}

set_bind_address() {
  local cfg_file="$1"
  local bind_addr="$2"

  if [[ -z "$cfg_file" || ! -f "$cfg_file" ]]; then
    echo "DB config file not found; skipping bind-address update."
    return 0
  fi

  if grep -Eq '^[[:space:]#]*bind-address' "$cfg_file"; then
    sudo_if_needed sed -i "s|^[[:space:]#]*bind-address.*|bind-address = ${bind_addr}|" "$cfg_file"
  else
    printf '\n[mysqld]\nbind-address = %s\n' "$bind_addr" | sudo_if_needed tee -a "$cfg_file" >/dev/null
  fi

  echo "Set bind-address=${bind_addr} in ${cfg_file}"
}

restart_db_service() {
  local os="$1"
  local engine="$2"

  if [[ "$os" == "debian" ]]; then
    if [[ "$engine" == "mysql" ]] && sudo_if_needed systemctl list-unit-files | grep -q '^mysql\.service'; then
      sudo_if_needed systemctl restart mysql || true
    elif sudo_if_needed systemctl list-unit-files | grep -q '^mariadb\.service'; then
      sudo_if_needed systemctl restart mariadb || true
    else
      sudo_if_needed systemctl restart mysql || true
    fi
  elif [[ "$os" == "alpine" ]]; then
    sudo_if_needed rc-service mariadb restart || true
  fi
}

validate_identifier() {
  local s="$1"
  [[ "$s" =~ ^[A-Za-z0-9_]+$ ]]
}

prompt_password_twice() {
  local label="$1"
  local p1 p2
  while true; do
    read -r -s -p "$label: " p1
    echo
    read -r -s -p "Confirm $label: " p2
    echo
    if [[ "$p1" != "$p2" ]]; then
      echo "Passwords do not match. Try again."
      continue
    fi
    if [[ -z "$p1" ]]; then
      echo "Password cannot be empty. Try again."
      continue
    fi
    printf '%s' "$p1"
    return 0
  done
}

escape_sql_string() {
  printf '%s' "$1" | sed "s/'/''/g"
}

write_credentials_file() {
  local engine="$1"
  local bind_addr="$2"
  local db_name="$3"
  local db_user="$4"
  local db_password="$5"
  local db_user_host="$6"
  local root_password_set="$7"

  sudo_if_needed mkdir -p /etc/agpd
  sudo_if_needed tee "$DB_CREDENTIALS_FILE" >/dev/null <<EOF_CREDS
# AutoGithubPullDeploy database credentials
DB_ENGINE="$engine"
DB_BIND_ADDRESS="$bind_addr"
DB_NAME="$db_name"
DB_USER="$db_user"
DB_PASSWORD="$db_password"
DB_USER_HOST="$db_user_host"
DB_ROOT_PASSWORD_SET="$root_password_set"
EOF_CREDS
  sudo_if_needed chmod 600 "$DB_CREDENTIALS_FILE"

  echo "Credentials saved: $DB_CREDENTIALS_FILE"
}

configure_database() {
  local os="$1"
  local engine="$2"
  local bind_choice bind_addr db_name db_user db_password db_user_host
  local set_root_pass root_password root_password_set
  local db_cfg sql_file esc_db_name esc_db_user esc_db_pass esc_db_host esc_root_pass

  while true; do
    read -r -p "Application database name [appdb]: " db_name
    db_name="${db_name:-appdb}"
    if validate_identifier "$db_name"; then
      break
    fi
    echo "Use only letters, numbers, underscore for database name."
  done

  while true; do
    read -r -p "Application database user [appuser]: " db_user
    db_user="${db_user:-appuser}"
    if validate_identifier "$db_user"; then
      break
    fi
    echo "Use only letters, numbers, underscore for user name."
  done

  db_password="$(prompt_password_twice "Database user password")"

  echo
  echo "Connection mode:"
  echo "1) Localhost only"
  echo "2) Allow external connections"
  read -r -p "Choose [1-2]: " bind_choice

  case "$bind_choice" in
    1)
      bind_addr="127.0.0.1"
      db_user_host="localhost"
      ;;
    2)
      bind_addr="0.0.0.0"
      db_user_host="%"
      ;;
    *)
      echo "Invalid choice"
      exit 1
      ;;
  esac

  read -r -p "Set root DB password now? [y/N]: " set_root_pass
  root_password=""
  root_password_set="0"
  if [[ "$set_root_pass" =~ ^[Yy]$ ]]; then
    root_password="$(prompt_password_twice "Root DB password")"
    root_password_set="1"
  fi

  db_cfg="$(detect_db_config_file "$engine")"
  set_bind_address "$db_cfg" "$bind_addr"
  restart_db_service "$os" "$engine"

  esc_db_name="$(escape_sql_string "$db_name")"
  esc_db_user="$(escape_sql_string "$db_user")"
  esc_db_pass="$(escape_sql_string "$db_password")"
  esc_db_host="$(escape_sql_string "$db_user_host")"
  esc_root_pass="$(escape_sql_string "$root_password")"

  sql_file="$(mktemp)"
  {
    echo "DELETE FROM mysql.user WHERE User='';"
    echo "DROP DATABASE IF EXISTS test;"
    echo "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    echo "CREATE DATABASE IF NOT EXISTS \`${esc_db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    echo "CREATE USER IF NOT EXISTS '${esc_db_user}'@'${esc_db_host}' IDENTIFIED BY '${esc_db_pass}';"
    echo "ALTER USER '${esc_db_user}'@'${esc_db_host}' IDENTIFIED BY '${esc_db_pass}';"
    echo "GRANT ALL PRIVILEGES ON \`${esc_db_name}\`.* TO '${esc_db_user}'@'${esc_db_host}';"
    if [[ "$root_password_set" == "1" ]]; then
      echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '${esc_root_pass}';"
    fi
    echo "FLUSH PRIVILEGES;"
  } > "$sql_file"

  run_sql_file "$sql_file"
  rm -f "$sql_file"

  write_credentials_file "$engine" "$bind_addr" "$db_name" "$db_user" "$db_password" "$db_user_host" "$root_password_set"

  save_config_kv "DB_ENGINE" "$engine"
  save_config_kv "DB_INSTALLED" "1"
  save_config_kv "DB_BIND_ADDRESS" "$bind_addr"
  save_config_kv "DB_NAME" "$db_name"
  save_config_kv "DB_USER" "$db_user"

  echo "Database configured successfully."
}

main() {
  local os choice engine
  os="$(detect_os)"

  print_header
  echo "Database Installer"
  echo "1) MariaDB (recommended)"
  echo "2) MySQL"
  echo "0) Cancel"
  read -r -p "Choose [0-2]: " choice

  case "$choice" in
    1)
      case "$os" in
        debian) install_mariadb_debian ;;
        alpine) install_mariadb_alpine ;;
        *) echo "Unsupported OS"; exit 1 ;;
      esac
      engine="mariadb"
      ;;
    2)
      case "$os" in
        debian)
          install_mysql_debian
          engine="mysql"
          ;;
        alpine)
          echo "MySQL packages are not standard on Alpine; installing MariaDB instead."
          install_mariadb_alpine
          engine="mariadb"
          ;;
        *)
          echo "Unsupported OS"
          exit 1
          ;;
      esac
      ;;
    0)
      echo "Cancelled."
      exit 0
      ;;
    *)
      echo "Invalid choice"
      exit 1
      ;;
  esac

  choose_db_client
  configure_database "$os" "$engine"
}

main "$@"
