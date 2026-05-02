# jakeos-dashboard-v1 — Tasks

> Implementation order. Tasks are gated on the design-question decisions in `design.md`. Nothing under "Phase 2" or later starts until **all five Decision lines** in design.md are filled in.

Repo legend:
- 🅙 = `~/Documents/jakeos` (this repo — specs only)
- 🅜 = `~/Documents/Second-brain-helper-app` (macOS app)
- 🅦 = `~/Documents/New_Jakehallman_site` (WordPress / Caddy host)

Commits in 🅜 and 🅦 must reference `jakeos-dashboard-v1` per the convention in `openspec/project.md`.

---

## Phase 0 — Decisions (gate)

These tasks happen in this repo (🅙). No code yet.

- [x] 0.1  **Q1. Surface architecture = B** (standalone web app at `https://jakeos.jakehallman.com`, hosted on UnRAID, exposed via Cloudflare Tunnel — refined during Phase 3 architecture exploration). Locked 2026-05-01.
- [x] 0.2  **Q2. Shared backend = α** (Rust sidecar as backend; Swift UI repurposed as drag-and-drop capture surface). Locked 2026-05-01.
- [x] 0.3  **Q3. Auth model = iii** (Google OAuth-to-self; reuses Gmail/Calendar scopes; single-allowed-account guard for `jake.hallman@gmail.com`). Locked 2026-05-01.
- [x] 0.4  **Q4. Self-loop safety = Ⅰ** (diff-and-approve, Jake as human in the loop, with graceful-skip behavior: queue coalescing, stale re-evaluation, generation pause after 14 days inactivity). Locked 2026-05-01.
- [x] 0.5  **Q5. Ingest trigger = ①** (FSEvents on Mac, hosted in the Rust sidecar, with manual rescan endpoint). Locked 2026-05-01.
- [x] 0.6  Cross-question consistency check: B + α + iii + Ⅰ + ① is internally consistent. (B and α both expect a web tab + Mac-resident sidecar; iii's OAuth grant carries the Gmail/Calendar scopes the web tab needs; ① runs in the same sidecar as α; Ⅰ's queue surfaces on the same web tab.)
- [x] 0.7  Helper-app correction confirmed: `openspec/project.md` and `README.md` describe Second Brain Helper as macOS, not iOS. Verified 2026-05-01 against `SecondBrainHelper.xcodeproj` (`SDKROOT = macosx`, `MACOSX_DEPLOYMENT_TARGET = 26.0`).

---

## Phase 1 — Long-lived specs

Spec files written in this repo (🅙) under `openspec/specs/`. Each cites the chosen options from `design.md`.

- [x] 1.1  `openspec/specs/dashboard/spec.md` — promoted from delta 2026-05-01.
- [x] 1.2  `openspec/specs/data-contract/spec.md` — promoted from delta 2026-05-01.
- [x] 1.3  `openspec/specs/auth/spec.md` — promoted from delta 2026-05-01.
- [x] 1.4  `openspec/specs/self-loop/spec.md` — promoted from delta 2026-05-01.
- [x] 1.5  `openspec/specs/ingest/spec.md` — promoted from delta 2026-05-01.
- [x] 1.6  `openspec/specs/orchestration/spec.md` — promoted from delta 2026-05-01.
- [x] 1.7  `openspec/specs/capture/spec.md` — promoted from delta 2026-05-01.

---

## Phase 2 — Backend / data plane

Only relevant tasks run, depending on Q2.

If **Q2 = α (Helper-as-server)**: tasks are 🅜.
If **Q2 = β (WordPress)**: tasks are 🅦.
If **Q2 = γ (dedicated service)**: tasks are 🅦 (deployed alongside Caddy).
If **Q2 = δ (no shared backend)**: skip Phase 2 entirely; replace with per-surface storage tasks in Phase 3.

- [ ] 2.1  Stand up the chosen backend (service, schema, API surface) per `data-contract/spec.md`.
- [ ] 2.2  Implement read endpoints for: todos, ideas, ingest-state, recent-important-emails, upcoming-calendar, employment-tracker.
- [ ] 2.3  Implement write endpoints for: todo create / complete, idea capture, calendar-add-from-email, email-mark-important / mark-not-important.
- [ ] 2.4  Add an audit log table/file used by Phase 5's self-loop for write traceability.
- [ ] 2.5  Health check + liveness endpoint exposed to the chosen surface(s).

---

## Phase 3 — Surface implementation

Q1 = B locked. Subdomain locked at `jakeos.jakehallman.com`. Stack locked per design.md "Phase 3 deployment topology" section: UnRAID host, Cloudflare Tunnel for public reachability, Node.js + HTMX web app, oauth2-proxy in front, Tailscale to the Mac sidecar.

The web app lives in a **new repo** (TBD), not in `New_Jakehallman_site`. WordPress at Lithium is untouched.

### Phase 3.0 — Pre-implementation setup (manual, by Jake)

