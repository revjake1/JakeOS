## Context

The Phase 2 ingest pipeline in `Second-brain-helper-app/sidecar` is feature-complete:

- FSEvents watcher subscribes to `~/Documents/Obsidian Vault/Second brain/raw/` (commit `5ee83c4`).
- 1.5s debounce, manifest-based change detection (BLAKE3 hash, not mtime), resume-on-wake via FSEvents checkpoint, idempotent firing (commit `abfde82`).
- `POST /ingest/rescan` for manual full-walk + audit-log writes on every fire (commit `70d58c8`).
- Audit-log table in the sidecar's SQLite store. Each row carries: `at` (timestamp), `mechanism` (`fsevents` | `manual-rescan`), `manifest_hash`, `trigger_files` (newline-joined or JSON-array), `outcome` (`ingest-run` | `no-op` | `error`), and `error_message` when `outcome=error`.

The user-facing gap: the dashboard renders no ingest state. Both `ingest/spec.md` "Surface visibility" and `dashboard/spec.md` "Manual ingest rescan control" require it; neither has a renderer. Phase 4.8 of `jakeos-dashboard-v1` left it implicit ("show progress + outcome") without specifying *where* on the dashboard.

The dashboard already polls section endpoints every 10s (per `jakeos-todos-module/design.md`). HTMX is the swap mechanism. The dashboard's chrome (header / footer) is currently sparse: the offline banner, the "last sync" indicator, and the Cowork input are the only persistent elements.

## Goals / Non-Goals

**Goals:**

1. Concretize the existing "Surface visibility" requirement from `ingest/spec.md` so it's testable end-to-end.
2. Surface ingest state from any dashboard view in a token-cheap way (no new section card; chrome-only).
3. Promote ingest *errors* to first-class visibility — today they live only in the audit log and are unreadable from any surface.
4. Reuse the existing `POST /ingest/rescan` write contract — no behavioral changes to the watcher.
5. Stay within the dashboard's "Token / context budget" requirement. The collapsed indicator is one short line; the drawer is opt-in on click.
6. Preserve the dashboard's offline behavior: indicator falls back to cached `/ingest/status`, Re-scan disables.

**Non-Goals:**

- No new pipeline work in the watcher. The watcher already fires correctly; this change reads what it already writes.
- No new audit-log columns. The endpoint projects the existing schema.
- No streaming / SSE for the indicator. It rides the existing 10s poll. (If a 10s lag becomes annoying after a Re-scan, design decision 4 below handles the immediate-render case.)
- No "ingest history" surface beyond the last 10 events in the drawer. Bulk audit-log browsing is out of scope; if wanted, a separate change.
- No editing of audit-log entries. Read-only, always.
- No mobile-responsive styling beyond what the dashboard already has.

## Decisions

### Decision 1: Indicator placement — footer chrome bar, not header

**Choice:** The ingest indicator lives in the dashboard's existing footer chrome alongside the "last sync at <time>" hint, on its own row. Right-aligned. One short line: `Ingest: <relative_time>, <N> pending [Re-scan]`.

**Why:** The dashboard's "Token / context budget" requirement caps per-load tokens, and a section card with a header rule would pull more weight than the data justifies. Ingest state is glanceable, not actionable-most-of-the-time. Footer chrome already hosts the `last sync` indicator the user reads the same way. Header-bar placement competes with the (still-to-be-built) breadcrumb / view title and would push the dashboard's primary content below the fold on shorter viewports.

**Alternatives considered:**

- *Section card alongside todos / calendar.* Rejected: too heavy for a one-line status. Section cards in this dashboard exist for surfaces with daily-actionable lists.
- *Header chrome bar.* Rejected: pushes primary content down; the indicator is rarely the user's reason for visiting the dashboard.
- *Floating badge in a corner.* Rejected: inconsistent with the rest of the dashboard's typography. Footer is the existing convention for system status.

### Decision 2: Drawer vs popover for the audit-log detail view

**Choice:** A `<details>`-element drawer that slides up from the footer when the indicator is clicked. Lists the last 10 events from `/ingest/status`'s `recent_events` array. Re-scan button lives at the top-right of the drawer.

**Why:** A `<details>` drawer is HTMX-friendly and survives page swaps without JS state. A popover competes with the offline banner and would need positioning logic; a drawer reuses the footer's full width and lets the user scan 10 rows at once without the popup feeling cramped.

**Alternatives considered:**

- *Right-side drawer (slide in from edge).* Rejected: the dashboard is desktop-first and the right edge is unused, but a side drawer would obscure section content. Footer-anchored drawer pushes content up only when opened.
- *Modal dialog.* Rejected: too heavy a dismissal action for a glanceable detail view.
- *Inline expansion (the indicator row grows).* Rejected: pushes footer content (offline banner, sync time) around in a jarring way.

