#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/repo.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/deploy.sh"

write_systemd_service() {
  local service_name="$1"
  local workdir="$2"
  local command="$3"
  local env_file="$4"
  local file="/etc/systemd/system/${service_name}.service"

  sudo_if_needed tee "$file" >/dev/null <<EOF_SERVICE
[Unit]
Description=${service_name}
After=network.target

[Service]
Type=simple
User=$USER
Group=$(id -gn)
WorkingDirectory=$workdir
Environment=HOME=$HOME
ExecStart=/usr/bin/env bash -lc 'export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"; if [[ -f "$env_file" ]]; then set -a; source "$env_file"; set +a; fi; exec ${command}'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SERVICE

  sudo_if_needed systemctl daemon-reload
  sudo_if_needed systemctl enable --now "${service_name}.service"
}

write_openrc_service() {
  local service_name="$1"
  local workdir="$2"
  local command="$3"
  local env_file="$4"
  local file="/etc/init.d/${service_name}"

  sudo_if_needed tee "$file" >/dev/null <<EOF_OPENRC
#!/sbin/openrc-run
name="${service_name}"
description="${service_name}"
directory="${workdir}"
command="/bin/sh"
command_args="-lc 'export DOTNET_ROOT=\"$HOME/.dotnet\"; export PATH=\"$HOME/.dotnet:$HOME/.dotnet/tools:$PATH\"; if [ -f \"$env_file\" ]; then set -a; . \"$env_file\"; set +a; fi; exec ${command}'"
command_user="$USER:$(id -gn)"
pidfile="/run/${service_name}.pid"
command_background="yes"
output_log="/var/log/${service_name}.log"
error_log="/var/log/${service_name}.err.log"
EOF_OPENRC

  sudo_if_needed chmod +x "$file"
  sudo_if_needed rc-update add "$service_name" default
  sudo_if_needed rc-service "$service_name" restart || sudo_if_needed rc-service "$service_name" start
}

