#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/deploy.sh"

install_systemd_timer() {
  local app_name="$1"
  local interval="$2"
  local service="agpd-update-${app_name}"

  sudo_if_needed tee "/etc/systemd/system/${service}.service" >/dev/null <<EOF_SERVICE
[Unit]
Description=Auto update ${app_name}
After=network.target

[Service]
Type=oneshot
Environment=AGPD_CONFIG_DIR=${CONFIG_DIR}
ExecStart=${SCRIPT_DIR}/update_deployed.sh ${app_name}
EOF_SERVICE

  sudo_if_needed tee "/etc/systemd/system/${service}.timer" >/dev/null <<EOF_TIMER
[Unit]
Description=Schedule auto update for ${app_name}

[Timer]
OnBootSec=2min
OnUnitActiveSec=${interval}
Persistent=true
Unit=${service}.service

[Install]
WantedBy=timers.target
EOF_TIMER

  sudo_if_needed systemctl daemon-reload
  sudo_if_needed systemctl enable --now "${service}.timer"
}

install_openrc_cron() {
  local app_name="$1"
  local minutes="$2"
  local line="*/${minutes} * * * * AGPD_CONFIG_DIR=${CONFIG_DIR} ${SCRIPT_DIR}/update_deployed.sh ${app_name} >> /var/log/agpd-update-${app_name}.log 2>&1"

  local tmp
  tmp="$(mktemp)"
  sudo_if_needed sh -c "crontab -l 2>/dev/null > '$tmp' || true"
  if ! sudo_if_needed grep -Fq "$line" "$tmp"; then
    echo "$line" | sudo_if_needed tee -a "$tmp" >/dev/null
  fi
  sudo_if_needed crontab "$tmp"
  rm -f "$tmp"

  sudo_if_needed rc-update add crond default || true
  sudo_if_needed rc-service crond start || true
}

main() {
  print_header
  echo "Schedule automatic updates"

  local app_name os
  if ! list_apps >/dev/null 2>&1; then
    echo "No deployed apps found. Run deploy first."
    exit 1
  fi

  echo "Available apps:"
  list_apps | sed 's/^/- /'
  read -r -p "App name: " app_name
  load_app_env "$app_name"

  os="$(detect_os)"
  case "$os" in
    debian)
      local interval
      read -r -p "Systemd interval [15min|30min|1h] (default 15min): " interval
      interval="${interval:-15min}"
      install_systemd_timer "$app_name" "$interval"
      ;;
    alpine)
      local minutes
      read -r -p "Cron frequency in minutes [default 15]: " minutes
      minutes="${minutes:-15}"
      install_openrc_cron "$app_name" "$minutes"
      ;;
    *)
      echo "Unsupported OS"
      exit 1
      ;;
  esac

  echo "Automatic updates configured for $app_name"
}

main "$@"
