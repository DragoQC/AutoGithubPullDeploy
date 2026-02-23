#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

main() {
  require_cmd ssh-keygen

  local key_path ssh_cfg email
  key_path="$HOME/.ssh/id_ed25519_github"

  print_header
  echo "$(c_menu "GitHub SSH Authentication")"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [[ ! -f "$key_path" ]]; then
    read -r -p "Email for SSH key comment: " email
    ssh-keygen -t ed25519 -C "$email" -f "$key_path"
  else
    echo "$(c_menu "Existing key found: $key_path")"
  fi

  ssh_cfg="$HOME/.ssh/config"
  touch "$ssh_cfg"
  chmod 600 "$ssh_cfg"

  if ! grep -q "Host github.com" "$ssh_cfg" 2>/dev/null; then
    {
      echo "Host github.com"
      echo "  HostName github.com"
      echo "  User git"
      echo "  IdentityFile $key_path"
      echo "  IdentitiesOnly yes"
    } >> "$ssh_cfg"
  fi

  if ! pgrep -u "$USER" ssh-agent >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null
  fi
  ssh-add "$key_path" >/dev/null 2>&1 || true

  echo
  echo "$(c_menu "Add this key to GitHub: https://github.com/settings/keys")"
  cat "$key_path.pub"
  echo
  read -r -p "Press Enter after adding the key to GitHub..."

  echo "$(c_menu "Testing SSH auth...")"
  ssh -T git@github.com || true
}

main "$@"
