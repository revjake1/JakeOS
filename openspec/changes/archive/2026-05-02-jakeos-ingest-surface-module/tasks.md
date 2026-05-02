# jakeos-ingest-surface-module — Tasks

> Follow-up to [`jakeos-dashboard-v1`](../jakeos-dashboard-v1/proposal.md). Adds the dashboard surface for the ingest pipeline that already shipped in Phase 2 of `Second-brain-helper-app` (commits `5ee83c4`, `abfde82`, `70d58c8`). No watcher / pipeline work — read endpoint over the existing audit-log table plus a slim chrome indicator.

Repo legend (matches `jakeos-dashboard-v1`):

- 🅙 = `~/Documents/jakeos` (this repo — specs only)
- 🅦 = `~/Documents/jakeos-web` (the dashboard app)
- 🅜 = `~/Documents/Second-brain-helper-app` (Rust sidecar)

Commits in 🅦 and 🅜 must reference `jakeos-ingest-surface-module` per the convention in `openspec/project.md`.

---

## 1. Sidecar audit (read existing surface)

- [x] 1.1 🅜 Confirmed: `ingest_triggers(id, ts, mechanism, manifest_hash, files_triggered (JSON), outcome, error)` covers the projection. Spec text refers to an "audit log" but the implementation uses a dedicated `ingest_triggers` table — same data, no blocker.
- [x] 1.2 🅜 Better than design.md anticipated: the manifest already tracks per-file `ingest_state` (`pending`/`processed`/`failed`), so `pending_count` is a single `SELECT COUNT(*) FROM ingest_manifest WHERE ingest_state = 'pending'` — no new accessor needed.
- [x] 1.3 🅜 Confirmed: `POST /ingest/rescan` returns synchronously with the full `RescanResponse` (trigger_id, mechanism, outcome, manifest_hash, changed, touched_unchanged_count). Compatible with design.md decision 4.

## 2. Sidecar — `GET /ingest/status`

- [x] 2.1 🅜 Branched `jakeos-ingest-surface-module` off the current `jakeos-raw-inbox-module` tip.
- [x] 2.2 🅜 Added `IngestStatus` + `IngestStatusEvent` types and `status()` handler in `src/api/ingest.rs`.
- [x] 2.3 🅜 `recent_events` capped at 10 via `ORDER BY ts DESC LIMIT 10` over `ingest_triggers`.
- [x] 2.4 🅜 `pending_count` reuses the existing `ingest_manifest WHERE ingest_state = 'pending'` query (simpler than design.md decision 5; the manifest already tracks this state per file). Note: the existing watcher only sets state = 'pending' on first sight; nothing transitions it back to 'processed' (the wiki ingest pipeline runs externally). v1 surfaces this as-is — `pending_count: 45` on the live machine reflects the real backlog.
- [x] 2.5 🅜 Route wired in `src/api/ingest.rs::routes()` (the routes builder already merged in `src/api/mod.rs`).
- [ ] 2.6 🅜 _Skipped per existing project convention._ The repo has no async/integration test harness; the only unit tests (`inbox/identity.rs`) are sync `#[test]` for pure logic. Adding a tokio + in-memory-SQLite harness just for this projection would be over-engineering. Manual smoke (2.7) covers the projection end-to-end.
- [x] 2.7 🅜 Manual smoke against the live audit log returns the documented shape: `last_successful_at: "2026-05-02T14:38:08…"`, `pending_count: 45`, `recent_events: [10 entries]`. Outcomes seen: `ingest-run`, `touched-but-unchanged`. Mechanisms seen: `fsevents`, `resume-from-checkpoint`.
- [x] 2.8 🅜 `cargo build --release` succeeded; `launchctl kickstart -k gui/$UID/com.jakeos.sidecar` reloaded the daemon; re-`curl` confirms the new binary serves `/ingest/status`.

## 3. jakeos-web — indicator fragment + drawer

