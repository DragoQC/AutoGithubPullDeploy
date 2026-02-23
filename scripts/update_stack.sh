#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

run_as_owner() {
  local cmd="$1"
  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    runuser -u "$SUDO_USER" -- bash -lc "$cmd"
  else
    bash -lc "$cmd"
  fi
}

main() {
  load_config
  require_cmd git

  local app_name repo_url branch app_dir backend_rel backend_dir migration_cmd creds_file
  app_name="${APP_NAME:-}"
  repo_url="${REPO_URL:-}"
  branch="${REPO_BRANCH:-main}"
  app_dir="${APP_DIR:-}"
  backend_rel="${BACKEND_REL:-Backend}"
  migration_cmd="${MIGRATION_CMD:-dotnet ef database update}"
  creds_file="${DB_CREDENTIALS_FILE:-}"

  [[ -n "$app_name" && -n "$repo_url" && -n "$app_dir" ]] || { echo "Missing config. Run option 2 first."; exit 1; }
  repo_url="$(normalize_repo_url_ssh "$repo_url")"
  if ! is_ssh_repo_url "$repo_url"; then
    echo "Configured repo URL is not SSH. Run option 2 and set an SSH URL."
    exit 1
  fi

  print_header
  echo "$(c_menu "Updating app: $app_name")"
  echo "$(c_menu "Deleting old code: $app_dir")"
  sudo_if_needed rm -rf "$app_dir"

  sudo_if_needed mkdir -p "$(dirname "$app_dir")"
  echo "$(c_menu "Cloning branch '$branch' from $repo_url")"
  run_as_owner "git clone --branch '$branch' --single-branch '$repo_url' '$app_dir'"

  backend_dir="$app_dir/$backend_rel"
  if [[ -d "$backend_dir" ]]; then
    if [[ -n "$creds_file" && -f "$creds_file" ]]; then
      sudo_if_needed cp "$creds_file" "$backend_dir/db-credentials.env" || true
      sudo_if_needed chown "$(id -u):$(id -g)" "$backend_dir/db-credentials.env" || true
    fi

    if command -v dotnet >/dev/null 2>&1; then
      echo "$(c_dotnet "Running dotnet restore")"
      run_as_owner "cd '$backend_dir' && export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1; dotnet restore"

      if [[ -n "$migration_cmd" ]]; then
        echo "$(c_dotnet "Running migration command: $migration_cmd")"
        run_as_owner "cd '$backend_dir' && export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1; $migration_cmd"
      fi
    else
      echo "$(c_dotnet "dotnet not installed; skipping migration")"
    fi
  fi

  echo "$(c_menu "Update finished.")"
}

main "$@"