These can't be done by Claude Code. Do them first.

- [x] 3.0.1  Google OAuth client created (web app, origin `https://jakeos.jakehallman.com`, redirect `/oauth2/callback`). Client ID + secret stored.
- [x] 3.0.2  Gmail API + Calendar API enabled in GCP.
- [x] 3.0.3  Cloudflare Tunnel `jakeos` created.
- [x] 3.0.4  Domain moved to Cloudflare nameservers; public hostname `jakeos.jakehallman.com → http://caddy:80` wired in tunnel config.
- [x] 3.0.5  Tailscale verified on UnRAID; UnRAID Tailscale IP: `100.117.1.101`. (Sidecar reachability from UnRAID containers will be verified for real during Phase 3.1 wiring.)

### Phase 3.1 — Scaffold the web app

- [x] 3.1.1  Repo `revjake1/jakeos-web` created on GitHub; initial commit pushed 2026-05-01 (branch `phase-3.1-scaffold`). Working copy at `~/Documents/jakeos-web`.
- [x] 3.1.2  Node.js project scaffolded 2026-05-01: **Hono** (small/fast/typed) + plain template literals (no extra runtime deps) + HTMX 1.9.x via CDN. Source under `src/`: `server.js`, `layout.js`, `sections.js`, `sidecar.js`, `auth.js`, `html.js`.
- [x] 3.1.3  Dashboard layout implemented: seven cards (todos, important emails, calendar, employment, briefings, recent captures, self-loop queue) + Cowork input anchored at bottom. Each card polls its own fragment endpoint at `/sections/<id>`.
- [x] 3.1.4  Per-section HTMX polling cadence chosen per data volatility: todos 10s, captures 15s, emails 30s, self-loop 30s, calendar 60s, briefings 60s, employment 5m. Offline banner re-checks every 15s.
- [x] 3.1.5  Sidecar HTTP client (`src/sidecar.js`) with `SIDECAR_BASE_URL` env var (default `http://100.122.117.106:7843`, the Mac's tailnet IP). Forwards the user's Google access token from `X-Forwarded-Access-Token` (oauth2-proxy) to the sidecar as `X-Google-Access-Token` for endpoints needing Gmail/Calendar scope.
- [x] 3.1.6  Offline behavior: in-memory cache of every successful GET; on failure each section renders the last cached value with a "stale" tag; the shell renders an offline banner reporting `last sync at <ts>` and write controls disable. Per `dashboard/spec.md` "Graceful degradation".

### Phase 3.2 — Compose the UnRAID stack

- [x] 3.2.1  `docker-compose.yml` with four services (cloudflared, caddy, oauth2-proxy, jakeos-web stub via nginx:alpine; UnRAID host-level Tailscale used). Stack source at `phase-3/unraid-stack/` in this repo. Deploy/management scripts at `phase-3/scripts/`.
- [x] 3.2.2  `Caddyfile`: HTTP-only on `:80`, reverse-proxies to `oauth2-proxy:4180`. TLS terminated at Cloudflare's edge.
- [x] 3.2.3  `oauth2-proxy` config: provider Google, single-allowed-account guard via `authenticated-emails.txt`, full scope list (openid + email + profile + Gmail readonly + Calendar readonly), upstream `http://jakeos-web:3000`, cookie secret 32 bytes ASCII (`openssl rand -hex 16`).
- [x] 3.2.4  `cloudflared` runs in compose using `TUNNEL_TOKEN`; standalone Community Apps cloudflared removed; tunnel hostname `jakeos.jakehallman.com → caddy:80`.
- [x] 3.2.5  Stack deployed; all four containers `Up`.
- [x] 3.2.6  `https://jakeos.jakehallman.com` reachable publicly. Google sign-in flow works. Single-account guard rejects non-Jake accounts. Staging stub renders for Jake. Phase 3.2 verified 2026-05-01.

---

## Phase 4 — Modules (the 13 capability bullets)

These run in parallel where possible. Each one will be split off into its own follow-up change citing `jakeos-dashboard-v1` once the frame is up.

For v1 of *this* change, only these tasks are required:

- [x] 4.1  **Todos** — add/check/uncheck round-trip via `data-contract/spec.md`; verified end-to-end. Implemented in change `jakeos-todos-module` (2026-05-01).
- [ ] 4.2  **Important email surface** — Gmail OAuth scope wired (uses the same OAuth from Q3 if applicable); show top-N most-recent likely-important; "mark important / not" writes back.
- [x] 4.3  **Calendar surface** — Google Calendar OAuth scope wired; show today + condensed upcoming; "add this email as event" prompt path stubbed. Implemented in change `jakeos-calendar-module` (2026-05-01). End-to-end verified: real events from Jake's primary Google Calendar render on https://jakeos.jakehallman.com.
- [ ] 4.4  **Employment section** — read from `~/.claude/skills/job-applier/state/APPLICATION_TRACKER.md`; cross-reference Gmail labels for `Job Apps/*`; render outstanding / needs-followup / rejected (rejected hidden).
- [ ] 4.5  **Cowork input** — bottom input field that posts to a Cowork session (or queues for one) for new todos / ideas / questions.
- [ ] 4.6  **Daily staleness sweep** — scheduled task (per Q5 trigger) flags stale facts; ambiguous ones surface to Jake on the dashboard.
- [ ] 4.7  **Contextual briefings** — when an email or event references a topic in the second-brain wiki, surface a "Brief me" button that triggers the briefing skill.
- [ ] 4.8  **RAW-folder ingest trigger** — implements the chosen Q5 option; calls the wiki ingest pipeline per `AGENTS.md` rules. _Sidecar pipeline shipped Phase 2 (commits `5ee83c4`, `abfde82`, `70d58c8`); dashboard surface shipped in change `jakeos-ingest-surface-module` (2026-05-02). Remaining piece: wiring an actual wiki ingest pipeline to the trigger — currently the watcher only updates the manifest but does not run wiki ingest._
  - [ ] 4.8.1  **Watcher error reporting** — `sidecar/src/ingest/manifest.rs` `scan_and_diff_blocking` uses `WalkDir::new(...).filter_map(Result::ok)` which silently drops directory-missing or read errors and writes the trigger row as `outcome: no-op` instead of `outcome: error`. The indicator's amber/red surface in `jakeos-ingest-surface-module` therefore never fires from realistic failure modes (missing `raw/`, permissions, ENOSPC). Fix: count `Err` entries from `WalkDir`, capture the first error message, and write `outcome: error` + populate `ingest_triggers.error` when any walker entry failed. _Surfaced during `jakeos-ingest-surface-module` 2026-05-02 e2e verification._
- [ ] 4.9  **Auto-reply opt-in (per category)** — UI to enable/disable per email category; never blanket; categories defined in 4.2.
- [x] 4.10  **File-to-markdown capture** — Helper.app's existing Swift drop pipeline (PDF / image / RTF / HTML / .docx / .epub / .ipynb / etc.) is now wired to the sidecar's audit + dashboard registration layer; menubar bare-icon drop, URL drops with naive readability extraction, clipboard screenshot import, .eml + .webp added, unsupported-type notifications, sidecar `POST /captures` registration with file-backed pending-sync queue for offline retry. Dashboard "Recent captures" enriched with mime + size + companion link. Implemented in change `jakeos-capture-module` (2026-05-02). Architecture: conversion stays in Swift; sidecar is the audit + dashboard registration layer (no Rust pipeline). Spec deltas: `.doc` and `.mbox` deferred to a follow-up.

---

## Phase 5 — Self-improvement loop

Only relevant if Q4 ≠ Ⅳ (defer).

- [ ] 5.1  Implement the daily loop runner per `self-loop/spec.md`.
- [ ] 5.2  Wire the audit log (Phase 2.4) so every loop-initiated write is reviewable.
- [ ] 5.3  Implement the chosen safety boundary: diff-and-approve UI / sandbox+smoketest harness / auto+rollback snapshot, per Q4.
- [ ] 5.4  First dry-run on a fixture day; confirm no destructive writes.

---

## Phase 6 — Ship & verify

- [ ] 6.1  End-to-end test: open dashboard, see todos / email / calendar / employment / briefings; capture a new todo via Cowork input; verify it appears on the macOS surface (or wherever the source of truth lives).
- [ ] 6.2  Token-budget audit: measure tokens-per-dashboard-load and per-update; document in `openspec/specs/dashboard/spec.md` as the v1 budget.
- [ ] 6.3  Push `~/Documents/jakeos` to GitHub as `JakeOS` (bullet 19 of source notes).
- [ ] 6.4  Run `openspec validate --change jakeos-dashboard-v1`. All artifacts pass.
- [ ] 6.5  `/opsx:archive jakeos-dashboard-v1` once the long-lived specs are in place and at least Phase 4.1 + 4.5 work end-to-end.

---

## Cross-cutting checks (run continuously, not in order)

- [ ] C.1  No monolithic skill — enforced by `orchestration/spec.md` (single orchestrator, 300-line per-skill budget, single responsibility, depth limit). Drift audit runs weekly per that spec.
- [ ] C.2  Scripts preferred where they suffice (bullet 18).
- [ ] C.3  All reads measured against the v1 token budget once it exists.
- [ ] C.4  No fabricated facts from `~/.claude/skills/job-applier/references/hard-constraints.yaml` — the dashboard never invents application status.

---

## Open follow-on changes (queued, not part of this change)

- `jakeos-visual-system` — UI styling, components, color, motion.
- `jakeos-email-classifier-loop` — the importance-learning loop.
- `jakeos-mobile` — only if/when desired.
- `jakeos-multi-user` — only if it ever becomes needed.
