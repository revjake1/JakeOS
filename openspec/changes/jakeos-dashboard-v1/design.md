# jakeos-dashboard-v1 — Design

> Five open questions from `proposal.md`. For each, options are laid out side-by-side with tradeoffs. **No recommendation.** Jake picks before `/opsx:apply` runs and the chosen option is recorded inline.

Format per question: brief problem statement → 2–3 named options → matrix of tradeoffs → "Decision: ___" line for Jake to fill in.

---

## Q1. Surface architecture

**Problem.** Where does the dashboard UI actually live? Bullet 20 of the source notes asks: "Is all this feasible as a URL? Should it be a standalone app?" The answer ripples into deploy, auth, data, and how much WordPress matters.

### Option A — WordPress page at `/jakeos`

A custom page template inside the existing `jakehallman` child theme renders the dashboard. Data fetched via WordPress REST endpoints (custom or plugins). Authenticated as a WordPress user. Updates via WP-cron + websocket fallback or polling.

- **Pros:** zero new infra; deploys with the rest of the site; reuses Caddy + Docker setup; auth piggybacks on `wp-login`.
- **Cons:** WordPress is a poor fit for a reactive single-page dashboard; PHP/JS ergonomics are 2015-era; the page becomes a second product crammed inside a CMS; performance ceiling is real once email + calendar streams are live; "context efficiency" goal harder to hit because the round-trip to WP-cron is expensive.
- **Touch surfaces:** `wp-content/themes/jakehallman/`, custom plugin in `wp-content/plugins/jakeos/` (new), custom REST routes.

### Option B — Standalone web app reverse-proxied behind `/jakeos`

A separate web app runs as its own service. Caddy reverse-proxies a subdomain (or `/jakeos` path) to the app. Auth handled by the app (not WordPress). *(Subdomain choice locked during Phase 3 architecture exploration — see "Phase 3 deployment topology" below.)*

- **Pros:** modern reactive UI; clean separation; can stream updates over WebSocket / SSE; easy to put behind its own auth; one deploy unit; "no monolith" maps cleanly to one route per capability.
- **Cons:** new service to operate; Caddy routing must be tightened (auth on `/jakeos` AND any sub-paths); SEO/cookie/CORS edge cases at the WP boundary; you now have two web apps to maintain.
- **Touch surfaces:** new `~/Documents/New_Jakehallman_site/jakeos-app/` directory (Docker service); `Caddyfile` route block; small WP-side stub (just a redirect or meta tag if needed).

### Option C — Native macOS dashboard inside Second Brain Helper

The dashboard is a window/scene inside the existing `SecondBrainHelper.app`. No web UI. The Helper app is already at deployment target macOS 26 with a Rust sidecar — it has the privilege model and local-data access the dashboard needs anyway. Web URL `/jakeos` either doesn't exist or is a thin "open the Mac app" landing page.

