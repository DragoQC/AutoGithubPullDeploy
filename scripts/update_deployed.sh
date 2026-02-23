#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/deploy.sh"

run_as_deploy_user() {
  local cmd="$1"
  local preamble='export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"; export DOTNET_CLI_TELEMETRY_OPTOUT="1"; export DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1"; export ASPNETCORE_ENVIRONMENT="Production"; '
  if [[ "$(id -u)" -eq 0 ]]; then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$DEPLOY_USER" -- bash -lc "${preamble}${cmd}"
    else
      su - "$DEPLOY_USER" -c "${preamble}${cmd}"
    fi
  else
    bash -lc "${preamble}${cmd}"
  fi
}

run_in_dir_with_env() {
  local dir="$1"
  local env_file="$2"
  local cmd="$3"
  local script=""

  script+="cd '$dir' && "
  if [[ -n "$env_file" ]]; then
    script+="if [[ -f '$env_file' ]]; then set -a; source '$env_file'; set +a; fi; "
  fi
  script+="$cmd"

  run_as_deploy_user "$script"
}

restart_services() {
  local do_backend="$1"
  local do_frontend="$2"
  local os
  os="$(detect_os)"
  case "$os" in
    debian)
      if [[ "$(id -u)" -eq 0 ]]; then
        if [[ "$do_backend" == "1" && -n "${BACKEND_SERVICE:-}" ]]; then
          systemctl restart "${BACKEND_SERVICE}.service"
        fi
        if [[ "$do_frontend" == "1" && -n "${FRONTEND_SERVICE:-}" ]]; then
          systemctl restart "${FRONTEND_SERVICE}.service"
        fi
      else
        if [[ "$do_backend" == "1" && -n "${BACKEND_SERVICE:-}" ]]; then
          sudo_if_needed systemctl restart "${BACKEND_SERVICE}.service"
        fi
        if [[ "$do_frontend" == "1" && -n "${FRONTEND_SERVICE:-}" ]]; then
          sudo_if_needed systemctl restart "${FRONTEND_SERVICE}.service"
        fi
      fi
      ;;
    alpine)
      if [[ "$(id -u)" -eq 0 ]]; then
        if [[ "$do_backend" == "1" && -n "${BACKEND_SERVICE:-}" ]]; then
          rc-service "$BACKEND_SERVICE" restart
        fi
        if [[ "$do_frontend" == "1" && -n "${FRONTEND_SERVICE:-}" ]]; then
          rc-service "$FRONTEND_SERVICE" restart
        fi
      else
        if [[ "$do_backend" == "1" && -n "${BACKEND_SERVICE:-}" ]]; then
          sudo_if_needed rc-service "$BACKEND_SERVICE" restart
        fi
        if [[ "$do_frontend" == "1" && -n "${FRONTEND_SERVICE:-}" ]]; then
          sudo_if_needed rc-service "$FRONTEND_SERVICE" restart
        fi
      fi
      ;;
    *)
      echo "Unsupported OS"
      exit 1
      ;;
  esac
}

main() {
  local app_name="${1:-}"
  local target="${2:-}"
  local do_frontend=0
  local do_backend=0

  if [[ -z "$app_name" ]]; then
    echo "Usage: $0 <app_name> [frontend|backend|both]"
    exit 1
  fi

  load_app_env "$app_name"

  echo "Updating deployment: $APP_NAME"
  echo "Repo: $REPO_DIR"

  if [[ -z "$target" ]]; then
    if [[ "${ENABLE_BACKEND:-1}" == "1" && "${ENABLE_FRONTEND:-1}" == "1" ]]; then
      if [[ -t 0 ]]; then
        echo "Update target:"
        echo "1) Backend + Frontend"
        echo "2) Backend only"
        echo "3) Frontend only"
        read -r -p "Choose [1-3]: " target
        case "$target" in
          1) target="both" ;;
          2) target="backend" ;;
          3) target="frontend" ;;
          *) echo "Invalid choice"; exit 1 ;;
        esac
      else
        target="both"
      fi
    elif [[ "${ENABLE_BACKEND:-1}" == "1" ]]; then
      target="backend"
    elif [[ "${ENABLE_FRONTEND:-1}" == "1" ]]; then
      target="frontend"
    else
      echo "No enabled components for app: $app_name"
      exit 1
    fi
  fi

  case "$target" in
    both)
      do_backend=1
      do_frontend=1
      ;;
    backend)
      do_backend=1
      ;;
    frontend)
      do_frontend=1
      ;;
    *)
      echo "Invalid target: $target"
      echo "Allowed: frontend, backend, both"
      exit 1
      ;;
  esac

  if [[ $do_backend -eq 1 && "${ENABLE_BACKEND:-1}" != "1" ]]; then
    echo "Backend is not enabled for this deployment."
    exit 1
  fi
  if [[ $do_frontend -eq 1 && "${ENABLE_FRONTEND:-1}" != "1" ]]; then
    echo "Frontend is not enabled for this deployment."
    exit 1
  fi

  run_as_deploy_user "git -C '$REPO_DIR' pull --ff-only"

  if [[ $do_frontend -eq 1 && -n "${FRONTEND_REL:-}" ]]; then
    append_missing_env_lines "$REPO_DIR/$FRONTEND_REL/.env.example" "${FRONTEND_ENV_FILE:-}"
    run_in_dir_with_env "$REPO_DIR/$FRONTEND_REL" "${FRONTEND_ENV_FILE:-}" "npm install"
  fi

  if [[ $do_backend -eq 1 && -n "${BACKEND_REL:-}" ]]; then
    if [[ -z "${BACKEND_APPSETTINGS_FILE:-}" ]]; then
      BACKEND_APPSETTINGS_FILE="$REPO_DIR/$BACKEND_REL/appsettings.json"
    fi
    if [[ -n "${BACKEND_APPSETTINGS_FILE:-}" && ! -f "${BACKEND_APPSETTINGS_FILE}" && -f "$REPO_DIR/$BACKEND_REL/appsettings.example.json" ]]; then
      cp "$REPO_DIR/$BACKEND_REL/appsettings.example.json" "${BACKEND_APPSETTINGS_FILE}"
      echo "Created missing backend appsettings from example: ${BACKEND_APPSETTINGS_FILE}"
    fi
    run_in_dir_with_env "$REPO_DIR/$BACKEND_REL" "" "dotnet restore"
  fi

  if [[ $do_backend -eq 1 && -n "${MIGRATION_CMD:-}" && -n "${BACKEND_REL:-}" ]]; then
    echo "Applying migrations..."
    run_in_dir_with_env "$REPO_DIR/$BACKEND_REL" "" "$MIGRATION_CMD"
  fi

  echo "Restarting services..."
  restart_services "$do_backend" "$do_frontend"

  echo "Update complete for $APP_NAME"
}

main "$@"
