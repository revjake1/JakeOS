# jakeos-raw-inbox-module — Tasks

> Follow-up to [`jakeos-dashboard-v1`](../jakeos-dashboard-v1/proposal.md), [`jakeos-todos-module`](../archive/2026-05-01-jakeos-todos-module/proposal.md), and (when archived) `jakeos-ingest-trigger`. Implements the raw-inbox surface end-to-end. Code work spans the Rust sidecar (`Second-brain-helper-app`) and the dashboard (`jakeos-web`).

Repo legend (matches earlier modules):
- 🅙 = `~/Documents/jakeos` (this repo — specs only)
- 🅦 = `~/Documents/jakeos-web` (the dashboard app)
- 🅜 = `~/Documents/Second-brain-helper-app` (Rust sidecar)
- 🅥 = `~/Documents/Obsidian Vault/Second brain/` (the vault — read-only for `raw/`)

Commits in 🅦 and 🅜 must reference `jakeos-raw-inbox-module` per the convention in `openspec/project.md`.

---

## 1. Sidecar — schema + identity

- [x] 1.1 🅜 Branch `jakeos-raw-inbox-module` off main in `~/Documents/Second-brain-helper-app`.
- [x] 1.2 🅜 Add `sha2 = "0.10"` to `sidecar/Cargo.toml` (or confirm an existing SHA-256 path; do not reuse blake3 for fingerprints — the locked algorithm is SHA-256).
- [x] 1.3 🅜 Create `sidecar/src/db/migrations/0002_raw_inbox.sql`:
  - Table `raw_inbox` with columns `(id TEXT PRIMARY KEY, text TEXT NOT NULL, file_path TEXT NOT NULL, header_chain TEXT NOT NULL, line_number INTEGER NOT NULL, state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open','promoted-todo','promoted-wiki','dismissed','retired')), first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, state_changed_at TEXT NOT NULL, state_change_source TEXT NOT NULL DEFAULT 'scanner')`.
  - Indexes on `(state, last_seen_at)` for the `state=open` list and on `file_path` for retire sweeps.
  - Use `IF NOT EXISTS` for idempotence per `data-contract/spec.md` "Schema migrations are explicit".
- [x] 1.4 🅜 Append `Migration { version: 2, … }` to `MIGRATIONS` in `sidecar/src/db/migrations.rs`.
- [x] 1.5 🅜 Bump `MAX_KNOWN_SCHEMA_VERSION` to `2` in `sidecar/src/db/mod.rs`.
- [x] 1.6 🅜 Create `sidecar/src/inbox/identity.rs` exposing `fingerprint(file_path: &Path, vault_root: &Path, header_chain: &[String], todo_text: &str) -> String` returning a 64-char hex SHA-256, with normalization exactly per `design.md` Decision 1. Add a unit test asserting:
  - Same fingerprint for `- [ ]` vs `- [x]` of the same line.
  - Same fingerprint after editing surrounding (non-todo, non-header) lines.
  - Different fingerprint after editing the todo text.
  - Same fingerprint regardless of original casing of `file_path`.

## 2. Sidecar — scanner

