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

choose_dotnet_target() {
  local dotnet_choice custom_channel custom_version

  echo
  echo "Select .NET SDK target:"
  echo "1) .NET 10"
  echo "2) .NET 9"
  echo "3) .NET 8"
  echo "4) .NET 7"
  echo "5) .NET 6"
  echo "6) LTS channel"
  echo "7) STS channel"
  echo "8) Custom channel (for example 10.0)"
  echo "9) Exact SDK version (for example 10.0.100)"
  read -r -p "Choose [1-9]: " dotnet_choice

  DOTNET_INSTALL_CHANNEL=""
  DOTNET_INSTALL_VERSION=""

  case "$dotnet_choice" in
    1) DOTNET_INSTALL_CHANNEL="10.0" ;;
    2) DOTNET_INSTALL_CHANNEL="9.0" ;;
    3) DOTNET_INSTALL_CHANNEL="8.0" ;;
    4) DOTNET_INSTALL_CHANNEL="7.0" ;;
    5) DOTNET_INSTALL_CHANNEL="6.0" ;;
    6) DOTNET_INSTALL_CHANNEL="LTS" ;;
    7) DOTNET_INSTALL_CHANNEL="STS" ;;
    8)
      read -r -p "Enter custom channel (example: 10.0): " custom_channel
      DOTNET_INSTALL_CHANNEL="${custom_channel}"
      ;;
    9)
      read -r -p "Enter exact SDK version (example: 10.0.100): " custom_version
      DOTNET_INSTALL_VERSION="${custom_version}"
      ;;
    *)
      echo "Invalid choice"
      exit 1
      ;;
  esac

  if [[ -z "${DOTNET_INSTALL_CHANNEL}" && -z "${DOTNET_INSTALL_VERSION}" ]]; then
    echo "No .NET target provided."
    exit 1
  fi
}

install_dotnet_sdk() {
  local dotnet_args=()
  echo "Installing .NET SDK via dotnet-install script (user local)..."
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh

  if [[ -n "${DOTNET_INSTALL_VERSION:-}" ]]; then
    dotnet_args=(--version "$DOTNET_INSTALL_VERSION")
  else
    dotnet_args=(--channel "${DOTNET_INSTALL_CHANNEL:-STS}")
  fi

  bash /tmp/dotnet-install.sh "${dotnet_args[@]}" --install-dir "$HOME/.dotnet"
  ensure_dotnet_profile_exports
  activate_dotnet_path_now
  if ! command -v dotnet >/dev/null 2>&1; then
    echo "dotnet is still not in PATH after install."
    exit 1
  fi
  dotnet --list-sdks | tail -n 5 || true
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
      choose_dotnet_target
      install_dotnet_sdk
      save_config_kv "INSTALL_PROFILE" "full"
      save_config_kv "NODE_INSTALLED" "1"
      save_config_kv "DOTNET_INSTALLED" "1"
      save_config_kv "DOTNET_CHANNEL" "${DOTNET_INSTALL_CHANNEL:-}"
      save_config_kv "DOTNET_VERSION" "${DOTNET_INSTALL_VERSION:-}"
      echo "Toolchains installed and ready."
      ;;
    2)
      case "$os" in
        debian) install_node_debian ;;
        alpine) install_node_alpine ;;
      esac
      save_config_kv "INSTALL_PROFILE" "frontend"
      save_config_kv "NODE_INSTALLED" "1"
      save_config_kv "DOTNET_INSTALLED" "0"
      save_config_kv "DOTNET_CHANNEL" ""
      save_config_kv "DOTNET_VERSION" ""
      echo "Frontend toolchain installed."
      ;;
    3)
      choose_dotnet_target
      install_dotnet_sdk
      save_config_kv "INSTALL_PROFILE" "backend"
      save_config_kv "NODE_INSTALLED" "0"
      save_config_kv "DOTNET_INSTALLED" "1"
      save_config_kv "DOTNET_CHANNEL" "${DOTNET_INSTALL_CHANNEL:-}"
      save_config_kv "DOTNET_VERSION" "${DOTNET_INSTALL_VERSION:-}"
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
