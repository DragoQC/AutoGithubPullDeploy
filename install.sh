#!/bin/sh
set -eu

REPO_URL="${AGPD_REPO_URL:-https://github.com/DragoQC/AutoGithubPullDeploy.git}"
INSTALL_DIR="${AGPD_INSTALL_DIR:-/opt/AutoGithubPullDeploy}"

need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    echo ""
  else
    echo "sudo"
  fi
}

detect_os() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

install_prereqs() {
  os="$(detect_os)"
  SUDO="$(need_sudo)"

  case "$os" in
    debian|ubuntu|linuxmint|pop)
      $SUDO apt-get update
      $SUDO apt-get install -y bash curl git ca-certificates openssh-client sudo
      ;;
    alpine)
      $SUDO apk update
      $SUDO apk add --no-cache bash curl git ca-certificates openssh-client sudo
      ;;
    *)
      echo "Unsupported OS: $os"
      echo "Supported: Debian-like, Alpine"
      exit 1
      ;;
  esac
}

script_dir() {
  if cd -- "$(dirname -- "$0")" 2>/dev/null; then
    pwd -P
  else
    echo ""
  fi
}

has_local_repo() {
  d="$1"
  [ -n "$d" ] && [ -f "$d/main.sh" ] && [ -d "$d/scripts" ] && [ -d "$d/lib" ]
}

update_existing_repo() {
  SUDO="$(need_sudo)"
  ts="$(date +%Y%m%d-%H%M%S)"
  stash_name="agpd-autostash-$ts"

  if $SUDO git -C "$INSTALL_DIR" diff --quiet && $SUDO git -C "$INSTALL_DIR" diff --cached --quiet; then
    $SUDO git -C "$INSTALL_DIR" pull --ff-only
    return 0
  fi

  echo "Local changes detected in $INSTALL_DIR. Auto-stashing before update..."
  $SUDO git -C "$INSTALL_DIR" stash push -u -m "$stash_name" >/dev/null 2>&1 || true
  $SUDO git -C "$INSTALL_DIR" pull --ff-only

  if $SUDO git -C "$INSTALL_DIR" stash list | grep -q "$stash_name"; then
    echo "Re-applying local changes from stash..."
    if ! $SUDO git -C "$INSTALL_DIR" stash pop >/dev/null 2>&1; then
      echo "Warning: could not auto-apply local changes cleanly."
      echo "Your changes are still saved in git stash at: $INSTALL_DIR"
      echo "Run: sudo git -C $INSTALL_DIR stash list"
    fi
  fi
}

ensure_repo() {
  SUDO="$(need_sudo)"
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    $SUDO mkdir -p "$(dirname "$INSTALL_DIR")"
    $SUDO git clone "$REPO_URL" "$INSTALL_DIR"
  else
    update_existing_repo
  fi

  $SUDO chmod +x "$INSTALL_DIR/install.sh" "$INSTALL_DIR/main.sh" "$INSTALL_DIR"/scripts/*.sh
}

run_local_repo() {
  d="$1"
  exec bash "$d/main.sh"
}

run_installed_repo() {
  exec bash "$INSTALL_DIR/main.sh"
}

main() {
  install_prereqs

  d="$(script_dir)"
  if has_local_repo "$d"; then
    run_local_repo "$d"
  fi

  ensure_repo
  run_installed_repo
}

main "$@"