- [x] 2.1 🅜 Create `sidecar/src/inbox/scanner.rs::scan_all(db: &Db, vault_root: &Path) -> ScanOutcome`. Walk `vault_root.join("raw")` recursively with `walkdir::WalkDir::new(...).follow_links(false)`. Skip non-`.md`, hidden files, and any file whose path contains a hidden segment.
- [x] 2.2 🅜 Per file, parse line-by-line:
  - Skip frontmatter (everything between leading `---` lines).
  - Toggle "in code fence" on ```` ``` ```` and `~~~` lines.
  - For ATX headers, maintain a header stack so `header_chain` reflects the deepest path at the current line.
  - For task-like lines (`(?:[-*+])\s+\[[ xX]\]`), compute the fingerprint and accumulate `(fingerprint, text, file_path, header_chain, line_number)`.
- [x] 2.3 🅜 Reconcile in one transaction:
  - For each accumulated record, `INSERT … ON CONFLICT(id) DO UPDATE SET last_seen_at = ?, line_number = ?` only.
  - For pre-existing rows whose `last_seen_at < scan_start_ts AND state = 'open'`, transition to `retired` and emit an audit-log entry (`entity_type=raw_inbox, action=retire`).
  - For freshly-inserted rows, emit an audit-log entry (`action=first-seen`).
- [x] 2.4 🅜 Wire `inbox::scanner::scan_all` into `sidecar/src/ingest/watcher.rs` immediately after the existing `manifest::scan_and_diff` call inside the debounced batch handler.
- [x] 2.5 🅜 Spawn a 10-minute periodic poll in `sidecar/src/bin/jakeos-sidecar.rs` (`tokio::spawn` an `interval` loop) calling the same `scan_all`.
- [x] 2.6 🅜 Confirm both triggers no-op cleanly when nothing has changed (no audit-log entries on a re-run over identical content). Add a unit test or integration test that runs `scan_all` twice and asserts the second run produces zero new audit rows.

## 3. Sidecar — API endpoints

- [x] 3.1 🅜 Create `sidecar/src/api/raw_inbox.rs` with `routes()` exposing:
  - `GET /raw-inbox?state=open&limit=N` returning `[{ id, text, file_path, header_chain, nearest_header, first_seen_at, line_number }]` ordered by `first_seen_at ASC`. Default `limit=50`.
  - `POST /raw-inbox/:id/promote-todo` → look up the inbox row, insert into `todos` with `text` and `source: "raw-inbox"` via the existing audit-write path, transition the inbox row to `promoted-todo`, return `{ todo_id, inbox_state: "promoted-todo" }`. Idempotent: if already promoted, return the existing `todo_id` and write a no-op audit entry (`action=promote-todo-noop`).
  - `POST /raw-inbox/:id/promote-wiki` → look up the inbox row, ensure `wiki/todos.md` exists (create with the canonical stub from `design.md` Decision 6 if absent), append `- [ ] <text>  <!-- from raw-inbox <id-prefix> -->\n`, fsync, transition the inbox row to `promoted-wiki`. Idempotent: skip the append if state is already `promoted-wiki`.
  - `POST /raw-inbox/:id/dismiss` → transition to `dismissed`. Idempotent.
- [x] 3.2 🅜 Audit-log writes on every transition: `surface = scanner` for system-driven (first-seen, retire), `surface = dashboard` for the three process verbs. If `Surface::Scanner` is not yet in the existing enum, add it (otherwise fall back to `sidecar-internal`).
- [x] 3.3 🅜 Register the new router in `sidecar/src/api/mod.rs`.
- [x] 3.4 🅜 Strict invariant test: instrument `OpenOptions` use under `raw/` with a debug assertion that the path is being opened for read only. (Or simpler: a unit test that walks the new code paths and asserts no `OpenOptions::new().write(true)` call references a `raw/` path.)

## 4. Sidecar — build + deploy

- [x] 4.1 🅜 `cargo build --release --bin jakeos-sidecar`. Confirm clean (warnings limited to the new modules' debug-assertion path, if any).
- [x] 4.2 🅜 Local smoke against the running sidecar:
  ```
  echo $'\n- [ ] Smoke test inbox at '"$(date)" >> "/Users/jakehallman/Documents/Obsidian Vault/Second brain/raw/2026-04-29-daily-update-calendar-and-todos.md"
  curl -s http://127.0.0.1:7843/raw-inbox?state=open | jq '.[0:5]'
  ```
  Confirm the smoke-test entry appears.
- [ ] 4.3 🅜 Strip the smoke-test line manually from the source file (the user is allowed to edit `raw/`; JakeOS is not). Re-run the curl; confirm the row's state transitions to `retired` on the next scan. **Jake-side cleanup:** smoke entries (`Smoke test raw-inbox …`, `SMOKE-promote …`, `SMOKE-wiki …`, `SMOKE-dismiss …`) were left in `raw/2026-04-29-daily-update-calendar-and-todos.md` — the permission engine correctly blocked the agent from rewriting the file. Delete them in Obsidian when convenient; the inbox rows will retire on the next scan.
- [x] 4.4 🅜 `launchctl kickstart -k gui/$(id -u)/com.jakeos.sidecar`. Confirm new PID and that the 10-minute poll is logged on startup.
- [x] 4.5 🅜 Commit `jakeos-raw-inbox-module` on the sidecar branch.

## 5. Web — render the inbox region

- [x] 5.1 🅦 Branch `jakeos-raw-inbox-module` off `phase-3.1-scaffold` in `~/Documents/jakeos-web`.
- [x] 5.2 🅦 Add `renderRawInbox({ accessToken, offline })` to `src/sections.js` — calls `sidecar.getCached('/raw-inbox?state=open', { accessToken })`, renders header + count + entries; returns empty string when no rows.
- [x] 5.3 🅦 Each row renders text, source-file path (last segment, full path in `title`), header chain (last 1-2 segments or `(no heading)`), and three `<button class="linklike">` elements wired to `hx-post="/raw-inbox/:id/promote-todo|promote-wiki|dismiss"` with `hx-target="#card-todos .card-body"` and `hx-swap="innerHTML"`.
- [x] 5.4 🅦 In `renderTodos`, call `renderRawInbox(...)` first and prepend its output to the existing body. Active-todos rendering and the inline-add form remain unchanged.
- [x] 5.5 🅦 Add 3 routes to `src/server.js` that proxy to the sidecar's process-verb endpoints, then re-render `renderTodos(...)` so HTMX swaps the section atomically.
- [x] 5.6 🅦 Add CSS to `src/layout.js` for `.inbox-region`, `.inbox-row`, `.inbox-meta`, `.inbox-actions`. Match the dashboard's existing palette (`--accent`, `--muted`, `--border`, `--fg`).
- [x] 5.7 🅦 Disable the three buttons + tooltip when offline (mirror the existing `disabled title="Offline — writes disabled"` pattern from todos).

## 6. Web — local smoke + ship

- [x] 6.1 🅦 `node --check src/sections.js src/server.js src/layout.js`.
- [x] 6.2 🅦 Build + push image: `scripts/push-image.sh`. Capture the digest in the PR.
- [x] 6.3 🅦 `cd ~/Documents/jakeos/phase-3/scripts && ./unraid.sh up`. Confirm the new web container is running.

## 7. End-to-end verification

- [ ] 7.1 🅦 In Obsidian, open today's daily note under `raw/` and add a fresh `- [ ] Verify raw-inbox round-trip` line.
- [ ] 7.2 🅦 Reload `https://jakeos.jakehallman.com`. Confirm the line appears in the todos card's Inbox region within ~10s (FSEvents path) or within 10 minutes (poll fallback).
- [ ] 7.3 🅦 Click **Promote**. Confirm the inbox row disappears and a matching `- [ ]` row appears in the active todos list. Confirm `source = "raw-inbox"` on the new `todos` row via `curl http://127.0.0.1:7843/todos?status=open | jq '.[] | select(.text | contains("Verify raw-inbox round-trip"))'`.
- [ ] 7.4 🅥 Confirm the source file in `raw/` is unchanged on disk (`shasum` before-and-after the Promote, `mtime` unchanged from the post-edit state, the `- [ ]` line still reads exactly as Jake wrote it).
- [ ] 7.5 🅦 Drop another `- [ ] Wiki test` into the same daily note. Reload; click **Wiki** on the new inbox row. Confirm `wiki/todos.md` now exists (or has a new appended line if it already existed) with `- [ ] Wiki test` plus the trailing `<!-- from raw-inbox … -->` comment. Confirm the source file in `raw/` is again untouched.
- [ ] 7.6 🅦 Drop a third line and click **Dismiss**. Confirm the inbox row disappears, no `todos` row is created, no append to `wiki/todos.md`, source file untouched.
- [ ] 7.7 🅦 In Obsidian, delete one of the three lines from the daily note. Wait < 10 minutes. Confirm the row's state becomes `retired` (`curl http://127.0.0.1:7843/raw-inbox?state=open` no longer lists it; querying audit log shows the `retire` transition).
- [ ] 7.8 🅥 Audit-log spot check: `curl http://127.0.0.1:7843/audit?entity_type=raw_inbox | jq '.[] | {ts, action, surface, prior_value, new_value}'` shows the chain of transitions for each test entry: `first-seen → promote-todo|promote-wiki|dismiss → (retire)`.