### Decision 3: Indicator coloring — three states, derived purely from timestamps

**Choice:**

- **Neutral (default text color):** `last_successful_at != null` AND (`last_error_at == null` OR `last_error_at < last_successful_at`).
- **Amber:** `last_error_at > last_successful_at` AND the most recent error is within the last 24 hours.
- **Red:** `last_error_at > last_successful_at` AND the most recent error is older than 24 hours (i.e., the pipeline is stuck — no successful cycle since).

**Why:** The user wants amber/red on error per the proposal, and the 24h split distinguishes "transient error, watcher will pick up next cycle" (amber) from "ingest has been broken for a day and needs attention" (red). Timestamp-only logic means no extra state in the sidecar — the existing audit-log ordering is enough.

**Alternatives considered:**

- *Two states (neutral / red).* Rejected: amber/red is the user's stated preference and the 24h split is a meaningful operator signal.
- *Spinner during in-flight rescans.* Considered separately under Decision 4 — the indicator does briefly show a spinner *only* while the user-initiated rescan is in flight; the steady-state coloring is timestamp-derived.

### Decision 4: Re-scan UX — sync POST, drawer re-renders with outcome

**Choice:** Click `[Re-scan]` → HTMX POST to jakeos-web's `/ingest/rescan` proxy → the proxy waits for the sidecar's `POST /ingest/rescan` to return → the drawer body re-renders with the new `recent_events` array (the just-fired event sits at the top) and a one-line outcome banner: `0 new` / `N queued for ingest` / `error: <message>`. The `[Re-scan]` button is `hx-disabled-elt="this"` for the duration.

**Why:** Sidecar `/ingest/rescan` is fast for the small `raw/` directory (<200 .md files in practice) — typical round-trip is well under a second. Synchronous waiting keeps the UX honest; the user sees the result of their click instead of a delayed poll surfacing it 10 seconds later. If the user triggers a rescan during a large copy operation and the call exceeds the dashboard's HTTP timeout, jakeos-web surfaces a timeout error in the drawer banner — the next poll cycle will reflect the eventual outcome.

**Alternatives considered:**

- *Async fire-and-forget + rely on the 10s poll.* Rejected: makes manual rescan feel unresponsive. The user clicked because they want a signal *now*.
- *Optimistic "queued…" state with no waiting.* Rejected: hides errors until the next poll; spec calls for "progress + outcome" surfaced.
- *Server-Sent Events for live progress.* Rejected: gold-plating. The rescan is fast enough that a sync wait is fine.

### Decision 5: `pending_count` definition — manifest entries with `outcome=error` or queued-but-not-fired

**Choice:** `pending_count` = number of files in the watcher's current manifest whose hash differs from the most-recent successful ingest's manifest *plus* files in the watcher's debounce window that have not yet fired. In practice: a file dropped in `raw/` shows `pending_count: 1` until the next debounced cycle fires successfully, then drops to 0.

**Why:** The user's mental model is "how many files are sitting in `raw/` that haven't been ingested yet". The manifest already encodes "what the watcher knows about right now"; the audit log encodes "what's been processed". Diffing them is the right answer. No new state needed.

**Alternatives considered:**

- *Always-zero (drop the field).* Rejected: the proposal lists it explicitly. It's a useful operator signal during long copies and during sync-client backlogs.
- *Count files added since `last_successful_at` from the audit log alone.* Rejected: misses files that arrived but were debounced and haven't fired yet.

### Decision 6: Where the read endpoint lives — `src/api/ingest.rs`

**Choice:** `GET /ingest/status` lives in the same `src/api/ingest.rs` module that already hosts `POST /ingest/rescan`. The handler:

1. SELECT the most recent audit-log row for `outcome IN ('ingest-run')` → `last_successful_at`.
2. SELECT the most recent audit-log row for `outcome = 'error'` → `last_error_at`, `last_error_message`.
3. SELECT the last 10 audit-log rows in `at` desc order → `recent_events[]`.
4. Compute `pending_count` from the watcher's in-memory manifest diff (see Decision 5). The watcher exposes a read-only handle for this; if it doesn't yet, add one (small change, no new persistence).
5. Project to JSON and return.

**Why:** Co-locates ingest reads and writes in one module. SELECT-only endpoint means no locking concerns against the watcher's writes — SQLite WAL handles concurrent readers cleanly. No new file, no new module, no migration.

**Alternatives considered:**

- *New `src/api/status.rs` module for "system status" endpoints.* Rejected: premature abstraction. If `/system/status` becomes a thing later, refactor then.
- *Compute everything from the audit log alone (no manifest read).* Rejected: would miss in-flight debounce queue (Decision 5).

