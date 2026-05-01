# Phase 3.2 — UnRAID stack starter

This folder is the deployable stack for `jakeos.jakehallman.com`. Drop it onto UnRAID, fill in the `.env`, deploy, verify the public URL works end-to-end. The `jakeos-web` service is currently an `nginx:alpine` stub — Phase 3.1 swaps it for the real Node.js + HTMX app.

## What's in here

```
docker-compose.yml         the four-service stack (cloudflared, caddy,
                           oauth2-proxy, jakeos-web stub)
.env.example               template for the four secrets you need to fill in
.env                       (you create this — never commit it)
Caddyfile                  forwards HTTP from cloudflared to oauth2-proxy
authenticated-emails.txt   single-allowed-account guard for oauth2-proxy
stub/                      tiny nginx stub for the web app — replaced
                           in Phase 3.1
.gitignore                 keeps .env and caddy state out of git
```

## Prerequisites (do these first, in this order)

1. **Move `jakehallman.com` to Cloudflare nameservers.** WordPress on Lithium keeps working; only DNS resolves through Cloudflare now.
2. **Create the Cloudflare Tunnel** in https://one.dash.cloudflare.com → Networks → Tunnels. Name it `jakeos`. Copy the token.
3. **Create the Public Hostname** under that tunnel: subdomain `jakeos`, domain `jakehallman.com`, type `HTTP`, URL `caddy:80`.
4. **Create the Google OAuth client** at https://console.cloud.google.com/apis/credentials. App type: web application. Authorized JS origin `https://jakeos.jakehallman.com`. Authorized redirect URI `https://jakeos.jakehallman.com/oauth2/callback`. Save the client ID + client secret.
5. **Enable the Gmail API and Calendar API** for the same GCP project (APIs & Services → Library).
6. **Confirm Tailscale on UnRAID can reach the Mac sidecar.** `tailscale status` shows the Mac. `curl http://<mac-tailscale-ip>:<sidecar-port>/health` returns OK.

## Deploy on UnRAID — Compose Manager flow

If you don't have it: install the **Compose Manager** plugin from the UnRAID Apps tab.

1. **Copy this folder onto UnRAID** somewhere persistent — e.g., `/mnt/user/appdata/jakeos-stack/`. Use `scp`, the UnRAID web UI's terminal, or any method you prefer.

2. **Create your `.env` file** alongside `docker-compose.yml`:
   ```
   cd /mnt/user/appdata/jakeos-stack/
   cp .env.example .env
   nano .env
   ```
   Fill in the four values:
   - `CLOUDFLARE_TUNNEL_TOKEN` — the long token from step 2 of prerequisites
   - `OAUTH2_PROXY_CLIENT_ID` — from your Google OAuth client
   - `OAUTH2_PROXY_CLIENT_SECRET` — from your Google OAuth client
   - `OAUTH2_PROXY_COOKIE_SECRET` — generate with: `openssl rand -hex 16` (gives 32 ASCII chars, which is what oauth2-proxy actually wants — `-base64 32` produces 44 chars and gets rejected)

3. **In Compose Manager (UnRAID UI) → Add New Stack**:
   - Name: `jakeos`
   - Compose path: `/mnt/user/appdata/jakeos-stack/docker-compose.yml`
   - Click **Compose Up**.

4. **Watch the logs** (Compose Manager has a per-service log view):
   - `cloudflared` should connect to Cloudflare and report "Registered tunnel connection"
   - `caddy` should bind to `:80` quietly
   - `oauth2-proxy` should print "OAuth2 Proxy is ready to handle requests"
   - `jakeos-web` should bind to `:3000`

5. **Visit https://jakeos.jakehallman.com in your browser:**
   - Cloudflare's edge issues TLS, your browser sees a valid cert
   - oauth2-proxy redirects you to Google's sign-in
   - Sign in with `jake.hallman@gmail.com` → see the staging stub page
   - Sign in with any other account → "Permission denied"

If all four behaviors work, **Phase 3.2 is verified.** The plumbing is good; only the upstream content (Phase 3.1's real app) is left.

## Swap-in plan when Phase 3.1 ships

In `docker-compose.yml`, replace the `jakeos-web` service stanza with one that points at the real app's image (or build context). Everything else — auth, Caddy, tunnel — stays. `oauth2-proxy`'s `OAUTH2_PROXY_UPSTREAMS=http://jakeos-web:3000` is already pointed at the right service name and port.

## Troubleshooting

**`cloudflared` keeps reconnecting:** token wrong or revoked. Re-copy from Cloudflare dashboard.

**OAuth flow loops or `oauth2-proxy` keeps restarting with `cookie_secret must be 16, 24, or 32 bytes`:** the secret must be exactly 16, 24, or 32 ASCII characters long. Use `openssl rand -hex 16` (gives 32 hex chars = 32 bytes). Do NOT use `openssl rand -base64 32` — it produces 44 chars and is rejected. Or `OAUTH2_PROXY_REDIRECT_URL` doesn't match the Authorized redirect URI you set in Google Cloud Console exactly (including `https://`, the path, no trailing slash).

**"Permission denied" with the right account:** check `authenticated-emails.txt` — exact email, lowercase, no extra whitespace, single line.

**Browser shows Cloudflare error 1033 / 1016:** the Public Hostname under your tunnel isn't pointing at `caddy:80`, or caddy isn't on `jakeos-net`. Check Compose Manager that all four containers are on the same network.

**Caddy logs say "no upstream":** oauth2-proxy hasn't started yet (first boot is slow). Wait 10s, refresh.
