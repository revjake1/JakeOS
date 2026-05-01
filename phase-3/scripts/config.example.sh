#!/usr/bin/env bash
# JakeOS — UnRAID stack config
#
# Copy this file to config.sh (no .example suffix) and fill in for your
# environment.  config.sh is gitignored so local paths/hostnames stay
# local.
#
#     cp config.example.sh config.sh
#     $EDITOR config.sh

# ─── UnRAID host ────────────────────────────────────────────────────────
# Prefer the Tailscale hostname (works whether you're on the home
# network or remote).  On UnRAID, run `tailscale status` and look at
# the local node's full DNS name.
#
# Examples:
#     UNRAID_HOST="tower.tail-net.ts.net"        # tailnet hostname
#     UNRAID_HOST="100.x.y.z"                     # tailnet IP
#     UNRAID_HOST="192.168.1.10"                  # LAN IP (home only)

UNRAID_HOST=""

# SSH user.  UnRAID's default SSH user is root.
UNRAID_USER="root"

# Where the stack will live on UnRAID.  Anywhere persistent is fine;
# /mnt/user/appdata/ is the conventional place.
UNRAID_PATH="/mnt/user/appdata/jakeos-stack"

# Where the stack source lives on this Mac.
LOCAL_PATH="$HOME/Documents/jakeos/phase-3/unraid-stack"
