# AutoGithubPullDeploy (Simple Mode)

Minimal Bash toolkit for one app deployment flow:
- Install dependencies (git/curl/node/dotnet)
- Generate/setup GitHub SSH key authentication
- Install + configure MariaDB
- Clone one GitHub repo into `/srv/apps/<app>`
- Create `agpd-update` command
- Setup cron to auto-run update
- Update flow: delete old code, re-clone repo, run DB migration

Note: repository operations are SSH-only (`git@github.com:owner/repo.git`).

## Files

- `install.sh`: bootstrap installer (clone/update repo into `/opt/AutoGithubPullDeploy` and open menu)
- `main.sh`: interactive menu
- `lib/common.sh`: shared helpers + config
- `scripts/install_deps.sh`: install base/runtime dependencies
- `scripts/github_auth.sh`: generate/use SSH key and test GitHub auth
- `scripts/configure_project.sh`: save app/repo config and clone repo
- `scripts/install_database.sh`: install MariaDB + create DB/user + generate strong password
- `scripts/setup_update.sh`: install `/usr/local/bin/agpd-update` + cron
- `scripts/update_stack.sh`: delete app dir, clone fresh code, run `dotnet restore` + migration
- `scripts/show_config.sh`: print saved config

## Quick Start

```bash
chmod +x install.sh main.sh scripts/*.sh
./install.sh
```

Or from a fresh LXC:

Debian/Ubuntu:
```bash
apt update && apt upgrade -y && apt install -y curl
bash -c "$(curl -fsSL https://raw.githubusercontent.com/DragoQC/AutoGithubPullDeploy/main/install.sh)"
```

Alpine:
```sh
apk update && apk upgrade && apk add --no-cache curl
sh -c "$(curl -fsSL https://raw.githubusercontent.com/DragoQC/AutoGithubPullDeploy/main/install.sh)"
```

## Menu Flow

1. Install dependencies
2. GitHub SSH auth (generate key)
3. Configure project + clone repo
4. Install/configure MariaDB
5. Install update command + cron
6. Run update now

## Config + Credentials

- Main config: `~/.config/agpd/config.env`
- DB credentials (global): `/etc/agpd/db-credentials.env`
- DB credentials (app backend): `<APP_DIR>/<BACKEND_REL>/db-credentials.env`

DB name defaults from app name.
DB password is auto-generated strong and written to credentials files.

## Update Behavior

`agpd-update` (or menu option 5) does:
1. delete old app directory
2. fresh clone of configured branch/repo
3. run backend `dotnet restore`
4. run migration command (default `dotnet ef database update`)
