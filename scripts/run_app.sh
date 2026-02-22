#!/usr/bin/env bash
set -euo pipefail

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
    echo "Path does not exist: $repo_path"
    exit 1
  fi

  if [[ -f "$repo_path/package.json" ]]; then
    (cd "$repo_path" && npm install && npm run dev)
    exit 0
  fi

  if compgen -G "$repo_path/*.sln" > /dev/null || compgen -G "$repo_path/*.csproj" > /dev/null; then
    (cd "$repo_path" && dotnet restore && dotnet run)
    exit 0
  fi

  echo "Could not detect app type."
  echo "Try running manually in: $repo_path"
  exit 1
}

main "$@"
