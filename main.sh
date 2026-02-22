#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

run_script() {
  local script="$1"
  bash "$ROOT_DIR/scripts/$script"
}

menu() {
  echo
  echo "AutoGithubPullDeploy"
  echo "1) Install dependencies"
  echo "2) Setup GitHub authentication"
  echo "3) Deploy app services (backend/frontend/both)"
  echo "4) Configure automatic update schedule"
  echo "5) Clone/Update repository"
  echo "6) Update deployed app now (frontend/backend/both)"
  echo "7) Run app from local path (manual/dev)"
  echo "8) Cleanup installed deployments/services"
  echo "0) Exit"
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
