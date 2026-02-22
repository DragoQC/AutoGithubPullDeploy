#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

install_base_deps_debian() {
  sudo_if_needed apt-get update
  sudo_if_needed apt-get install -y \
    bash curl ca-certificates git openssh-client sudo gnupg lsb-release
}

install_base_deps_alpine() {
  sudo_if_needed apk update
  sudo_if_needed apk add --no-cache \
    bash curl ca-certificates git openssh-client sudo
}

install_node_debian() {
  sudo_if_needed apt-get install -y nodejs npm
}

install_node_alpine() {
  sudo_if_needed apk add --no-cache nodejs npm
}

ensure_dotnet_profile_exports() {
  local profile
  for profile in "$HOME/.profile" "$HOME/.bashrc"; do
    touch "$profile"
    if ! grep -q 'DOTNET_ROOT="$HOME/.dotnet"' "$profile" 2>/dev/null; then
      echo 'export DOTNET_ROOT="$HOME/.dotnet"' >> "$profile"
    fi
    if ! grep -q 'HOME/.dotnet/tools' "$profile" 2>/dev/null; then
      echo 'export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"' >> "$profile"
    fi
  done
}

activate_dotnet_path_now() {
  export DOTNET_ROOT="$HOME/.dotnet"
  export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
}

install_dotnet_sdk() {
  echo "Installing .NET SDK via dotnet-install script (user local)..."
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --channel STS --install-dir "$HOME/.dotnet"
  ensure_dotnet_profile_exports
  activate_dotnet_path_now
  if ! command -v dotnet >/dev/null 2>&1; then
    echo "dotnet is still not in PATH after install."
    exit 1
  fi
}

main() {
  local os choice
  os="$(detect_os)"

  case "$os" in
    debian)
      echo "Detected Debian-like OS"
      install_base_deps_debian
      ;;
    alpine)
      echo "Detected Alpine Linux"
      install_base_deps_alpine
      ;;
    *)
      echo "Unsupported OS. Supported: Debian-like and Alpine."
      exit 1
      ;;
  esac

  echo
  echo "Install app toolchains:"
  echo "1) Frontend + Backend (Node + .NET SDK)"
  echo "2) Frontend only (Node)"
  echo "3) Backend only (.NET SDK)"
  echo "0) Skip"
  read -r -p "Choose [0-3]: " choice

  case "$choice" in
    1)
      case "$os" in
        debian) install_node_debian ;;
        alpine) install_node_alpine ;;
      esac
      install_dotnet_sdk
      echo "Toolchains installed and ready."
      ;;
    2)
      case "$os" in
        debian) install_node_debian ;;
        alpine) install_node_alpine ;;
      esac
      echo "Frontend toolchain installed."
      ;;
    3)
      install_dotnet_sdk
      echo "Backend toolchain installed and ready."
      ;;
    0)
      echo "Skipping toolchain installation."
      ;;
    *)
      echo "Invalid choice"
      exit 1
      ;;
  esac

  echo "Dependencies setup complete."
}

main "$@"