main() {
  require_cmd git
  load_config

  print_header
  echo "Deploy App Services"

  local app_name repo_url target_root repo_dir backend_rel="" frontend_rel="" backend_cmd="" frontend_cmd="" migration_cmd="" os
  local env_root backend_env_file="" frontend_env_file="" backend_example="" frontend_example="" backend_example_input="" frontend_example_input=""
  local component_choice enable_backend enable_frontend existing_enable_backend existing_enable_frontend
  local backend_service frontend_service
  enable_backend=1
  enable_frontend=1

  read -r -p "Deployment name (e.g. myapp): " app_name
  app_name="$(sanitize_app_name "$app_name")"
  if [[ -z "$app_name" ]]; then
    echo "Invalid app name"
    exit 1
  fi

  read -r -p "GitHub repo URL: " repo_url
  read -r -p "Target root directory [/srv/apps]: " target_root
  target_root="${target_root:-/srv/apps}"

  repo_dir="$(clone_or_update_repo "$repo_url" "$target_root")"
  echo "Repo ready at: $repo_dir"

  if [[ -f "$(app_env_file "$app_name")" ]]; then
    load_app_env "$app_name"
    existing_enable_backend="${ENABLE_BACKEND:-1}"
    existing_enable_frontend="${ENABLE_FRONTEND:-1}"
    enable_backend="$existing_enable_backend"
    enable_frontend="$existing_enable_frontend"
    echo
    echo "Existing deployment detected for $app_name."
    echo "Component mode is locked: backend=$enable_backend, frontend=$enable_frontend"
  else
    echo
    echo "Deploy components:"
    echo "1) Backend + Frontend"
    echo "2) Backend only"
    echo "3) Frontend only"
    read -r -p "Choose [1-3]: " component_choice
    case "$component_choice" in
      1) enable_backend=1; enable_frontend=1 ;;
      2) enable_backend=1; enable_frontend=0 ;;
      3) enable_backend=0; enable_frontend=1 ;;
      *) echo "Invalid choice"; exit 1 ;;
    esac
  fi

  if [[ $enable_backend -eq 1 ]]; then
    read -r -p "Backend path inside repo (e.g. backend/Api): " backend_rel
    if [[ ! -d "$repo_dir/$backend_rel" ]]; then
      echo "Backend path not found: $repo_dir/$backend_rel"
      exit 1
    fi
  fi

  if [[ $enable_frontend -eq 1 ]]; then
    read -r -p "Frontend path inside repo (e.g. frontend): " frontend_rel
    if [[ ! -d "$repo_dir/$frontend_rel" ]]; then
      echo "Frontend path not found: $repo_dir/$frontend_rel"
      exit 1
    fi
  fi

  env_root="$(app_env_dir "$app_name")"
  mkdir -p "$env_root"
  backend_env_file="$env_root/backend.env"
  frontend_env_file="$env_root/frontend.env"

  backend_example="$repo_dir/$backend_rel/.env.example"
  frontend_example="$repo_dir/$frontend_rel/.env.example"

  if [[ $enable_backend -eq 1 ]]; then
    read -r -p "Backend .env.example path [$backend_example] (type none to skip): " backend_example_input
    backend_example_input="${backend_example_input:-$backend_example}"
    if [[ "${backend_example_input,,}" == "none" ]]; then
      backend_example_input=""
    fi
    ensure_env_file_from_example "$backend_env_file" "$backend_example_input" \
      "# Backend env for $app_name"$'\n'"# ASPNETCORE_ENVIRONMENT=Production"$'\n'"# ConnectionStrings__DefaultConnection=Host=...;Database=...;Username=...;Password=..."

    read -r -p "Backend start command [dotnet run --configuration Release --urls http://0.0.0.0:5000]: " backend_cmd
    backend_cmd="${backend_cmd:-dotnet run --configuration Release --urls http://0.0.0.0:5000}"

    read -r -p "Migration command [dotnet ef database update] (type none to skip): " migration_cmd
    migration_cmd="${migration_cmd:-dotnet ef database update}"
    if [[ "${migration_cmd,,}" == "none" ]]; then
      migration_cmd=""
    fi
  else
    backend_rel=""
    backend_cmd=""
    migration_cmd=""
    backend_env_file=""
  fi

  if [[ $enable_frontend -eq 1 ]]; then
    read -r -p "Frontend .env.example path [$frontend_example] (type none to skip): " frontend_example_input
    frontend_example_input="${frontend_example_input:-$frontend_example}"
    if [[ "${frontend_example_input,,}" == "none" ]]; then
      frontend_example_input=""
    fi
    ensure_env_file_from_example "$frontend_env_file" "$frontend_example_input" \
      "# Frontend env for $app_name"$'\n'"# VITE_API_BASE_URL=https://api.example.com"

    read -r -p "Frontend start command [npm run dev -- --host 0.0.0.0 --port 4173]: " frontend_cmd
    frontend_cmd="${frontend_cmd:-npm run dev -- --host 0.0.0.0 --port 4173}"
  else
    frontend_rel=""
    frontend_cmd=""
    frontend_env_file=""
  fi

  os="$(detect_os)"
  case "$os" in
    debian)
      if [[ $enable_backend -eq 1 ]]; then
        write_systemd_service "${app_name}-backend" "$repo_dir/$backend_rel" "$backend_cmd" "$backend_env_file"
      fi
      if [[ $enable_frontend -eq 1 ]]; then
        write_systemd_service "${app_name}-frontend" "$repo_dir/$frontend_rel" "$frontend_cmd" "$frontend_env_file"
      fi
      ;;
    alpine)
      if [[ $enable_backend -eq 1 ]]; then
        write_openrc_service "${app_name}-backend" "$repo_dir/$backend_rel" "$backend_cmd" "$backend_env_file"
      fi
      if [[ $enable_frontend -eq 1 ]]; then
        write_openrc_service "${app_name}-frontend" "$repo_dir/$frontend_rel" "$frontend_cmd" "$frontend_env_file"
      fi
      ;;
    *)
      echo "Unsupported OS for service setup"
      exit 1
      ;;
  esac

  backend_service=""
  frontend_service=""
  if [[ $enable_backend -eq 1 ]]; then
    backend_service="${app_name}-backend"
  fi
  if [[ $enable_frontend -eq 1 ]]; then
    frontend_service="${app_name}-frontend"
  fi

  save_app_kv "$app_name" "APP_NAME" "$app_name"
  save_app_kv "$app_name" "REPO_URL" "$repo_url"
  save_app_kv "$app_name" "REPO_DIR" "$repo_dir"
  save_app_kv "$app_name" "ENABLE_BACKEND" "$enable_backend"
  save_app_kv "$app_name" "ENABLE_FRONTEND" "$enable_frontend"
  save_app_kv "$app_name" "BACKEND_REL" "$backend_rel"
  save_app_kv "$app_name" "FRONTEND_REL" "$frontend_rel"
  save_app_kv "$app_name" "BACKEND_SERVICE" "$backend_service"
  save_app_kv "$app_name" "FRONTEND_SERVICE" "$frontend_service"
  save_app_kv "$app_name" "MIGRATION_CMD" "$migration_cmd"
  save_app_kv "$app_name" "DEPLOY_USER" "$USER"
  save_app_kv "$app_name" "DEPLOY_HOME" "$HOME"
  save_app_kv "$app_name" "BACKEND_ENV_FILE" "$backend_env_file"
  save_app_kv "$app_name" "FRONTEND_ENV_FILE" "$frontend_env_file"

  echo
  echo "Deployment registered: $app_name"
  echo "Backend env file: $backend_env_file"
  echo "Frontend env file: $frontend_env_file"
  echo "You can now run updates with scripts/update_deployed.sh $app_name"
}

main "$@"
