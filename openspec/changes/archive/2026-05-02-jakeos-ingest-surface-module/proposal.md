## Why

The ingest pipeline is built. Phase 2 of [`jakeos-dashboard-v1`](../jakeos-dashboard-v1/proposal.md) and the now-archived [`jakeos-todos-module`](../archive/2026-05-01-jakeos-todos-module/proposal.md) shipped the FSEvents watcher, 1.5s debounce, resume-from-checkpoint on wake, manifest hashing, `POST /ingest/rescan`, and trigger audit logging — landed in `Second-brain-helper-app` commits `5ee83c4`, `abfde82`, and `70d58c8`. What's missing is the *surface*: ingest state is invisible from the dashboard. A failed ingest leaves no breadcrumb, a stuck file in `raw/` produces no signal, and the existing "Re-scan now" control specified in [`ingest/spec.md`](../../specs/ingest/spec.md) and [`dashboard/spec.md`](../../specs/dashboard/spec.md) has nowhere to render.

The ingest spec already has a "Surface visibility" requirement: time of most recent successful cycle, count of pending RAW files, and a failed-state indicator that reveals the audit-log entry on click. Today nothing renders any of that. This change closes the gap with one slim read endpoint over the existing audit-log table and a small dashboard chrome element — no new pipeline work.

This is intentionally a small change: every byte of work fits inside the already-defined "Surface visibility" and "Manual ingest rescan control" requirements. The deltas concretize *how* those requirements are met, not what the system does.

## What Changes

### Sidecar — Second-brain-helper-app

- **New read endpoint** `GET /ingest/status` returning a stable shape derived from the existing trigger audit-log table:

  ```json
  {
    "last_successful_at": "2026-05-02T13:42:11Z",
    "last_error_at": null,
    "last_error_message": null,
    "pending_count": 0,
    "recent_events": [
      {
        "at": "2026-05-02T13:42:11Z",
        "mechanism": "fsevents",
        "outcome": "ingest-run",
        "trigger_files": ["daily/2026-05-02.md"],
        "manifest_hash": "blake3:…"
      },
      …
    ]
  }
  ```

  No new tables. No pipeline logic. The endpoint is a SELECT over the existing audit-log rows plus a count of pending entries derived from the watcher's manifest.

- **Audit-log entry shape** is already rich enough (per [`ingest/spec.md`](../../specs/ingest/spec.md) "Trigger audit log": timestamp, originating mechanism, RAW manifest hash, files, outcome). The endpoint projects those fields verbatim — it doesn't add new ones.

### Web — jakeos-web

- **Ingest status indicator** in the dashboard chrome (footer or top chrome bar — exact placement decided in design.md). Slim footprint per the dashboard's "Token / context budget" requirement. Renders `Ingest: <relative_time>, <N> pending [Re-scan]`.
- **State-of-most-recent-attempt coloring**: green/neutral on success, amber/red when `last_error_at > last_successful_at`, with the error message as a hover tooltip and full text in the drawer.
- **Drawer / popover** opened by clicking the indicator. Lists the last 10 entries from `recent_events` with timestamp, mechanism, outcome, and (on the row of any error) the message.
- **Re-scan button** wired to the existing `POST /ingest/rescan` endpoint. Disabled while a rescan is in flight; surfaces outcome ("0 new" / "N queued" / error) inline in the drawer.
- **Offline behavior**: identical to the rest of the dashboard — the indicator falls back to the cached `/ingest/status` response read-only with the existing offline banner; the Re-scan button disables.

### Spec deltas

- **`dashboard/spec.md`**:
  - MODIFY `Manual ingest rescan control` to reference the new ingest status indicator as the surface that hosts the Re-scan button (today the requirement is two sentences; it gains shape).
  - ADD `Ingest status indicator` capturing the chrome-bar/footer indicator, drawer, error-state coloring, and offline behavior.
- **`ingest/spec.md`**:
  - MODIFY `Surface visibility` to spell out the read-endpoint shape and the indicator surface so the requirement is testable end-to-end (today it lists the data fields but not where they're sourced from or rendered).
- **`data-contract/spec.md`**:
  - MODIFY `API surface` to include the new `GET /ingest/status` read endpoint alongside the existing manual ingest rescan write endpoint.

## Capabilities

### New Capabilities

(none — this change extends three existing capabilities)

### Modified Capabilities

- `dashboard`: adds `Ingest status indicator`; tightens `Manual ingest rescan control` to point at it.
- `ingest`: tightens `Surface visibility` with the read-endpoint shape and indicator scenario.
- `data-contract`: extends the `API surface` requirement to enumerate `GET /ingest/status`.

## Impact

- **Code**:
  - Sidecar (`~/Documents/Second-brain-helper-app/sidecar`):
    - `src/api/ingest.rs` — new `GET /ingest/status` handler (SELECT over the audit-log table; project to the documented JSON shape). The existing `POST /ingest/rescan` handler stays as-is.
    - `src/api/mod.rs` — wire the new route.
    - No DB migration. No new columns. No watcher changes.
  - Web (`~/Documents/jakeos-web`):
    - `src/sections.js` *or* `src/layout.js` — new `renderIngestIndicator()` helper rendered in the dashboard chrome (placement decided in design.md). Drawer rendered as an HTMX-targeted overlay or details element.
    - `src/server.js` — new `GET /ingest-indicator` route that fetches `/ingest/status` from the sidecar and returns the rendered fragment; new `POST /ingest/rescan` proxy that re-renders the drawer body with the outcome.
    - `src/sidecar.js` — `getCached('/ingest/status')` so the indicator participates in the offline cache.
    - Minor CSS in `src/layout.js` for the indicator dot, drawer, and amber/red error states.
- **APIs**: 1 new sidecar read endpoint (`GET /ingest/status`). The existing `POST /ingest/rescan` endpoint is unchanged. New jakeos-web routes: `GET /ingest-indicator` (fragment), `POST /ingest/rescan` (proxy returning the drawer fragment).
- **Dependencies**: None added.
- **Systems**: UnRAID stack picks up the new web image on next push to `ghcr.io/revjake1/jakeos-web:latest`. Sidecar binary rebuilds + relaunches via `cargo build --release` + `launchctl kickstart` per the project memory note.
- **Tasks**: Marks the dashboard-side of `jakeos-dashboard-v1`'s ingest-trigger work complete (the sidecar pipeline already landed in `5ee83c4` / `abfde82` / `70d58c8`; this change supplies the dashboard surface that closes the loop).
