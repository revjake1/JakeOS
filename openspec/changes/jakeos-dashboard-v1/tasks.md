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

- [x] 0.1  **Q1. Surface architecture = B** (standalone web app reverse-proxied behind `/jakeos`). Locked 2026-05-01.
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

Only relevant tasks run, depending on Q1.

### If Q1 = A (WordPress page) → 🅦

- [ ] 3.A.1  New plugin `wp-content/plugins/jakeos/` registers a custom page template `/jakeos`.
- [ ] 3.A.2  Page template renders the dashboard frame (todos, email, calendar, employment, briefings, Cowork input) with sections that update via REST polling or SSE.
- [ ] 3.A.3  REST routes proxy reads/writes to the Phase-2 backend per `auth/spec.md`.
- [ ] 3.A.4  Caddy route confirmation: `/jakeos` requires the chosen auth (per Q3) before reaching WP.

### If Q1 = B (standalone web app) → 🅦

- [ ] 3.B.1  Scaffold a new web app at `~/Documents/New_Jakehallman_site/jakeos-app/` (framework chosen during Phase 1.1).
- [ ] 3.B.2  Implement dashboard layout: todos / email / calendar / employment / briefings / Cowork input.
- [ ] 3.B.3  Wire to backend per `data-contract/spec.md`; live updates via WebSocket or SSE.
- [ ] 3.B.4  Add to `docker-compose.yml`; add `Caddyfile` reverse-proxy block for `jakehallman.com/jakeos*` with the chosen auth (per Q3) in front.
- [ ] 3.B.5  Verify Caddy serves `/jakeos` with auth enforced and that WordPress is unaffected.

### If Q1 = C (native macOS only) → 🅜

- [ ] 3.C.1  New SwiftUI scene/window `DashboardScene` in `SecondBrainHelper/`.
- [ ] 3.C.2  Implement dashboard layout panels.
- [ ] 3.C.3  Wire to local data + Rust sidecar endpoints per `data-contract/spec.md`.
- [ ] 3.C.4  Auth = OS account; secrets in Keychain (per Q3 = iv).

### If Q1 = mixed (B + C, etc.) → both 🅜 and 🅦 sub-tasks above, in that order.

---

## Phase 4 — Modules (the 13 capability bullets)

These run in parallel where possible. Each one will be split off into its own follow-up change citing `jakeos-dashboard-v1` once the frame is up.

For v1 of *this* change, only these tasks are required:

- [ ] 4.1  **Todos** — read/write through `data-contract/spec.md`; check/uncheck round-trips to source of truth; verified end-to-end.
- [ ] 4.2  **Important email surface** — Gmail OAuth scope wired (uses the same OAuth from Q3 if applicable); show top-N most-recent likely-important; "mark important / not" writes back.
- [ ] 4.3  **Calendar surface** — Google Calendar OAuth scope wired; show today + condensed upcoming; "add this email as event" prompt path stubbed.
- [ ] 4.4  **Employment section** — read from `~/.claude/skills/job-applier/state/APPLICATION_TRACKER.md`; cross-reference Gmail labels for `Job Apps/*`; render outstanding / needs-followup / rejected (rejected hidden).
- [ ] 4.5  **Cowork input** — bottom input field that posts to a Cowork session (or queues for one) for new todos / ideas / questions.
- [ ] 4.6  **Daily staleness sweep** — scheduled task (per Q5 trigger) flags stale facts; ambiguous ones surface to Jake on the dashboard.
- [ ] 4.7  **Contextual briefings** — when an email or event references a topic in the second-brain wiki, surface a "Brief me" button that triggers the briefing skill.
- [ ] 4.8  **RAW-folder ingest trigger** — implements the chosen Q5 option; calls the wiki ingest pipeline per `AGENTS.md` rules.
- [ ] 4.9  **Auto-reply opt-in (per category)** — UI to enable/disable per email category; never blanket; categories defined in 4.2.
- [ ] 4.10  **File-to-markdown capture** — implement the drop-target on the macOS Helper.app (menubar / dock target), wire it to the Rust sidecar's conversion pipeline (PDF, .docx, .eml, images, URLs), write originals + companion notes to `raw/` per `capture/spec.md` and `AGENTS.md` rules, expose recent-captures in the dashboard.

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
