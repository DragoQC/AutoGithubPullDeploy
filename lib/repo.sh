#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

normalize_repo_url() {
  local url="$1"
  load_config

  if [[ "${AUTH_METHOD:-}" == "ssh" ]]; then
    if [[ "$url" =~ ^https://github.com/(.+)/(.+?)(\.git)?$ ]]; then
      local owner_repo
      owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
      echo "git@github.com:${owner_repo}.git"
      return
    fi
  fi

  echo "$url"
}

repo_name_from_url() {
  local url="$1"
  local base
  base="$(basename "$url")"
  echo "${base%.git}"
}

ensure_target_root() {
  local target_root="$1"

  if mkdir -p "$target_root" 2>/dev/null; then
    :
  else
    sudo_if_needed mkdir -p "$target_root"
  fi

  if [[ ! -w "$target_root" ]]; then
    sudo_if_needed chown "$USER:$(id -gn)" "$target_root"
  fi
}

clone_or_update_repo() {
  local raw_url="$1"
  local target_root="$2"
  local url repo_name target_dir

  url="$(normalize_repo_url "$raw_url")"
  repo_name="$(repo_name_from_url "$url")"

  ensure_target_root "$target_root"
  target_dir="$target_root/$repo_name"

  if [[ -d "$target_dir/.git" ]]; then
    echo "Repository exists. Pulling latest changes..."
    git -C "$target_dir" pull --ff-only
  else
    echo "Cloning repository..."
    git clone "$url" "$target_dir"
  fi

  echo "$target_dir"
}
