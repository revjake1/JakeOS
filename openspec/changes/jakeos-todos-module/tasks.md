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
- [ ] 5.4 🅙 On Mac (manual): `cd ~/Documents/jakeos/phase-3/scripts && ./unraid.sh sync && ./unraid.sh up`. Verify with `./unraid.sh status`.

## 6. End-to-end verification

- [ ] 6.1 🅦 Open https://jakeos.jakehallman.com in a browser. Sign in. Confirm the todos card renders both the open list and (if any) today's completed list with the inline-add input.
- [ ] 6.2 🅦 Add a todo via the inline input. Verify it appears within one render cycle and that `sqlite3` against the sidecar's `state.db` shows the row with `source = 'dashboard'`.
- [ ] 6.3 🅦 Click "done" on the new todo. Verify it moves to the completed-today list. Confirm the `audit_log` table has a `complete` entry.
- [ ] 6.4 🅦 Click "↩︎ undo" on the now-completed todo. Verify it returns to the open list. Confirm a `reopen` audit-log entry.
- [ ] 6.5 🅦 Stop the sidecar (`launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.jakeos.sidecar.plist`). Reload the dashboard. Confirm the offline banner appears, the inline-add input is disabled, "done"/"undo" buttons are disabled, and the cached lists remain readable. Restart the sidecar with `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jakeos.sidecar.plist`.
- [ ] 6.6 🅦 Cross-surface check: capture a todo from the macOS Helper.app (when that path exists) or via `curl POST /todos` to the sidecar with `source: helper-app`. Confirm it appears in the dashboard within one poll cycle.

## 7. Close out

- [x] 7.1 🅙 Marked `4.1 [x]` in `jakeos-dashboard-v1/tasks.md` with a pointer to this change.
- [x] 7.2 🅙 `openspec validate jakeos-todos-module` → "Change 'jakeos-todos-module' is valid".
- [ ] 7.3 🅙 Run `/opsx:archive jakeos-todos-module` once Jake has done the UnRAID sync (5.4) and browser verification (6.1–6.6).