- [x] 3.1 🅦 Branched `jakeos-ingest-surface-module` off the current `jakeos-raw-inbox-module` tip.
- [x] 3.2 🅦 No-op as scoped: `src/sidecar.js`'s `getCached(path)` already keys cache by URL automatically (no allowlist). The indicator's calls participate in the offline cache without code changes.
- [x] 3.3 🅦 Added `renderIngestIndicator(status, {offline, outcomeBanner})` to `src/sections.js` with collapsed line `Ingest: <relative_time>, <N> pending [Re-scan]`. `last_successful_at == null` falls back to `Ingest: never run`.
- [x] 3.4 🅦 Color logic via `ingestState({...})` helper: `--ok` / `--warn` (<24h since error) / `--err` (≥24h) classes added in `src/layout.js`.
- [x] 3.5 🅦 `title` attribute on the indicator carries `last_error_message` when in `--warn`/`--err` state.
- [x] 3.6 🅦 Drawer rendered inline via `<details id="ingest-details" hx-preserve="true">`. Lists up to 10 events with timestamp / mechanism / outcome / file label / error message. `hx-preserve` survives the 10s poll's `outerHTML` swap so open state persists.
- [x] 3.7 🅦 Indicator slot placed in `<footer class="cowork">` below the cowork form via `<div id="ingest-indicator" hx-get="/ingest-indicator" hx-trigger="load, every 10s">`. Token cost is one short line collapsed; drawer body adds ~10 events worth of HTML only when open.

## 4. jakeos-web — server routes

- [x] 4.1 🅦 `GET /ingest-indicator` route added: calls `sidecar.getCached('/ingest/status')` and returns `renderIngestIndicator(...)` as the HTMX-swappable fragment.
- [x] 4.2 🅦 `POST /ingest/rescan` reshaped (was re-rendering captures): now calls sidecar rescan, computes outcome banner from `r.value.changed.length` and `outcome`, re-fetches `/ingest/status`, returns the indicator with the banner attached. Errors surface as `error: <message>`.
- [x] 4.3 🅦 Both routes sit below `app.use('*', requireJake)` (server.js line 24), auth-gated automatically.
- [x] 4.4 🅦 Indicator polls `every 10s` via `hx-trigger="load, every 10s"`. Drawer's `<details hx-preserve="true">` keeps open/closed state across swaps; drawer body refreshes on next open.
- [x] 4.5 🅦 `[Re-scan]` button uses `hx-disabled-elt="this"` to disable for the duration of the request.

## 5. Visual polish + offline behavior

- [x] 5.1 🅦 `.ingest-indicator { font-size: 11px; color: var(--muted) }` matches existing footer hint style. `.ingest-line { white-space: nowrap }` keeps the collapsed line single-row.
- [x] 5.2 🅦 `.ingest-drawer { max-height: 220px; overflow-y: auto }` caps drawer height; events scroll inside.
- [x] 5.3 🅦 `renderIngestIndicator(status, { offline })` propagates the offline flag to the Re-scan button (`disabled title="Offline — sidecar unreachable"`). The cached `/ingest/status` response still flows through `sidecar.getCached`, so the indicator renders the last cached state when the sidecar is unreachable.
- [x] 5.4 🅦 Indicator is a sibling of the Cowork form (not a parent), so `hx-swap="outerHTML"` on the indicator does not touch the cowork input — focus is preserved. Confirmed by reading the layout.

## 6. Build + ship

- [x] 6.1 🅦 Local smoke against the live sidecar passed:
  - **Healthy state:** indicator class `--ok`, "Ingest: 2m ago, 45 pending", drawer shows the most recent 10 events with mixed `fsevents` / `resume-from-checkpoint` / `manual-rescan` mechanisms.
  - **Drop a file:** dropped `_jakeos-ingest-smoke-2026-05-02.md` in `raw/`. Within one debounce window the watcher fired; the new file landed at the top of `recent_events` with `outcome: ingest-run, mechanism: fsevents` carrying the smoke filename. `pending_count` incremented from 45 → 46. Smoke file removed.
  - **Re-scan with no new files:** `POST /ingest/rescan` returns the indicator with banner `0 new`; the just-fired event sits at the top with `mechanism: manual-rescan, outcome: no-op`.
  - **Error path (deferred):** the existing watcher swallows `WalkDir` errors via `filter_map(Result::ok)`, so a missing-`raw/` rescan returns `outcome: no-op` rather than `outcome: error` — that's an existing-watcher behavior outside this slice's scope. The endpoint's *projection* of error rows is verified by inspection (the SQL surface returns `error_message` whenever `outcome = 'error'` rows exist); a live error path requires either a real ingest failure or an addition to the watcher's error reporting, which is a separate change.
