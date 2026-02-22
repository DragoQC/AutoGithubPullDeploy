#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

sanitize_app_name() {
  local app="$1"
  app="${app,,}"
  app="${app// /-}"
  app="${app//_/\-}"
  app="${app//[^a-z0-9\-]/}"
  printf '%s' "$app"
}

app_env_file() {
  local app
  app="$(sanitize_app_name "$1")"
  printf '%s/%s.env' "$APPS_DIR" "$app"
}

app_env_dir() {
  local app
  app="$(sanitize_app_name "$1")"
  printf '%s/env/%s' "$CONFIG_DIR" "$app"
}

save_app_kv() {
  local app="$1"
  local key="$2"
  local value="$3"
  local file
  file="$(app_env_file "$app")"

  mkdir -p "$APPS_DIR"
  touch "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

env_key_exists() {
  local file="$1"
  local key="$2"
  grep -Eq "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file"
}

append_missing_env_lines() {
  local example_file="$1"
  local env_file="$2"
  local appended=0
  local line stripped key

  [[ -n "$env_file" ]] || return 0
  [[ -f "$example_file" ]] || return 0
  mkdir -p "$(dirname "$env_file")"
  touch "$env_file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    stripped="${line#"${line%%[![:space:]]*}"}"
    stripped="${stripped#export }"

    if [[ "$stripped" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      key="${BASH_REMATCH[1]}"
      if ! env_key_exists "$env_file" "$key"; then
        printf '%s\n' "$line" >> "$env_file"
        appended=$((appended + 1))
      fi
    fi
  done < "$example_file"

  if [[ $appended -gt 0 ]]; then
    echo "Appended $appended new env entries from $example_file into $env_file"
  fi
}

ensure_env_file_from_example() {
  local env_file="$1"
  local example_file="$2"
  local fallback_header="$3"

  mkdir -p "$(dirname "$env_file")"

  if [[ ! -f "$env_file" ]]; then
    if [[ -f "$example_file" ]]; then
      cp "$example_file" "$env_file"
    else
      printf '%s\n' "$fallback_header" > "$env_file"
    fi
  fi

  append_missing_env_lines "$example_file" "$env_file"
  chmod 600 "$env_file"
}

load_app_env() {
  local app="$1"
  local file
  file="$(app_env_file "$app")"
  if [[ ! -f "$file" ]]; then
    echo "Deployment not found for app: $app"
    return 1
  fi

  # shellcheck disable=SC1090
  source "$file"
}

list_apps() {
  mkdir -p "$APPS_DIR"
  local found=0
  local file
  for file in "$APPS_DIR"/*.env; do
    if [[ -f "$file" ]]; then
      basename "$file" .env
      found=1
    fi
  done
  if [[ $found -eq 0 ]]; then
    return 1
  fi
}
