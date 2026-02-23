#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

install_base_deps_debian() {
  sudo_if_needed apt-get update
  sudo_if_needed apt-get install -y bash curl ca-certificates git openssh-client sudo gnupg
}

install_base_deps_alpine() {
  sudo_if_needed apk update
  sudo_if_needed apk add --no-cache bash curl ca-certificates git openssh-client sudo
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
    grep -q 'DOTNET_ROOT="$HOME/.dotnet"' "$profile" 2>/dev/null || echo 'export DOTNET_ROOT="$HOME/.dotnet"' >> "$profile"
    grep -q 'HOME/.dotnet/tools' "$profile" 2>/dev/null || echo 'export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"' >> "$profile"
    grep -q 'DOTNET_CLI_TELEMETRY_OPTOUT=' "$profile" 2>/dev/null || echo 'export DOTNET_CLI_TELEMETRY_OPTOUT="1"' >> "$profile"
    grep -q 'DOTNET_SKIP_FIRST_TIME_EXPERIENCE=' "$profile" 2>/dev/null || echo 'export DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1"' >> "$profile"
  done
}

activate_dotnet_now() {
  export DOTNET_ROOT="$HOME/.dotnet"
  export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
  export DOTNET_CLI_TELEMETRY_OPTOUT="1"
  export DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1"
}

install_dotnet_sdk() {
  local channel="10.0"
  echo "$(c_dotnet "Installing .NET SDK channel: $channel")"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    bash /tmp/dotnet-install.sh --channel "$channel" --install-dir "$HOME/.dotnet"
  ensure_dotnet_profile_exports
  activate_dotnet_now
  dotnet --list-sdks | tail -n 5 || true
}

main() {
  local os choice
  os="$(detect_os)"

  case "$os" in
    debian) install_base_deps_debian ;;
    alpine) install_base_deps_alpine ;;
    *) echo "Unsupported OS"; exit 1 ;;
  esac

  echo "$(c_menu "Install runtime toolchains:")"
  echo "$(c_menu "1) Node + .NET")"
  echo "$(c_node "2) Node only")"
  echo "$(c_dotnet "3) .NET only")"
  echo "$(c_menu "0) Base deps only")"
  read -r -p "Choose [0-3]: " choice

  case "$choice" in
    1)
      case "$os" in debian) install_node_debian ;; alpine) install_node_alpine ;; esac
      install_dotnet_sdk
      ;;
    2)
      case "$os" in debian) install_node_debian ;; alpine) install_node_alpine ;; esac
      ;;
    3)
      install_dotnet_sdk
      ;;
    0) ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac

  echo "Dependencies installed."
}

main "$@"
