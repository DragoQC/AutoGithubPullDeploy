# AutoGithubPullDeploy

Interactive Bash toolkit to:
- Install dependencies on Debian-like and Alpine systems
- Configure GitHub authentication for private repositories
- Deploy backend, frontend, or both from one repo as OS services
- Pull updates, run backend migrations, and restart services
- Schedule automatic update checks
- Optionally install and configure MariaDB during deploy

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
- `scripts/install_database.sh`: MariaDB installer/configurator

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
For .NET SDK, installer lets you choose 6/7/8/9/10, LTS/STS, custom channel, or exact version.

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
Backend/frontend path prompts now auto-detect common names (for example `Backend`, `backend`, `FrontEnd`, `Front end`) and will keep prompting instead of exiting on first typo.

## Migrations during updates

Each deployment stores `MIGRATION_CMD` (default: `dotnet ef database update`).

When `update_deployed.sh <app> [frontend|backend|both]` runs, it does:
1. `git pull --ff-only`
2. sync missing env keys from repo `.env.example` into deployed env files
3. frontend dependency install (`npm install`) if frontend enabled
4. backend dependency restore (`dotnet restore`) if backend enabled
5. backend migration command if backend enabled
6. restart only updated services

## Config files

During deployment:

- Backend uses `appsettings.example.json` (from backend project) to create `appsettings.json` in the backend folder.
- Frontend uses env file: `~/.config/agpd/env/<app>/frontend.env`

Frontend `.env.example` is copied on first deploy, and missing keys are appended on update.

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

## Cleanup / Fresh Start

Use menu option `8) Cleanup installed deployments/services` to remove previously managed app services and deployment records.

It can:
- stop/disable and remove backend/frontend services
- remove update timers (Debian/systemd) or update cron entries (Alpine/openrc)
- remove saved deployment records/env files
- optionally remove checked-out repo folders (for example under `/srv/apps`)
- optionally remove installed toolchains (Node/npm and user-local .NET SDK)
- optionally reset saved toolchain markers in `~/.config/agpd/config.env`
- optionally drop configured database/user using `/etc/agpd/db-credentials.env`

## Database Setup Details

Deploy option `3` can run MariaDB setup during backend deployment. The setup wizard can:
- choose localhost-only or external access
- set app DB name/user/password
- optionally set root DB password
- apply secure defaults (remove anonymous users/test DB)
- save credentials to: `/etc/agpd/db-credentials.env` (mode `600`)

For external access, it sets `bind-address=0.0.0.0` and creates DB user host `%`.
For local-only access, it sets `bind-address=127.0.0.1` and creates DB user host `localhost`.
