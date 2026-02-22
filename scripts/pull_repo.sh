#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/repo.sh"

main() {
  require_cmd git
  load_config

  print_header
  echo "Clone or Update GitHub Repo"

  local repo_url default_root target_root repo_dir
  read -r -p "Enter GitHub repo URL: " repo_url

  default_root="/srv/apps"
  read -r -p "Target root directory [$default_root]: " target_root
  target_root="${target_root:-$default_root}"

  repo_dir="$(clone_or_update_repo "$repo_url" "$target_root" | tail -n 1)"
  echo "Repo ready at: $repo_dir"
}

main "$@"