## 8. Close out

- [ ] 8.1 🅙 In `jakeos-dashboard-v1/tasks.md`, link `4.6` (daily staleness sweep) and `4.8` (RAW-folder ingest trigger) to this change as partial implementation pointers — neither is fully closed by this module, but the inbox surface is the most-visible piece of both.
- [ ] 8.2 🅙 `openspec validate jakeos-raw-inbox-module` → "Change 'jakeos-raw-inbox-module' is valid".
- [ ] 8.3 🅙 Open PRs:
  - `revjake1/jakeos-web` head `jakeos-raw-inbox-module` against `phase-3.1-scaffold`.
  - `revjake1/JakeOS` head `claude/...` (worktree branch) against `main`.
  - Note in the JakeOS PR that `Second-brain-helper-app` still has no GitHub remote; sidecar branch lives on the Mac only until that's wired.
- [ ] 8.4 🅙 `/opsx:archive jakeos-raw-inbox-module` after end-to-end verification.

## Verification summary (one paragraph for the close-out commit)

Drop a `- [ ] Verify raw-inbox round-trip` into a daily note in `raw/`; refresh the dashboard; the line appears in the Inbox region of the todos card within one scan cycle. Click **Promote**; the row moves to the active todos list with `source = "raw-inbox"`. The source file in `raw/` is byte-identical before and after — JakeOS never modifies it, honoring the AGENTS.md rule. Repeat for **Wiki** (appends to `wiki/todos.md`) and **Dismiss** (no further action). Delete the line from the source file; on the next scan the row transitions to `retired` and disappears from the Inbox view. Audit log records every transition.
