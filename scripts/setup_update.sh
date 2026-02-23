#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

install_update_command() {
  local target="/usr/local/bin/agpd-update"
  sudo_if_needed tee "$target" >/dev/null <<EOF_CMD
#!/usr/bin/env bash
set -euo pipefail
exec bash "$ROOT_DIR/scripts/update_stack.sh" "\$@"
EOF_CMD
  sudo_if_needed chmod +x "$target"
  echo "$(c_menu "Installed command: $target")"
}

setup_cron() {
  local schedule line tmp
  read -r -p "Cron schedule [*/15 * * * *]: " schedule
  schedule="${schedule:-*/15 * * * *}"

  line="$schedule AGPD_NO_COLOR=1 bash '$ROOT_DIR/scripts/update_stack.sh' >> '$HOME/agpd-update.log' 2>&1"
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -Fv "$ROOT_DIR/scripts/update_stack.sh" > "$tmp" || true
  echo "$line" >> "$tmp"
  crontab "$tmp"
  rm -f "$tmp"

  echo "$(c_menu "Cron installed: $line")"
}

main() {
  load_config
  [[ -n "${APP_NAME:-}" ]] || { echo "Configure project first (option 2)."; exit 1; }

  print_header
  echo "$(c_menu "Setup update command + cron")"

  install_update_command
  setup_cron

  echo "$(c_menu "Done. You can now run: agpd-update")"
}

main "$@"
