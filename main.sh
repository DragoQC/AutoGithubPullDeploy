#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

run_script() {
  local script="$1"
  bash "$ROOT_DIR/scripts/$script"
}

menu() {
  echo
  echo "$(c_menu "AutoGithubPullDeploy")"
  echo "$(c_menu "1) Install dependencies (git, curl, node, dotnet)")"
  echo "$(c_menu "2) Configure project + clone repo")"
  echo "$(c_db "3) Install/Configure MariaDB for this project")"
  echo "$(c_menu "4) Install update command + setup cron")"
  echo "$(c_menu "5) Run update now (delete old code, re-clone, migrate)")"
  echo "$(c_menu "6) Show current config")"
  echo "$(c_menu "0) Exit")"
}

main() {
  while true; do
    menu
    read -r -p "Choose an option: " choice

    case "$choice" in
      1) run_script "install_deps.sh" ;;
      2) run_script "configure_project.sh" ;;
      3) run_script "install_database.sh" ;;
      4) run_script "setup_update.sh" ;;
      5) run_script "update_stack.sh" ;;
      6) run_script "show_config.sh" ;;
      0) exit 0 ;;
      *) echo "Invalid choice" ;;
    esac
  done
}

main "$@"
