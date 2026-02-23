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
  echo "$(c_menu "1) Install dependencies")"
  echo "$(c_menu "2) Setup GitHub authentication")"
  echo "$(c_menu "3) Deploy app services (backend/frontend/both)")"
  echo "$(c_menu "4) Configure automatic update schedule")"
  echo "$(c_menu "5) Clone/Update repository")"
  echo "$(c_menu "6) Update deployed app now (frontend/backend/both)")"
  echo "$(c_menu "7) Run app from local path (manual/dev)")"
  echo "$(c_menu "8) Cleanup installed deployments/services")"
  echo "$(c_menu "0) Exit")"
}

main() {
  while true; do
    menu
    read -r -p "Choose an option: " choice

    case "$choice" in
      1)
        run_script "install_deps.sh"
        ;;
      2)
        run_script "github_auth.sh"
        ;;
      3)
        run_script "deploy_stack.sh"
        ;;
      4)
        run_script "schedule_updates.sh"
        ;;
      5)
        run_script "pull_repo.sh"
        ;;
      6)
        read -r -p "App deployment name: " app_name
        bash "$ROOT_DIR/scripts/update_deployed.sh" "$app_name"
        ;;
      7)
        read -r -p "Enter local repo path: " repo_path
        bash "$ROOT_DIR/scripts/run_app.sh" "$repo_path"
        ;;
      8)
        run_script "cleanup_install.sh"
        ;;
      0)
        exit 0
        ;;
      *)
        echo "Invalid choice"
        ;;
    esac
  done
}

main "$@"
