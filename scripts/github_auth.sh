#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

configure_git_identity() {
  local name email
  read -r -p "Git user.name (leave blank to skip): " name
  if [[ -n "$name" ]]; then
    git config --global user.name "$name"
  fi

  read -r -p "Git user.email (leave blank to skip): " email
  if [[ -n "$email" ]]; then
    git config --global user.email "$email"
  fi
}

setup_ssh_auth() {
  local key_path="$HOME/.ssh/id_ed25519_github"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [[ ! -f "$key_path" ]]; then
    read -r -p "Email for SSH key comment: " comment
    ssh-keygen -t ed25519 -C "$comment" -f "$key_path"
  fi

  if ! pgrep -u "$USER" ssh-agent >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null
  fi

  ssh-add "$key_path" >/dev/null 2>&1 || true

  local ssh_cfg="$HOME/.ssh/config"
  if [[ ! -f "$ssh_cfg" ]] || ! grep -q "Host github.com" "$ssh_cfg"; then
    {
      echo "Host github.com"
      echo "  HostName github.com"
      echo "  User git"
      echo "  IdentityFile $key_path"
      echo "  IdentitiesOnly yes"
    } >> "$ssh_cfg"
    chmod 600 "$ssh_cfg"
  fi

  echo
  echo "Add this public key to GitHub: https://github.com/settings/keys"
  echo "----- BEGIN PUBLIC KEY -----"
  cat "${key_path}.pub"
  echo "----- END PUBLIC KEY -----"
  echo
  read -r -p "Press Enter after adding the key to GitHub..."

  echo "Testing SSH authentication..."
  ssh -T git@github.com || true

  git config --global url."git@github.com:".insteadOf "https://github.com/"
  save_config_kv "AUTH_METHOD" "ssh"
  echo "SSH auth configured."
}

setup_pat_auth() {
  local username token
  read -r -p "GitHub username: " username
  read -r -s -p "GitHub Personal Access Token: " token
  echo

  git config --global credential.helper store
  local cred_file
  cred_file="$(git config --global --get credential.helper | awk '{print $NF}')"
  if [[ "$cred_file" == "store" || -z "$cred_file" ]]; then
    cred_file="$HOME/.git-credentials"
  fi

  printf 'https://%s:%s@github.com\n' "$username" "$token" > "$cred_file"
  chmod 600 "$cred_file"

  save_config_kv "AUTH_METHOD" "pat"
  echo "PAT auth configured using git credential store."
}

main() {
  require_cmd git
  require_cmd ssh-keygen

  print_header
  echo "GitHub Authentication Setup"
  echo "1) SSH key (recommended)"
  echo "2) Personal Access Token (HTTPS)"
  read -r -p "Choose auth method [1-2]: " choice

  configure_git_identity

  case "$choice" in
    1) setup_ssh_auth ;;
    2) setup_pat_auth ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
}

main "$@"
