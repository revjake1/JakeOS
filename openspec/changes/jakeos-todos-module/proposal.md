## Why

Phase 3.1 of [`jakeos-dashboard-v1`](../jakeos-dashboard-v1/proposal.md) shipped the dashboard frame, but the todos card only renders open items and a one-way "done" button. The data-contract already specifies bidirectional todo sync, the sidecar already exposes `GET /todos`, `POST /todos`, `PATCH /todos/:id/complete`, and `PATCH /todos/:id/reopen` (Phase 2 commit `abfde82` on `Second-brain-helper-app`), and the dashboard is wired to the sidecar over Tailscale. What's missing is the round-trip: completed todos need to be visible long enough to be unchecked, and the uncheck path needs UI. This change closes that loop and ships task 4.1 of `jakeos-dashboard-v1`.

This is a small scoped follow-up — implementation glue plus a tiny dashboard-spec delta that records *visibility of recently-completed todos* as a requirement (not just an implementation detail), since that property is what makes uncheck discoverable.

## What Changes

- **jakeos-web** todos card renders open + recently-completed (last N completed today, or last 5, whichever is smaller) so completed items remain visible long enough for the uncheck path to be discoverable.
- **jakeos-web** completed items get a "↩︎ undo" affordance that calls `PATCH /todos/:id/reopen` on the sidecar.
- **jakeos-web** todos card gains an inline "add todo" input distinct from the Cowork input, so the user can capture directly into the todos surface without going through the Cowork classifier.
- **jakeos-web** todo writes use HTMX `hx-swap="outerHTML"` on the row (or the section body) so the round-trip feels immediate without optimistic-update bookkeeping.
- **dashboard spec** gains one new requirement: "Todo round-trip visibility" — the dashboard MUST surface recently-completed todos for the user to uncheck, and uncheck MUST round-trip to the sidecar.
- No new sidecar endpoints — `/todos`, `/todos/:id/complete`, `/todos/:id/reopen` already cover the surface.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `dashboard`: add a "Todo round-trip visibility" requirement (recently-completed must be visible; uncheck round-trips); refine the "Sectioned layout" scenario for todos to mention add + check + uncheck. No breaking changes.

## Impact

- **Code**: `~/Documents/jakeos-web/src/sections.js` (the todos renderer), `~/Documents/jakeos-web/src/server.js` (route additions for add + reopen), small CSS in `layout.js` for the inline add input. No sidecar code changes expected.
- **APIs**: No new sidecar endpoints. New jakeos-web routes: `POST /todos` (add), `POST /todos/:id/reopen`. The existing `POST /todos/:id/complete` route stays.
- **Dependencies**: None added.
- **Systems**: UnRAID stack image updates on next push to `ghcr.io/revjake1/jakeos-web:latest`. Sidecar unchanged.
- **Tasks completed**: marks `4.1` `[x]` in `jakeos-dashboard-v1/tasks.md` once verified end-to-end.
