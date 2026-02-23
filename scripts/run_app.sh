#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

show_help() {
  cat <<'TXT'
Usage: scripts/run_app.sh <repo_path>

Auto-detects common app types and runs a sensible dev command:
- Svelte/Node: npm install + npm run dev
- ASP.NET: dotnet restore + dotnet run
TXT
}

main() {
  local repo_path="${1:-}"
  if [[ -z "$repo_path" ]]; then
    show_help
    exit 1
  fi

  if [[ ! -d "$repo_path" ]]; then
    echo "$(c_menu "Path does not exist: $repo_path")"
    exit 1
  fi

  if [[ -f "$repo_path/package.json" ]]; then
    echo "$(c_node "Detected Node/Svelte app. Running npm install + npm run dev...")"
    (cd "$repo_path" && npm install && npm run dev)
    exit 0
  fi

  if compgen -G "$repo_path/*.sln" > /dev/null || compgen -G "$repo_path/*.csproj" > /dev/null; then
    echo "$(c_dotnet "Detected .NET app. Running dotnet restore + dotnet run...")"
    (cd "$repo_path" && dotnet restore && dotnet run)
    exit 0
  fi

  echo "$(c_menu "Could not detect app type.")"
  echo "$(c_menu "Try running manually in: $repo_path")"
  exit 1
}

main "$@"