- [x] 6.2 🅦 Built + pushed multi-arch image `ghcr.io/revjake1/jakeos-web:latest` and `:phase-3.3` (digest `sha256:8e1e0bc7e1493fed164cc689511094a135c877c4f8a33f6d13baa7f6c0bd129d`) via `scripts/push-image.sh`.
- [x] 6.3 🅙 PRs opened: sidecar [`Second-brain-helper-app#1`](https://github.com/revjake1/Second-brain-helper-app/pull/1) and web [`jakeos-web#4`](https://github.com/revjake1/jakeos-web/pull/4). Both branches `jakeos-ingest-surface-module`.
- [x] 6.4 🅙 UnRAID stack synced + brought up on the new image. `docker compose pull` fetched the new `:latest` digest; `jakeos-web` container Recreated → Started. Cloudflare → Caddy → oauth2-proxy chain healthy (anonymous HTTPS returns 403 as expected).

## 7. End-to-end verification (Jake)

- [x] 7.1 🅦 Browser verification on `https://jakeos.jakehallman.com`: indicator visible in footer, single-line collapsed.
- [x] 7.2 🅦 Drop-file: required two follow-up fixes shipped during apply.
  - Fix 1 (`edf6526`): dropped `hx-preserve="true"` from the `<details>` element. The original `hx-preserve` was preserving the entire `<details>` (including `<summary>`), which froze the visible count between full page reloads. Trade-off: the drawer's open/closed state now resets on each 10s poll, which is fine — drawer body always reflects the latest data.
  - Fix 2 (`5d49067`): auto-open the drawer on rescan response (render `<details open>` when `outcomeBanner` is present) so the outcome banner is visible without a second click.
  - After both fixes, indicator increments + settles correctly across polls.
- [x] 7.3 🅦 Re-scan with no new files surfaces the `0 new` banner correctly (after fix 2). Drawer's top row shows `manual-rescan, outcome: no-op`.
- [ ] 7.4 🅦 _Verified by inspection only._ The existing watcher's `WalkDir::new(...).filter_map(Result::ok)` swallows directory-missing errors, so the rescan returns `outcome: no-op` rather than `outcome: error`. The endpoint's projection of error rows is correct (verified by reading the SQL); a live error-path demo would require either a real ingest failure or a separate change to the watcher's error reporting. Documented as a follow-up.
- [x] 7.5 🅦 Offline behavior verified live. With the sidecar `launchctl bootout`'d: the offline banner appeared within ~15s, the indicator fell back to its last cached state (muted styling), `[Re-scan]` was disabled with the offline-reason tooltip. Bringing the sidecar back via `launchctl bootstrap` + dashboard reload restored normal state.
- [x] 7.6 🅦 Token-budget eyeball check: collapsed indicator is one short line in the footer chrome; drawer body adds ~10 events worth of HTML *only when open*. No primary content displaced.

## 8. Close out

- [x] 8.1 🅙 Annotated `jakeos-dashboard-v1/tasks.md` task 4.8 with a pointer to this change. (Box stays unchecked: this change shipped the *dashboard surface* for ingest-trigger; the wiki ingest pipeline itself is still not wired to the trigger.)
- [x] 8.2 🅙 `openspec validate jakeos-ingest-surface-module` → "Change 'jakeos-ingest-surface-module' is valid".
- [x] 8.3 🅙 Archived 2026-05-02 via `/opsx:archive jakeos-ingest-surface-module`.
