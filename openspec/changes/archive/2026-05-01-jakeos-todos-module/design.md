## Context

Phase 3.1 of `jakeos-dashboard-v1` left the todos card at a half-state: it polls `GET /todos?status=open` every 10s and renders each as a row with a "done" button that calls `PATCH /todos/:id/complete` and re-renders. The sidecar already exposes the full surface needed for round-trip:

- `GET /todos?status=open|completed|all&limit=N`
- `POST /todos {text, source}`
- `PATCH /todos/:id/complete`
- `PATCH /todos/:id/reopen`

Source of truth is the sidecar's SQLite `todos` table (id, text, completed_at, source, created_at, updated_at). Wiki-stored todos are out of scope for this change — todos here are sidecar-native.

The Cowork input at the bottom of the dashboard already creates todos from free text (Cowork classifier defaults to todo when text doesn't end in `?`). That path is fine for "I had a thought" capture but is the wrong affordance for "I want to add this specific thing to my todo list right now" — it routes through a classifier and emits a generic confirmation, not a row appearing in the todos card.

## Goals / Non-Goals

**Goals:**

1. Round-trip parity: the dashboard exposes every todo capability the sidecar already supports — read open + recently-completed, add, complete, reopen.
2. Discoverability of uncheck: completed todos remain visible long enough that the user can uncheck them without leaving the dashboard.
3. Inline add: the todos card has its own input distinct from the Cowork input.
4. Snappy UX: writes round-trip through the sidecar but feel immediate (no spinner, no full-page reload), via HTMX `hx-swap` with the server-rendered fragment as the response.
5. Offline behavior preserved: when the sidecar is unreachable, completed/open list still renders from cache, write controls disable, no fake-success on submit.

**Non-Goals:**

- No optimistic updates / client-side todo state. HTMX renders the server response; if the sidecar is down, the request fails and the row stays as-is. The 10s poll re-establishes truth on its own. (Optimistic UI doubles the failure surface for negligible UX gain at our latencies.)
- No bulk operations (multi-select, "complete all", reorder). Out of scope; if/when wanted, a separate change.
- No editing todo text after creation. The sidecar doesn't expose `PATCH /todos/:id` for text — adding it is a Phase 2 expansion, not this change.
- No wiki-backed todos (Obsidian-stored markdown todos). Captured under `data-contract`'s "Wiki is the source of truth for note text" rule and explicitly excluded from this change.
- No keyboard shortcuts beyond Enter-to-submit on the inline input.

## Decisions

### Decision 1: List shape — show open + last 5 completed-today

**Choice:** The todos card renders all open todos (sorted by `updated_at desc`, capped at 25) followed by the most recent 5 completed-today todos in a visually-deemphasized state, each with an "↩︎ undo" affordance.

**Why:** Discoverability of uncheck. Without seeing the completed item, the user has no surface to uncheck it on. Capping at 5/today keeps the list from drifting into archive territory. "Today" is computed client-side from `completed_at` ≥ 00:00 local — easy to render without a new endpoint.

**Alternatives considered:**

- *Show only open todos, with a separate "completed" view behind a toggle.* Rejected: a toggle adds a click and hides the affordance; the spec wants discoverability without expansion.
- *Show all completed regardless of recency.* Rejected: list bloat. Old completions aren't relevant to today's work.
- *Strikethrough completed inline (no separator).* Rejected: visually noisy when many completions accumulate; the soft separator gives a clear "below this is yesterday" affordance even when the count is small.

### Decision 2: Two GETs vs one

**Choice:** Issue two parallel `GET /todos?status=open&limit=25` and `GET /todos?status=completed&limit=20` calls server-side; the section endpoint joins and renders. The completed-list is filtered server-side to today's completions.

**Why:** The sidecar has `status=open|completed|all`. Asking for `all` returns the full set sorted by `updated_at desc`, which doesn't preserve "open first". Two queries are cheaper than parsing/sorting `all` results client-side, and they cache independently in `sidecar.js`'s offline cache.

**Alternatives considered:**

- *Add `GET /todos/today` to the sidecar.* Rejected: avoids a sidecar change. Two existing endpoints are enough.
- *Parse `?status=all` and split.* Rejected: a single 200-row response sorted by `updated_at` doesn't reliably surface today's completions; we'd have to over-fetch and then filter.

### Decision 3: HTMX swap shape — replace section body, not row

**Choice:** Both `complete` and `reopen` server endpoints respond with the entire todos-section fragment (the same body that `GET /sections/todos` produces). HTMX swaps `#card-todos .card-body` `innerHTML`.

**Why:** Avoids row-level state divergence. The simplest correct thing is "after any write, re-render the whole section from authoritative state." Section is small (≤30 rows). Latency is dominated by the round-trip to the sidecar over Tailscale (< 50ms typical), not the few KB of HTML.

**Alternatives considered:**

- *Row-level swap (`hx-target="closest li"`, server returns one `<li>`).* Rejected: needs to handle "row moves from open list to completed list" specially. More client/server contract surface.
- *Out-of-band swaps.* Rejected: complexity for no gain at our list size.

### Decision 4: Inline add input — `POST /todos` on the section, returns the new section body

**Choice:** New form at the bottom of the todos card, `hx-post="/todos"`, `hx-target="#card-todos .card-body"`, `hx-swap="innerHTML"`, `hx-on::after-request="this.reset()"`. Form has a single text field. Pressing Enter submits.

**Why:** Mirrors the Cowork pattern already used elsewhere. Server route accepts `{text}`, calls `sidecar.post('/todos', {text, source: 'dashboard'})`, returns the re-rendered section body.

**Alternatives considered:**

- *Reuse the Cowork input.* Rejected per the proposal — Cowork's classifier and confirmation message are wrong for explicit todo capture.
- *Modal popup.* Rejected: extra click, extra state, no benefit.

### Decision 5: Source attribution = "dashboard"

**Choice:** Every write from the web app sets `source: "dashboard"` on the sidecar payload. The sidecar's audit log already maps this to `Surface::Dashboard`.

**Why:** It's already the convention in `jakeos-web/src/server.js` and matches `data-contract/spec.md`'s "originating surface" requirement. No reason to introduce a new source label for this change.

### Decision 6: Empty-state copy

**Choice:** When open list is empty AND no completed-today, render "No todos. Add one below." When open is empty but completed-today is non-empty, render the completed list with no "open" header. When open is non-empty and completed-today is empty, render only the open list.

**Why:** Avoids three-section visual noise when only one section has data. The card stays scannable at a glance.

## Risks / Trade-offs

- **Sidecar unreachable mid-write** → request errors; section re-renders from cache (stale). User sees no row update; the next 10s poll restores truth when the sidecar comes back. The offline banner makes the cause obvious. Mitigation: inline-add input gets `disabled` when offline (same pattern as Cowork input).
- **Race condition: user clicks "done" twice fast** → first PATCH wins, second 404s (todo already completed) or no-ops. Sidecar's `transition_todo` handles re-completion gracefully (writes a fresh `completed_at`). Either way the section re-renders from authoritative state, so the UI converges.
- **Completed-today filter spans midnight** → at 11:59pm the row shows; at 12:00am it disappears. Acceptable — that's what "today" means. No mitigation needed.
- **HTMX swap clobbers focus on the inline add input** → if the user mid-types when a poll fires, focus is lost. Mitigation: `hx-trigger="every 10s"` already excludes elements with the `htmx-busy` class; the form's input doesn't trigger swaps so focus is preserved during typing. (Confirm in v1 testing.)
- **List-length jitter from re-renders every 10s** → poll triggers a full innerHTML swap every 10s even with no changes. Acceptable for v1; if it becomes annoying, switch to `hx-swap="morph"` via a small extension or compute a content hash on the server and short-circuit with a 304.

## Migration Plan

1. Land the change against `jakeos-web` `phase-3.1-scaffold` branch (or a new branch off it).
2. Build + push image: `scripts/push-image.sh` produces `ghcr.io/revjake1/jakeos-web:latest` and `:phase-3.2`.
3. UnRAID pulls the new image: `./unraid.sh up` from Mac.
4. Verify end-to-end per `tasks.md`'s verification section.
5. Mark `jakeos-dashboard-v1/tasks.md` 4.1 `[x]`.

Rollback: `docker tag` the previous `:phase-3.1` digest as `:latest` and `./unraid.sh up`. The sidecar contract didn't change, so old-web ↔ current-sidecar still works.

## Open Questions

- *Should the completed-today list survive a page reload across sessions?* Currently the offline cache is process-local in jakeos-web. If the user reloads, completed items still appear because the sidecar still has them with `completed_at` ≥ today. So yes, no extra work needed.
- *Is "today" local-Mac-time or UTC?* The dashboard's "today" should be the user's wall-clock day. We render server-side, and the server is UnRAID (UTC). For v1, we ship UTC and document the gotcha. If midnight skew becomes annoying, add a `tz` query param or a client-side fix.
