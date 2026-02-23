#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

sanitize_name() {
  local s="$1"
  s="${s,,}"
  s="${s//[^a-z0-9_-]/-}"
  s="${s#-}"
  s="${s%-}"
  printf '%s' "$s"
}

main() {
  require_cmd git
  load_config

  local app_name repo_url branch app_root app_dir backend_rel migration_cmd
  local do_clone

  print_header
  echo "$(c_menu "Configure Project")"

  read -r -p "App name [${APP_NAME:-myapp}]: " app_name
  app_name="${app_name:-${APP_NAME:-myapp}}"
  app_name="$(sanitize_name "$app_name")"
  [[ -n "$app_name" ]] || { echo "Invalid app name"; exit 1; }

  read -r -p "GitHub repo URL [${REPO_URL:-}]: " repo_url
  repo_url="${repo_url:-${REPO_URL:-}}"
  [[ -n "$repo_url" ]] || { echo "Repo URL is required"; exit 1; }

  read -r -p "Branch [${REPO_BRANCH:-main}]: " branch
  branch="${branch:-${REPO_BRANCH:-main}}"

  read -r -p "App root directory [${APP_ROOT:-/srv/apps}]: " app_root
  app_root="${app_root:-${APP_ROOT:-/srv/apps}}"

  read -r -p "Backend path inside repo [${BACKEND_REL:-Backend}]: " backend_rel
  backend_rel="${backend_rel:-${BACKEND_REL:-Backend}}"

  read -r -p "Migration command [${MIGRATION_CMD:-dotnet ef database update}]: " migration_cmd
  migration_cmd="${migration_cmd:-${MIGRATION_CMD:-dotnet ef database update}}"

  app_dir="$app_root/$app_name"

  save_config_kv "APP_NAME" "$app_name"
  save_config_kv "REPO_URL" "$repo_url"
  save_config_kv "REPO_BRANCH" "$branch"
  save_config_kv "APP_ROOT" "$app_root"
  save_config_kv "APP_DIR" "$app_dir"
  save_config_kv "BACKEND_REL" "$backend_rel"
  save_config_kv "MIGRATION_CMD" "$migration_cmd"
  save_config_kv "BACKEND_DIR" "$app_dir/$backend_rel"

  read -r -p "Clone repo now (delete existing app dir first)? [Y/n]: " do_clone
  if [[ ! "$do_clone" =~ ^[Nn]$ ]]; then
    sudo_if_needed mkdir -p "$app_root"
    if [[ -d "$app_dir" ]]; then
      sudo_if_needed rm -rf "$app_dir"
    fi
    sudo_if_needed git clone --branch "$branch" --single-branch "$repo_url" "$app_dir"
    sudo_if_needed chown -R "$(id -u):$(id -g)" "$app_dir" || true
    echo "$(c_menu "Repo cloned at: $app_dir")"
  fi

  echo "$(c_menu "Project configuration saved to: $CONFIG_FILE")"
}

main "$@"
