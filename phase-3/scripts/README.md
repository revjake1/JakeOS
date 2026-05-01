# Phase 3 — UnRAID management scripts

One script (`unraid.sh`) drives the whole stack from your Mac terminal: rsync the config to UnRAID, bring the stack up/down over SSH, tail logs, etc.

## One-time setup

### 1. Make sure SSH key auth works to UnRAID

```bash
ssh-copy-id root@<your-unraid-host>
ssh root@<your-unraid-host> 'echo ok'
```

If that prints `ok` without prompting for a password, you're good.

If you don't have an SSH key yet:
```bash
ssh-keygen -t ed25519 -C "jake.hallman@gmail.com"
ssh-copy-id root@<your-unraid-host>
```

### 2. Create your config

```bash
cd ~/Documents/jakeos/phase-3/scripts
cp config.example.sh config.sh
$EDITOR config.sh
```

Fill in:
- `UNRAID_HOST` — Tailscale hostname is best (find with `tailscale status` on UnRAID)
- `UNRAID_USER` — usually `root`
- `UNRAID_PATH` — where the stack lives on UnRAID, default `/mnt/user/appdata/jakeos-stack`
- `LOCAL_PATH` — already correct if your repo is at `~/Documents/jakeos/`

`config.sh` is gitignored.

### 3. Make the script executable

```bash
chmod +x unraid.sh
```

## Day-one deploy

```bash
./unraid.sh sync          # rsync the stack files to UnRAID
./unraid.sh init-env      # create .env on UnRAID, open in nano to fill in secrets
./unraid.sh up            # docker compose up -d
./unraid.sh status        # confirm all four containers are healthy
./unraid.sh logs          # watch logs roll past while you visit the URL
```

Then in your browser: **https://jakeos.jakehallman.com** — Google sign-in flow → staging stub.

## Day-two updates

When you tweak the Caddyfile, the compose file, or the stub:

```bash
./unraid.sh restart       # down + sync + up
```

For just config nudges (no container changes):
```bash
./unraid.sh sync
./unraid.sh up            # docker compose up -d picks up changes idempotently
```

## Common ops

```bash
./unraid.sh logs cloudflared    # watch one service
./unraid.sh logs oauth2-proxy
./unraid.sh status              # docker compose ps
./unraid.sh ssh                 # drop into a shell at the stack dir on UnRAID
./unraid.sh down                # take it down (e.g., before a major refactor)
```

## What gets synced and what doesn't

`sync` excludes:
- `.env` — secrets, you manage these on UnRAID directly via `init-env` + nano
- `caddy-data/` and `caddy-config/` — Caddy state, regenerates on boot
- `*.log` — log files
- `.DS_Store` — macOS detritus

`sync` is `rsync --delete`, so files removed locally are removed on UnRAID. That's deliberate — it keeps the remote in sync with the source of truth (your Mac's repo). The exclude list above is what protects state and secrets.