### Decision 7: Endpoint shape is stable from v1; future fields are additive

**Choice:** The documented JSON shape — `{last_successful_at, last_error_at, last_error_message, pending_count, recent_events: [...]}` — is the v1 contract. Future additions (e.g., a per-event `bytes_processed` or `duration_ms`) MUST be additive only.

**Why:** The dashboard renders against a fixed shape. The sidecar's audit-log schema may grow over time; the JSON projection should be stable so jakeos-web doesn't need to be re-deployed in lockstep.

## Risks / Trade-offs

- **Sidecar unreachable mid-rescan** → jakeos-web's proxy returns a timeout/error; the drawer renders with a `error: <message>` banner; the offline banner stays active. The next poll re-establishes truth when the sidecar comes back. *Mitigation:* button stays disabled while in flight (`hx-disabled-elt="this"`), so the user can't double-fire.

- **Audit log grows unbounded** → `recent_events` is capped at 10 by query limit, so the endpoint stays cheap. The audit log itself has no retention policy yet (out of scope here; flag for a future change). *Mitigation:* none needed for v1; raise it as an open question in `jakeos-dashboard-v1` task list if growth becomes a real concern.

- **`pending_count` flickers during large copies** → a 50MB PDF being copied in via Dropbox triggers FSEvents repeatedly during the copy; the manifest sees the file once it stabilizes. The watcher's existing debounce handles this for the watcher's own logic, but the manifest snapshot during the copy may include the partial file. *Mitigation:* Decision 5 ties `pending_count` to "files in the watcher's manifest" rather than "files with any FSEvents activity", so the count converges as the copy completes. Acceptable for v1.

- **Indicator polls every 10s and hits the audit-log table** → a 4-row aggregate query plus a 10-row SELECT ten times a minute, single-user, on a local SQLite database. Trivially cheap. *Mitigation:* none needed.

- **Drawer state on poll re-render** → if the user has the drawer open when the 10s poll fires, the swap could close it. *Mitigation:* the indicator polls the *indicator fragment*, not the drawer. The drawer is rendered by a separate request triggered on click. Pollers exclude `htmx-busy` already. Verify in v1 testing.

- **Time-zone of "<relative_time>"** → "5 minutes ago" is unambiguous; absolute timestamps in the drawer use the user's locale (browser-rendered). The sidecar emits ISO-8601 UTC. *Mitigation:* render the relative time client-side from the ISO timestamp; no server-side locale to think about.

- **Amber/red threshold drift across daylight saving** → the 24h cutoff is wall-clock-naïve (timestamp arithmetic is in UTC). DST changes don't affect a 24h window. No action needed.

## Migration Plan

1. Land the sidecar change first (`GET /ingest/status` in `Second-brain-helper-app`). Deploy via `cargo build --release` + `launchctl kickstart` per the project memory note. Verify the endpoint with `curl https://jakeos-sidecar.<tailnet>.ts.net/ingest/status`.
2. Land the jakeos-web change against a `jakeos-ingest-surface-module` branch off `main`.
3. Build + push image: `scripts/push-image.sh` produces `ghcr.io/revjake1/jakeos-web:latest`.
4. UnRAID pulls the new image: `./unraid.sh up` from Mac.
5. Verify end-to-end per `tasks.md`'s verification section (drop a file in `raw/`, watch indicator increment; click Re-scan with no new files, expect `0 new`; trigger an error path, expect amber/red).
6. Mark the relevant `jakeos-dashboard-v1/tasks.md` line `[x]` once verified.

**Rollback:** the sidecar's `GET /ingest/status` is a SELECT-only addition; rolling back is a binary swap (no schema change to undo). For jakeos-web, re-tag the previous `:latest` digest and `./unraid.sh up`. The endpoint contract being stable (Decision 7) means old-web ↔ new-sidecar still works during a partial rollback.

## Open Questions

- *Should the drawer paginate beyond 10 events?* Probably not for v1 — if the user wants the full audit log, that's a separate "ingest history" surface and a different design conversation. Re-evaluate if real-world usage shows 10 is too few.
- *Is `pending_count` meaningful when `last_successful_at` is null (fresh install, never ingested)?* Yes — it counts files in the manifest. The indicator copy in that edge case reads `Ingest: never run, <N> pending [Re-scan]`. Captured in tasks.md verification.
- *Does the indicator show the rescan-in-flight spinner if a *background* (FSEvents-triggered) ingest is running?* No — the spinner is scoped to user-initiated rescans only. A background fire shows up only after it completes (the indicator updates on the next 10s poll). This keeps the indicator from flickering during normal day-to-day activity.
