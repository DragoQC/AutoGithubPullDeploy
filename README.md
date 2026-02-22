# AutoGithubPullDeploy

Interactive Bash toolkit to:
- Install dependencies on Debian-like and Alpine systems
- Configure GitHub authentication for private repositories
- Deploy backend, frontend, or both from one repo as OS services
- Pull updates, run backend migrations, and restart services
- Schedule automatic update checks

## Files

- `install.sh`: bootstrap entrypoint
- `main.sh`: interactive menu
- `lib/common.sh`: shared helpers/config paths
- `lib/repo.sh`: repo clone/pull helpers
- `lib/deploy.sh`: deployment record helpers
- `scripts/install_deps.sh`: dependency and toolchain installation
- `scripts/github_auth.sh`: GitHub auth setup (SSH/PAT)
- `scripts/pull_repo.sh`: manual clone/update for any repo URL
- `scripts/deploy_stack.sh`: deploy frontend/backend services and store config
- `scripts/update_deployed.sh`: pull + restore + migrate + restart for one deployed app
- `scripts/schedule_updates.sh`: configure periodic auto-updates
- `scripts/run_app.sh`: local dev runner for Node or ASP.NET

## Quick Start

```bash
chmod +x install.sh main.sh scripts/*.sh
./install.sh
```

## Recommended flow

1. `Install dependencies`
2. `Setup GitHub authentication`
3. `Deploy app services (backend/frontend/both)`
4. `Configure automatic update schedule`

Default repository root is `/srv/apps`.
If `/srv/apps` is not writable, the script creates it with `sudo` and assigns ownership to the deploy user.

Toolchain install supports:
- frontend only: Node
- backend only: .NET SDK
- both: Node + .NET SDK

## Service behavior

### Debian-like

`deploy_stack.sh` creates and enables selected service(s):
- `/etc/systemd/system/<app>-backend.service` (if backend enabled)
- `/etc/systemd/system/<app>-frontend.service` (if frontend enabled)

Use:

```bash
sudo systemctl status <app>-backend.service
sudo systemctl status <app>-frontend.service
```

### Alpine

`deploy_stack.sh` creates and enables selected service(s):
- `/etc/init.d/<app>-backend` (if backend enabled)
- `/etc/init.d/<app>-frontend` (if frontend enabled)

Use:

```bash
sudo rc-service <app>-backend status
sudo rc-service <app>-frontend status
```

Component mode is locked per app after first deploy.  
If an app was created as backend-only, you cannot later add frontend to that same app name (and vice versa).

## Migrations during updates

Each deployment stores `MIGRATION_CMD` (default: `dotnet ef database update`).

When `update_deployed.sh <app> [frontend|backend|both]` runs, it does:
1. `git pull --ff-only`
2. sync missing env keys from repo `.env.example` into deployed env files
3. frontend dependency install (`npm install`) if frontend enabled
4. backend dependency restore (`dotnet restore`) if backend enabled
5. backend migration command if backend enabled
6. restart only updated services

## Environment files

During deployment, the script creates two env files per app:

- `~/.config/agpd/env/<app>/backend.env`
- `~/.config/agpd/env/<app>/frontend.env`

If `.env.example` exists in backend/frontend project directories, it is copied to these files on first deploy.
On deploy and on each update, any new keys found in `.env.example` are appended to existing env files (existing keys are left unchanged).

These files are loaded by the created services and also loaded before migrations in `update_deployed.sh`.

### ASP.NET `appsettings` override with env vars

Use double underscore `__` to map nested config keys:

- `ConnectionStrings__DefaultConnection=...`
- `Logging__LogLevel__Default=Information`
- `Jwt__Authority=https://...`

`ASPNETCORE_ENVIRONMENT=Production` is also commonly set in `backend.env`.

### Svelte / Vite env vars

Use `VITE_` prefix for variables exposed to frontend code:

- `VITE_API_BASE_URL=https://api.example.com`

Put these in `frontend.env`.

## Automatic pull + update

- Debian-like: creates `systemd` timer/service `agpd-update-<app>.timer`
- Alpine: creates root cron entry for periodic `update_deployed.sh <app>`

## Deployment records

Per-app settings are stored in:

- `~/.config/agpd/apps/<app>.env`

This includes repo URL/path, service names, and migration command.

## Notes

- For private repos with unattended updates, use SSH keys without interactive prompts, or PAT auth.
- If `dotnet ef` is missing, install it for your user:

```bash
dotnet tool install --global dotnet-ef
```

## Fresh LXC Bootstrap (curl | bash)

This repo uses `install.sh` for first-time machine bootstrap. It installs prerequisites, clones/updates this repo to `/opt/AutoGithubPullDeploy`, and launches the installer menu.

Debian/Ubuntu LXC:

```bash
apt update && apt upgrade -y && apt install -y curl
bash -c "$(curl -fsSL https://raw.githubusercontent.com/DragoQC/AutoGithubPullDeploy/main/install.sh)"
```

Alpine LXC:

```sh
apk update && apk upgrade && apk add --no-cache curl
sh -c "$(curl -fsSL https://raw.githubusercontent.com/DragoQC/AutoGithubPullDeploy/main/install.sh)"
```

Optional overrides:

- `AGPD_REPO_URL` to point to another repo URL
- `AGPD_INSTALL_DIR` to change install directory (default `/opt/AutoGithubPullDeploy`)
