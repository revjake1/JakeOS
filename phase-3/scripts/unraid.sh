#!/usr/bin/env bash
# JakeOS — UnRAID stack management
#
# Drives the docker-compose stack at phase-3/unraid-stack/ from your Mac.
# rsyncs config to UnRAID, brings the stack up/down over SSH, tails logs.
#
# Setup (one time):
#   1.  cp config.example.sh config.sh
#   2.  Edit config.sh with your UnRAID host (Tailscale name preferred),
#       SSH user, remote path, and local path.
#   3.  Make sure SSH key auth works:  ssh root@<unraid> 'echo ok'
#       (set up keys via:  ssh-copy-id root@<unraid>)
#
# Usage:
#   ./unraid.sh sync              push files to UnRAID (excludes .env, state)
#   ./unraid.sh up                bring stack up
#   ./unraid.sh down              bring stack down
#   ./unraid.sh restart           down → sync → up
#   ./unraid.sh logs              tail logs from all services
#   ./unraid.sh logs cloudflared  tail one service's logs
#   ./unraid.sh status            docker compose ps
#   ./unraid.sh ssh               drop into a shell at the stack dir
#   ./unraid.sh init-env          create .env on UnRAID from .env.example,
#                                 open it in nano for editing
#   ./unraid.sh help              this message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [[ ! -f "$CONFIG_FILE" ]]; then
    cat <<EOF >&2
error: config.sh not found in $SCRIPT_DIR

Run:
    cd "$SCRIPT_DIR"
    cp config.example.sh config.sh

Then edit config.sh with your UnRAID details.
EOF
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Verify required vars
for var in UNRAID_HOST UNRAID_USER UNRAID_PATH LOCAL_PATH; do
    if [[ -z "${!var:-}" ]]; then
        echo "error: $var is not set in config.sh" >&2
        exit 1
    fi
done

REMOTE="$UNRAID_USER@$UNRAID_HOST"

# ─── commands ──────────────────────────────────────────────────────────────

cmd_sync() {
    if [[ ! -d "$LOCAL_PATH" ]]; then
        echo "error: LOCAL_PATH does not exist: $LOCAL_PATH" >&2
        exit 1
    fi

    echo "==> Syncing $LOCAL_PATH/  →  $REMOTE:$UNRAID_PATH/"
    # Ensure remote path exists
    ssh "$REMOTE" "mkdir -p '$UNRAID_PATH'"

    rsync -avz --delete \
        --exclude='.env' \
        --exclude='caddy-data/' \
        --exclude='caddy-config/' \
        --exclude='*.log' \
        --exclude='.DS_Store' \
        "$LOCAL_PATH/" \
        "$REMOTE:$UNRAID_PATH/"

    echo "==> Sync complete."
    echo
    if ! ssh "$REMOTE" "test -f '$UNRAID_PATH/.env'" 2>/dev/null; then
        echo "Note: .env does not exist yet on UnRAID."
        echo "Run:  ./unraid.sh init-env"
    fi
}

cmd_up() {
    echo "==> Bringing stack up on $REMOTE"
    ssh "$REMOTE" "cd '$UNRAID_PATH' && docker compose up -d"
    echo "==> Stack up.  Run:  ./unraid.sh status"
}

cmd_down() {
    echo "==> Bringing stack down on $REMOTE"
    ssh "$REMOTE" "cd '$UNRAID_PATH' && docker compose down"
}

cmd_restart() {
    cmd_down
    cmd_sync
    cmd_up
}

cmd_logs() {
    local svc="${1:-}"
    if [[ -n "$svc" ]]; then
        ssh -t "$REMOTE" "cd '$UNRAID_PATH' && docker compose logs -f --tail=200 $svc"
    else
        ssh -t "$REMOTE" "cd '$UNRAID_PATH' && docker compose logs -f --tail=200"
    fi
}

cmd_status() {
    ssh "$REMOTE" "cd '$UNRAID_PATH' && docker compose ps"
}

cmd_ssh() {
    ssh -t "$REMOTE" "cd '$UNRAID_PATH' && exec \$SHELL -l"
}

cmd_init_env() {
    if ssh "$REMOTE" "test -f '$UNRAID_PATH/.env'" 2>/dev/null; then
        echo "==> .env already exists on UnRAID."
        read -r -p "    Open it for editing? [y/N] " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            ssh -t "$REMOTE" "cd '$UNRAID_PATH' && nano .env"
        fi
        return
    fi

    if ! ssh "$REMOTE" "test -f '$UNRAID_PATH/.env.example'" 2>/dev/null; then
        echo "error: $UNRAID_PATH/.env.example missing on UnRAID — run './unraid.sh sync' first" >&2
        exit 1
    fi

    echo "==> Creating .env on UnRAID from .env.example"
    ssh "$REMOTE" "cd '$UNRAID_PATH' && cp .env.example .env && chmod 600 .env"
    echo "==> Opening it in nano (over SSH).  Fill in the four secrets, Ctrl-O to save, Ctrl-X to exit."
    ssh -t "$REMOTE" "cd '$UNRAID_PATH' && nano .env"
}

cmd_help() {
    sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ─── dispatch ──────────────────────────────────────────────────────────────

case "${1:-help}" in
    sync)        cmd_sync ;;
    up)          cmd_up ;;
    down)        cmd_down ;;
    restart)     cmd_restart ;;
    logs)        shift; cmd_logs "${1:-}" ;;
    status)      cmd_status ;;
    ssh)         cmd_ssh ;;
    init-env)    cmd_init_env ;;
    help|-h|--help) cmd_help ;;
    *)
        echo "unknown command: $1" >&2
        echo
        cmd_help
        exit 1
        ;;
esac