- **Pros:** fastest, no auth (it's local + macOS account), no servers, native widgets, OS-level keychain, AppleScript/automation hooks; "context-efficient" is trivial because data is local; matches bullet 22 ("work hand in hand with the second brain helper app on my macbook").
- **Cons:** dashboard is unreachable when away from the Mac; password-protected web UI requirement (bullet 14) goes unmet unless a shadow web view is also built; harder to share with anyone (probably fine, since v1 is single-user); ties update cadence to App Store / notarized rebuilds.
- **Touch surfaces:** `Second-brain-helper-app/SecondBrainHelper/` (new SwiftUI scene/window); existing Rust sidecar gets new endpoints.

### Tradeoff matrix

| Dimension | A. WP page | B. Standalone web | C. Native macOS |
|---|---|---|---|
| Time to v1 | Medium (WP friction) | Medium-High (new service) | Low (you already have the app) |
| Reactivity | Poor | Excellent | Excellent |
| "Off-Mac" availability | Yes | Yes | No |
| Auth complexity | Low (WP login) | Medium (own auth) | None (OS account) |
| Token / context efficiency | Hardest | Medium | Easiest |
| Plays with the macOS Helper | Loosely | Loosely | Native |
| Public-facing at `/jakeos` | Yes | Yes | Only as a redirect/landing |

**Decision: B — Standalone web app at `https://jakeos.jakehallman.com`.**

Locked 2026-05-01 after exploring with Jake. Reasoning recorded for traceability:

- "Tab I keep open" is the daily mental model. A reactive web surface fits that natively; a WordPress page (A) doesn't, and a native macOS dashboard (C) is unreachable from phone-in-bed and school-computer contexts that Jake explicitly named as use cases.
- The web tab is the *consume* surface. The macOS Helper is repurposed as a *capture* surface (drag-and-drop, file→md conversion); see Q2's decision and the new `capture` capability spec.
- Aligns with the orchestration/no-monolith requirement: routes-per-capability map cleanly to a standalone web app.
- **Subdomain instead of path** — refined during Phase 3 architecture discussion: `jakehallman.com` is hosted at Lithium Hosting (managed shared hosting), making path-based routing across hosts impractical. Subdomain `jakeos.jakehallman.com` lives entirely on Jake's UnRAID server, leaving the WordPress site untouched at Lithium. See the Phase 3 deployment topology section below for the full topology.

---

## Q2. Shared backend

**Problem.** If both surfaces exist (e.g., A or B *and* C), or if any of them needs server-side state (calendar correlation, email triage history, self-improvement-loop ledger), where does the canonical data live?

### Option α — Helper-app-as-server

The macOS Helper exposes a localhost-and-bonjour service (the Rust sidecar already exists; extend it). When Jake's Mac is online, the web dashboard talks to it (via tunnel, e.g., Cloudflare Tunnel or Tailscale Funnel). Single source of truth on the Mac.

- **Pros:** one place for data; macOS owns identity; no third service.
- **Cons:** Mac asleep = dashboard offline; tunnel dependency; sync semantics get hairy if any write happens server-side while Mac is offline.

### Option β — WordPress / MySQL as the backend

State stored in WP custom tables or post types; WP REST as the API; both surfaces read/write through it.

- **Pros:** already deployed; durable; backed up by existing site infra.
- **Cons:** schema-heavy in a CMS; rate-limited by WP; PHP layer in front of high-frequency reads; not designed for streams/queues.

### Option γ — Dedicated small service (SQLite / Postgres + thin API)

A small backend service (e.g., a single-binary Go/Rust API + SQLite, or a Supabase/Pocketbase, deployed alongside Caddy) owns data; both surfaces are clients.

- **Pros:** right-shaped tool; reactive-friendly (websockets, change feeds); migration / schema control; easy to back up; zero coupling to WordPress.
- **Cons:** another service to run and secure; more moving parts than δ.

### Option δ — No shared backend (per-surface local storage)

The macOS Helper owns its data locally (already does). The web dashboard is read-only against a periodic export, or read-only against a tunnel into Helper, or has its own independent state. No "single source of truth."

- **Pros:** simplest possible v1; no new infra.
- **Cons:** fights the proposal's "two surfaces stay in sync" requirement; punts the problem instead of solving it.

| Dimension | α. Helper-as-server | β. WordPress | γ. Dedicated service | δ. No shared backend |
|---|---|---|---|---|
| Operational cost | Low if Mac always on | Already paid | Low (one extra container) | Lowest |
| Always-on availability | No | Yes | Yes | Per-surface |
| Schema control | Sidecar's call | WP-shaped | Yours | Each surface picks |
| Streams / change feeds | Possible | Hard | Easy | N/A |
| Plays with Q1 = A | Awkward | Native | Fine | Awkward |
| Plays with Q1 = B | Fine | Fine | Native | Awkward |
| Plays with Q1 = C alone | Native | Overkill | Overkill | Fine |

**Decision: α — Helper-as-server, with the Rust sidecar carrying the API.**

Locked 2026-05-01. Specifics:

- The existing **Rust sidecar** in `~/Documents/Second-brain-helper-app/sidecar/` becomes the canonical backend. It exposes an HTTP API over Tailscale that the web tab (Q1 = B) consumes. The sidecar owns the data store (SQLite or filesystem-backed, decided in Phase 1.2 / `data-contract/spec.md`).
- The **Swift UI** of Helper.app is *not* extended. It is repurposed as a native **drag-and-drop capture surface** (see new `capture` capability) — a tiny menubar/dock presence whose only job is accepting dropped items and routing them through the sidecar's conversion pipeline into the wiki's RAW folder. No browsing, no list views, no dashboard chrome.
- The "Mac in bag during commute" window (~30–60 min/day) is handled by **graceful degradation**: the web tab shows last-sync state with a banner, read-only, until the Mac is reachable again. Per Jake's answer, this is acceptable.
- Tailscale is already installed on the Mac — the tunnel is built. No new infra.

This means: **Helper.app = capture. Sidecar = backend. Web tab = consume.**

---

## Q3. Auth model

**Problem.** Bullet 14 mandates "password-protected" for the web UI. The macOS surface has Keychain available natively. What's the actual auth?

### Option i — WordPress login (`/wp-admin` cookie)

The dashboard at `/jakeos` checks for a logged-in WP user with role `administrator` (or a custom role).

- **Pros:** one place to manage; WP already does this.
- **Cons:** WP session cookies are clunky; logging out of `/jakeos` means logging out of WP entirely or not at all.

### Option ii — Standalone password (basic auth at Caddy or app-level)

Caddy enforces basic auth or a forward-auth provider on `/jakeos*`. Independent of WordPress.

- **Pros:** simple; no coupling to WP; easy to bootstrap.
- **Cons:** password rotation manual; no MFA without more work; only useful if Q1 ≠ C.

### Option iii — OAuth-to-self (Google / Apple via small auth service)

Use Sign in with Google or Apple as the front door (since Jake's identity is `jake.hallman@gmail.com`). Single allowed account. JWT cookie / session in front of the dashboard.

- **Pros:** real MFA via Google/Apple; revocable; modern; unifies with Gmail / Calendar OAuth scopes already needed for the email + calendar features.
- **Cons:** more infra; OAuth callback to set up; only useful if Q1 ≠ C.

### Option iv — OS-only on macOS surface

The macOS Helper relies on the user being logged into the Mac (with Touch ID / Keychain for any secrets). No web auth because there's no web surface (Q1 = C).

- **Pros:** simplest, strongest, free.
- **Cons:** doesn't satisfy "password-protected web UI" if any web surface exists.

| Dimension | i. WP login | ii. Caddy basic auth | iii. OAuth-to-self | iv. OS-only |
|---|---|---|---|---|
| Effort | Low | Lowest | Medium | None |
| MFA possible | Plugins | No | Yes | OS-level |
| Plays with Gmail/Calendar OAuth | Separate | Separate | Reuses scopes | N/A |
| Single-user simplicity | OK | OK | OK | Native |

**Decision: iii — OAuth-to-self via Google.**

Locked 2026-05-01. Reasoning:

- The dashboard needs Gmail and Calendar OAuth scopes anyway for capabilities #4 (important emails) and #6 (calendar). Folding sign-in into the same OAuth flow means **one grant, one consent screen, one token store** instead of two parallel auth systems.
- Identity is `jake.hallman@gmail.com`. Google's MFA already protects that account; JakeOS inherits it for free.
- A small auth proxy (e.g., `oauth2-proxy` behind Caddy, or an equivalent in the standalone web app) handles the OAuth dance. Caddy enforces the auth requirement on `/jakeos*` before any request reaches the app.
- **Single-allowed-account guard** is mandatory: any successful Google OAuth that resolves to an email other than `jake.hallman@gmail.com` MUST be denied. Codified in `auth/spec.md`.
- Borrowed-device case: the OAuth flow is slightly slower than basic auth, but acceptable. Trade-off accepted.

---

## Q4. Self-improvement-loop safety boundary

**Problem.** Bullet 10: "Second brain should iterate itself automatically once a day, evolving over lessons learned, reinstalling and overwriting itself with the newer, better version." This is a self-modifying-system bullet. It needs a safety boundary or it'll silently brick itself.

### Option Ⅰ — Diff-and-approve

Once daily, the loop produces a diff of proposed changes (skill edits, prompt tweaks, config) and asks Jake to approve before any write. No auto-merge.

- **Pros:** safest; reviewable history; matches existing skill-editing patterns.
- **Cons:** slowest; depends on Jake actually reviewing.

### Option Ⅱ — Sandbox + smoke test, then promote

Loop applies changes to a shadow copy; runs a smoke-test eval (e.g., does `/opsx:propose` still scaffold? does the briefing skill still answer a known query?); if green, promotes; if red, files a diff for Jake to review.

- **Pros:** automated for clear wins; falls back to review for ambiguous cases.
- **Cons:** requires building / maintaining the eval suite; sandbox infra.

### Option Ⅲ — Auto-apply with rollback

Loop writes immediately, keeps a daily snapshot, surfaces a "rollback" button if Jake notices anything off.

- **Pros:** fastest; matches the bullet's literal wording.
- **Cons:** trust on rails; bad-day-failure mode is a borked system Jake has to repair manually.

### Option Ⅳ — Explicitly defer

Self-loop is descoped from v1. Manual changes only. Loop becomes its own follow-up change once the rest of JakeOS is stable.

- **Pros:** removes the highest-risk, hardest-to-validate piece from v1.
- **Cons:** punts on a bullet Jake actually wants.

| Dimension | Ⅰ. Diff-and-approve | Ⅱ. Sandbox + smoke | Ⅲ. Auto + rollback | Ⅳ. Defer |
|---|---|---|---|---|
| Risk of self-bricking | Lowest | Low | Medium-High | None |
| Speed of improvement | Slow | Fast | Fastest | None (in v1) |
| Build cost | Low | High (eval suite) | Medium | None |
| Matches bullet 10 wording | Partly | Yes | Most literally | No |

**Decision: Ⅰ — Diff-and-approve. Jake is the human in the loop.**

Locked 2026-05-01. Reasoning + new constraint:

- Jake committed to reviewing the queue. The orchestration spec already prevents the loop from modifying the orchestrator or the safety policy, so the worst-case is bounded.
- Loop generates a diff once per day; nothing applies until Jake approves.
- **New requirement Jake added**: "If I miss a day, it should handle it gracefully." This means the loop CANNOT just keep piling up identical proposals into an unread queue. Codified in `self-loop/spec.md` as graceful-skip behavior:
  - Queue depth surfaces visibly on the dashboard, with age of oldest pending item
  - Duplicate / overlapping proposals coalesce automatically before review
  - Stale proposals (older than 7 days) re-evaluate against current state before being re-presented (so Jake doesn't approve a fix for a problem that no longer exists)
  - After 14 days with zero review activity, generation pauses entirely until Jake clears the queue (no infinite-growth queue)
- Cost: low. No eval suite required (that was Ⅱ's burden). Snapshots + audit log already required by the existing self-loop spec.
- Speed: slow but acceptable. Improvement happens at Jake's review cadence, not at the loop's generation rate.

---

## Q5. Ingest-cycle trigger

**Problem.** Bullet 12 wants regular checks of the second-brain wiki RAW folder (`~/Documents/Obsidian Vault/Second brain/RAW/` — verify path against `AGENTS.md`) to know when to run an ingest cycle. Where does the watcher live?

### Option ①  — macOS Helper watcher (FSEvents)

Helper app watches the RAW folder via macOS FSEvents and triggers ingest when files appear.

- **Pros:** instant; native; cheapest in compute; aligns with Q1 = C.
- **Cons:** Mac asleep = no trigger until wake.

### Option ② — Server-side cron (Caddy host)

A periodic job on the Caddy host pulls a manifest from the Mac (via tunnel) or from a synced location (iCloud/Dropbox/git-backed wiki) and decides whether ingest is needed.

- **Pros:** runs even with Mac off; centralizes scheduling.
- **Cons:** requires the wiki to be reachable server-side; sync dependency.

### Option ③ — Cowork scheduled task

A Cowork scheduled task (the user already has the `schedule` skill installed) runs every N minutes / hours, hits the wiki, decides whether ingest is needed.

- **Pros:** uses existing infra; already token-budgeted; runs from Cowork wherever Jake is.
- **Cons:** Cowork-bound; subject to Cowork session lifecycle.

| Dimension | ①. FSEvents | ②. Server cron | ③. Cowork schedule |
|---|---|---|---|
| Latency to detect new RAW | Seconds | Minutes-hours | Per schedule |
| Works when Mac off | No | Yes (if synced) | Yes |
| Setup effort | Medium (Helper code) | Medium (sync infra) | Lowest (existing skill) |
| Token efficiency | Best | Medium | Per Cowork run |

**Decision: ① — FSEvents on Mac, hosted in the Rust sidecar.**

Locked 2026-05-01. Reasoning:

- Q2 = α put the sidecar on the Mac, sitting next to `~/Documents/Obsidian Vault/Second brain/raw/`. macOS hands FSEvents for free; the sidecar is exactly where it needs to live.
- Latency: ingest fires within seconds of a new file appearing in `raw/`.
- "Mac in bag during commute" doesn't matter — capture surface is on the same Mac, so nothing's being added during that window. FSEvents has resume-from-checkpoint semantics; on wake, the sidecar catches up on missed events.
- **Implementation note added during exploration**: a manual "rescan now" button MUST exist on the dashboard for ad-hoc re-scans (covers the rare case where the watcher misses an event or where a sync-from-elsewhere drops files into `raw/` outside the watcher's view). Codified in `ingest/spec.md`.
- Token-efficient by construction (no polling).

---

## Cross-question dependencies

Once Q1 is decided, several others narrow:

- **Q1 = A (WordPress page).** Q2 likely β. Q3 likely i. Q5 needs ② or ③ (no native macOS watcher in scope).
- **Q1 = B (standalone web).** Q2 likely γ. Q3 likely iii (or ii). Q5 could be any.
- **Q1 = C (native macOS only).** Q2 likely α or δ. Q3 likely iv. Q5 likely ①.
- **Q1 = mixed (e.g., B + C).** Q2 likely α or γ. Q3 likely iii on web side, iv on Mac side. Q5 likely ①.

---

## Phase 3 deployment topology — locked 2026-05-01

After Phase 2 (sidecar) shipped, a follow-on architecture exploration locked the deployment topology for Phase 3 (the standalone web app). All decisions below are downstream of Q1 = B and Q2 = α and are recorded here so Phase 3 implementation has a clean target.

### Web app host

**UnRAID home server.** The other candidates were Jake's home PC (24/7 but a daily driver, susceptible to reboots) and the MacBook itself (already runs the sidecar; goes offline during commute, which would defeat the dashboard's offline-banner contract). UnRAID is purpose-built for Docker, runs unattended, and has Tailscale already installed so it can reach the Mac sidecar privately.

### Public reachability

**Cloudflare Tunnel** (`cloudflared` running on UnRAID). The other candidates were home-router port forwarding (some ISPs block 80/443; static-IP or DDNS dependency) and Tailscale Funnel (does not support custom domains with proper TLS — its Funnel hostnames are `*.ts.net`-locked). Cloudflare Tunnel exposes UnRAID publicly without port forwarding, terminates TLS at the Cloudflare edge for free, and costs nothing.

**DNS strategy:** option A — only the subdomain moves to Cloudflare. Jake adds a `CNAME jakeos.jakehallman.com → <tunnel-uuid>.cfargotunnel.com` in his current DNS panel (Lithium-managed). The apex `jakehallman.com` and its existing records stay untouched. No nameserver migration required.

### Web framework

**Node.js + HTMX.** The web app server-renders HTML. The browser uses HTMX to swap fragments on demand. Specifically:

- Tiny client payload — no SPA bundle.
- `hx-trigger="every 10s"` polling for live updates in v1. The sidecar's HTTP API + SQLite reads are sub-millisecond, so polling is cheap.
- Upgrade path: when polling becomes insufficient, add SSE to the sidecar and proxy through the web app to the browser via HTMX's SSE extension. Not required for v1.
- Alignment with the "EXTREMELY context-efficient" goal — fewer bytes shipped to the browser than any framework alternative would produce.

The other candidates considered: SvelteKit / Astro (heavier, reactive-SPA shape), Rust + axum (would share types with the sidecar, but slows velocity if Jake isn't actively writing Rust web code), plain HTML + minimal JS (similar to HTMX but more boilerplate). HTMX + Node.js wins on token-efficiency and pace-of-build for a single-user dashboard.

### OAuth integration

**`oauth2-proxy` in front of the web app, configured for Google.** The proxy enforces:

- `provider = google`
- `email_addresses = jake.hallman@gmail.com` (single-allowed-account guard at the proxy layer)
- Required scopes: `openid email profile https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.readonly` (one consent flow, all scopes per the auth spec)
- Forwards authenticated requests to the web app with `X-Forwarded-User`, `X-Forwarded-Email`, `X-Auth-Request-Access-Token` headers.

The web app trusts those headers and passes Gmail/Calendar tokens through to the sidecar via Tailscale when needed. Web-app code stays simple; OAuth complexity stays in the proxy.

### Container layout (UnRAID `docker-compose.yml`)

Five containers:

```
cloudflared       — tunnel client; exposes the stack publicly
caddy             — reverse proxy; terminates HTTP behind cloudflared,
                    routes to oauth2-proxy
oauth2-proxy      — Google OAuth gate; forwards authenticated requests
jakeos-web        — Node.js + HTMX server (the dashboard itself)
tailscale         — sidecar tailnet membership (or use UnRAID's
                    host-level Tailscale daemon — both work)
```

### TLS

**Terminated at Cloudflare's edge.** No ACME setup needed on UnRAID. The internal traffic between Cloudflare and `cloudflared` is encrypted by the tunnel itself; everything inside the docker network is HTTP-over-the-bridge.

### Live updates

**HTMX polling at `every 10s` for v1.** Cheap because the sidecar's reads are SQLite-backed. Per-section `hx-trigger` so each section refreshes independently. SSE is an explicit follow-up if the polling cadence proves limiting.

---

## What lands in the long-lived spec

After decisions are filled in above, an `apply` will produce or update specs in `openspec/specs/`:

- `openspec/specs/dashboard/spec.md` — surface architecture, layout contract, update mechanism.
- `openspec/specs/data-contract/spec.md` — what data flows between Helper and dashboard, in which direction, with what guarantees.
- `openspec/specs/auth/spec.md` — the chosen auth model.
- `openspec/specs/self-loop/spec.md` — the safety boundary for the daily self-improvement pass.
- `openspec/specs/ingest/spec.md` — the RAW-folder trigger contract.
- `openspec/specs/orchestration/spec.md` — the no-monolith contract (orchestrator + bounded subskills, with audit).
- `openspec/specs/capture/spec.md` — file-to-markdown drag-and-drop into the wiki's `raw/` folder.

Module-level specs (todos, email, calendar, employment, briefings) come in follow-up changes that cite this one.

## What does *not* land in spec from this change

- UI styling, component library, color palette — explicitly a follow-up "jakeos-visual-system" change.
- Email-classifier learning loop ("learn what's important over time") — its own change once the dashboard frame exists.
- Mobile / iOS — still out of scope.
