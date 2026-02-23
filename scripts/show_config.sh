#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

main() {
  load_config
  print_header
  echo "$(c_menu "Current config file: $CONFIG_FILE")"
  if [[ -f "$CONFIG_FILE" ]]; then
    sed 's/^/  /' "$CONFIG_FILE"
  else
    echo "  (not configured)"
  fi
}

main "$@"
