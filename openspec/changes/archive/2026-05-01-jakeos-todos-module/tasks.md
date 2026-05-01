# jakeos-todos-module — Tasks

> Follow-up to `jakeos-dashboard-v1`. Implements task 4.1 of that change end-to-end. All code work is in `~/Documents/jakeos-web` unless noted. No sidecar code changes expected (per `design.md` decisions).

Repo legend (matches `jakeos-dashboard-v1`):
- 🅙 = `~/Documents/jakeos` (this repo — specs only)
- 🅦 = `~/Documents/jakeos-web` (the dashboard app)
- 🅜 = `~/Documents/Second-brain-helper-app` (Rust sidecar)

Commits in 🅦 must reference `jakeos-todos-module` per the convention in `openspec/project.md`.

---

## 1. Sidecar audit (no code expected)

- [x] 1.1 🅜 Confirmed: `sidecar/src/api/todos.rs` `list()` selects `WHERE completed_at IS NOT NULL ORDER BY completed_at DESC LIMIT ?1` for `status=completed`. Limit is honored.
- [x] 1.2 🅜 Confirmed: `reopen()` accepts `Option<Json<CompleteBody>>` (so `{source}` is optional) and routes through `transition_todo()` which writes an audit_log entry with `action: "reopen"`.
- [x] 1.3 🅜 No gap; both endpoints are sufficient. Proceeding without sidecar changes.

## 2. jakeos-web — section renderer

- [x] 2.1 🅦 Branched `jakeos-todos-module` off `phase-3.1-scaffold` in `~/Documents/jakeos-web`.
- [x] 2.2 🅦 `renderTodos` now does parallel `sidecar.getCached` for open + completed, filters completed via `isCompletedToday()` (UTC day match).
- [x] 2.3 🅦 Open list, then `<hr class="todos-sep">` (only when both lists non-empty), then completed-today list with `↩︎ undo` buttons posting to `/todos/:id/reopen`.
- [x] 2.4 🅦 Empty state "No todos. Add one below." renders only when both lists empty; otherwise only the non-empty list shows. Inline-add form always rendered.
- [x] 2.5 🅦 `addForm()` helper produces the HTMX form; disabled + tooltip when offline; resets after submit.

## 3. jakeos-web — server routes

- [x] 3.1 🅦 `POST /todos` parses form body, rejects empty, POSTs to sidecar with `source: 'dashboard'`, re-renders section on either branch (success / failure prepends error).
- [x] 3.2 🅦 `POST /todos/:id/reopen` mirrors `complete`, PATCHes sidecar, re-renders.
- [x] 3.3 🅦 Both routes sit below `app.use('*', requireJake)` (server.js:24), so they're auth-gated automatically.

## 4. Visual polish

- [x] 4.1 🅦 Added `hr.todos-sep` (dashed rule), `ul.todos-completed li.todo-completed .text` (muted + strikethrough), and `form.todo-add` (compact flex form with input + small button).
- [x] 4.2 🅦 Card already has `min-height: 180px` from base styles (layout.js:111). No additional rule needed; revisit if real-world testing shows visible flicker on poll swaps.

## 5. Build + ship

- [x] 5.1 🅦 Local smoke against real sidecar: add → complete → reopen → complete round-trip; audit_log entries match (create/complete/reopen/complete from `dashboard`).
- [x] 5.2 🅦 Built + pushed `ghcr.io/revjake1/jakeos-web:latest` and `:phase-3.2` (multi-arch, digest `sha256:612b40b4…`). `push-image.sh` updated to make the version tag env-overridable.
- [x] 5.3 🅙 [jakeos-web#1](https://github.com/revjake1/jakeos-web/pull/1) opened against `phase-3.1-scaffold`.
- [x] 5.4 🅙 UnRAID stack synced + brought up on the new image. Container running on `:latest` (digest `sha256:612b40b4…`).

## 6. End-to-end verification

- [x] 6.1 🅦 Browser verification passed ("Looks good"). Todos card renders open + completed-today + inline-add input as designed.
- [x] 6.2 🅦 Add via inline input verified. (`source = 'dashboard'` already proven by local smoke 5.1.)
- [x] 6.3 🅦 Done → completed-today list verified.
- [x] 6.4 🅦 Undo → open list verified.
- [x] 6.5 🅦 Offline behavior verified.
- [x] 6.6 🅦 Cross-surface check rolled into the round-trip verification (dashboard surface confirmed end-to-end). A separate Helper.app cross-surface pass will land with the Helper.app drag-drop change (Phase 4.10).

## 7. Close out

- [x] 7.1 🅙 Marked `4.1 [x]` in `jakeos-dashboard-v1/tasks.md` with a pointer to this change.
- [x] 7.2 🅙 `openspec validate jakeos-todos-module` → "Change 'jakeos-todos-module' is valid".
- [x] 7.3 🅙 Archived 2026-05-01 via `/opsx:archive jakeos-todos-module`.
