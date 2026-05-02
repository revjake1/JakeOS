## Context

The second-brain wiki at `~/Documents/Obsidian Vault/Second brain/` is governed by `AGENTS.md`. The relevant constraint, quoted verbatim from line 254:

> **Never modify or delete an existing source file in `raw/`.**

This module surfaces todos from `raw/*.md` to the dashboard *without violating that rule*. Detection is read-only; "processing" a detected todo (Promote / Wiki / Dismiss) operates on the sidecar's mirror of the entry, not on the raw file.

Existing infrastructure this design hooks into:

- **Sidecar SQLite store** with numbered migrations under `sidecar/src/db/migrations/`. Migration 1 already covers `todos`, `audit_log`, `ingest_manifest`, `ingest_checkpoint`, etc.
- **FSEvents watcher** at `sidecar/src/ingest/watcher.rs`, debounced 1.5s, calls `manifest::scan_and_diff` per [`ingest/spec.md`](../../specs/ingest/spec.md). The watcher already iterates every debounced batch — this is the natural hook point for the inbox scanner.
- **Audit log** with the schema `(ts, surface, entity_type, entity_id, action, prior_value, new_value, rationale)` per `data-contract/spec.md`.
- **`todos` table** + `POST /todos` endpoint from [`jakeos-todos-module`](../archive/2026-05-01-jakeos-todos-module/) that already accepts `{text, source}`.
- **Dashboard todos card** at [`jakeos-web/src/sections.js`](../../../jakeos-web/src/sections.js) `renderTodos`, which polls `/sections/todos` every 10s and renders open + completed-today + an inline-add form.

The architectural decision (hybrid Model C — `raw/` is never modified by JakeOS, all processing flows through a mirror table) is **locked** by the proposal. This document records the implementation choices that flow from that lock.

## Goals / Non-Goals

**Goals:**

1. Every `- [ ] …` and `- [x] …` line under `~/Documents/Obsidian Vault/Second brain/raw/**/*.md` becomes visible on the dashboard's todos card within one scan cycle of the file landing in `raw/`.
2. Each inbox entry has a deterministic identity (the locked sha256 fingerprint) that survives surrounding-text edits, file renames within the relative-path-lowercase normalization, and check/uncheck flips of the source line.
3. Three "process" verbs operate exclusively on the sidecar's mirror row. Promote-to-todo writes a sidecar `todos` row; Promote-to-wiki appends to `wiki/todos.md`; Dismiss closes the entry. None modify any file in `raw/`.
4. State transitions are auditable: every change emits an audit-log row identifying the surface, the prior state, and the new state.
5. Detection is cheap. Both triggers (FSEvents + 10-min poll) are no-ops when nothing has changed.

**Non-Goals:**

- Wiki/-side todo detection. Scope is `raw/` only. (The user explicitly excluded `wiki/`.)
- Round-tripping check/uncheck back to the source. The source file in `raw/` is read-only by JakeOS.
- Surfacing already-checked source lines (`- [x] …`) as actionable inbox items — they're scanned for fingerprint stability but render as `state=open` once and become `retired` if the user removes them, never `promoted` automatically.
- Threading inbox entries by file or header in the v1 UI. Flat list, scan-order.
- Multi-user, attribution, conflict resolution beyond the existing audit log.
- Deletion of inbox rows. State `retired` exists for that — rows persist for audit.
- An admin UI for the scanner (force-rescan, pause). The 10-minute interval and the FSEvents trigger are sufficient for v1.

## Decisions

### Decision 1: Identity = `sha256(file_path | header_chain | todo_text)` after normalization, locked

**Choice:** Each inbox entry's primary key is `sha256(normalize(file_path) || "\n" || normalize(header_chain) || "\n" || normalize(todo_text))`. Normalization rules:

- **`file_path`** — relative to the vault root (`~/Documents/Obsidian Vault/Second brain/`), lowercase, forward-slash separators, NFC-normalized. Example: `raw/2026-04-29-daily-update-calendar-and-todos.md`.
- **`header_chain`** — every ATX header (`#`, `##`, `###`, …) preceding the line, in order, joined by `|`, each header text lowercased and trimmed of leading/trailing whitespace. Example: `daily 2026-04-29|todos`. Empty string when no preceding header.
- **`todo_text`** — the line minus the leading `- [ ]` or `- [x]` prefix (and any leading whitespace before the `-`), lowercased, internal whitespace runs collapsed to a single space, surrounding whitespace trimmed.

**Why:** This identity scheme is stable under the operations the user performs in `raw/`:

- Checking or unchecking the source line (toggling `[ ]` ↔ `[x]`) does NOT change the fingerprint — the prefix is stripped before normalization.
- Editing surrounding paragraph text in the file does NOT change the fingerprint.
- Renaming the file *does* change the fingerprint, but only if the relative path's lowercase form actually differs. Macro-renames (e.g., archiving an old daily note) reasonably should produce a "new" inbox entry — that's the user's signal that the context changed.
- Editing the todo text itself produces a NEW fingerprint; the old fingerprint stops being seen and transitions to `retired`. The user accepts this v1 trade-off rather than introduce fuzzy matching.

**Why SHA-256 specifically (not BLAKE3):** the user locked SHA-256. It's also a stable industry choice for content-addressed identifiers — fine for our scale (thousands of entries, not millions). 32-byte output stored as a 64-char hex string in SQLite.

**Alternatives rejected:**

- *Line number as part of the fingerprint:* rejected — adding/removing lines above the todo would re-fingerprint every todo in the file.
- *File path + line number alone:* rejected — surrounding edits would silently re-key entries that the user thinks are the same.
- *Fuzzy text matching (e.g., shingle similarity):* rejected — non-deterministic, hard to debug, and the v1 trade-off of "edit-text → new entry" is acceptable.

### Decision 2: Two triggers — FSEvents + 10-minute poll, both no-op when nothing changed

**Choice:** The scanner runs in two contexts:

1. **FSEvents callback.** After each debounced batch in `sidecar/src/ingest/watcher.rs`'s existing run loop, immediately after `manifest::scan_and_diff`, we call `inbox::scanner::scan_all(&db, raw_dir)`. This piggybacks on the spec's existing trigger contract (per [`ingest/spec.md`](../../specs/ingest/spec.md)).
2. **10-minute periodic poll.** `tokio::spawn`-ed task in `bin/jakeos-sidecar.rs` that calls `inbox::scanner::scan_all` every 600s. Belt-and-suspenders for the rare cases where FSEvents drops events (large bulk imports, long sleeps, sync-client batch writes that don't trigger expected event types).

Both paths converge on the same idempotent `scan_all` function. Re-running with no changes is cheap: the SQLite read+upsert per entry is sub-millisecond, and the `last_seen_at` column lets retire-detection use a single sweep.

**Why two triggers:**

- The FSEvents path gives sub-second latency from "Jake jots a todo in a daily note in Obsidian" to "it shows up in the dashboard inbox."
- The 10-minute poll catches anything FSEvents missed (which has happened in practice with iCloud/Dropbox sync clients and during macOS sleep transitions).
- The cost is negligible: a 10-minute poll over ~hundreds of markdown files in `raw/` runs in <50ms on this hardware.

**Why 10 minutes specifically:** if the FSEvents path is working, the poll never matters. If FSEvents is broken, 10 minutes is short enough that Jake won't notice the staleness for any morning-of-day-of work. Going shorter wastes Mac wattage with no UX gain; going longer (e.g., hourly) means Jake might see "I jotted that 45 minutes ago, where is it?"

**Alternatives rejected:**

- *Poll only:* rejected — sub-minute latency matters for the "I just jotted this" case.
- *FSEvents only:* rejected — the user explicitly asked for belt-and-suspenders and FSEvents has known dropped-event modes on macOS.
- *Continuous file-watch + per-file scan:* rejected — `notify` already coalesces events; one scanner pass per debounced batch is the simplest correct shape.

### Decision 3: State machine — five states, one transition graph

**Choice:** Inbox entries live in one of five states:

```
                  ┌──────────────┐
        new entry │ open         │ ──promote-todo──▶ promoted-todo
        ─────────▶│              │ ──promote-wiki──▶ promoted-wiki
                  │              │ ──dismiss───────▶ dismissed
                  └──────────────┘
                         │
                         └──no-longer-in-raw──▶ retired

                  promoted-todo, promoted-wiki, dismissed, retired:
                    no further transitions in v1
```

- **`open`** — default on first scan. The dashboard shows only `state=open` entries.
- **`promoted-todo`** — the user clicked Promote; a new row in `todos` was created. The inbox row stays for audit.
- **`promoted-wiki`** — the user clicked Wiki; a `- [ ] …` line was appended to `wiki/todos.md`. The inbox row stays for audit.
- **`dismissed`** — the user clicked Dismiss. The inbox row stays for audit.
- **`retired`** — the scanner stopped seeing the entry's fingerprint (file removed, todo text changed, file renamed past normalization). System-generated.

**Idempotence:** if the user clicks Promote a second time on a row that's already `promoted-todo`, the endpoint returns `200` with the existing `todos.id` and writes a no-op audit-log entry; it does NOT create a duplicate todo. Same shape for Promote-to-wiki (no second append) and Dismiss (no-op).

**Re-emergence:** if a `dismissed`/`promoted-*` entry's fingerprint is seen again on a future scan, `last_seen_at` is updated but the state is NOT reset to `open`. Once the user has acted on the entry, the action stands; the `raw/` line continues to exist as a historical artifact and does not reappear in the inbox view.

**Why preserve rows after transition:** `data-contract/spec.md` "Audit trail for all writes" requires the prior value of every write to be recorded. Keeping the inbox rows + state-changed metadata makes audit trivially queryable without joining against `audit_log` for every list view.

**Alternatives rejected:**

- *Hard-delete on dismiss:* rejected — loses audit trail; user might mis-click and want recovery.
- *Re-open dismissed entries when re-seen:* rejected — would surface "todos I already decided about" repeatedly. Decisions stick.
- *Separate "snoozed" / "deferred" state:* rejected — out of scope for v1.

### Decision 4: Scanner is one pure function over (db, raw_dir)

**Choice:** `inbox::scanner::scan_all(&db, raw_dir)` walks the directory once, parses each `.md`, computes fingerprints, upserts into `raw_inbox`, and sweeps for retire candidates. It is pure in the sense of taking only `(db, raw_dir)` and producing only DB writes + audit-log entries — no global state, no caches, no I/O outside the directory.

The scanner internally uses two passes:

1. **Discovery pass.** Walk `raw_dir` recursively (skipping non-`.md`, hidden files, anything under a `.obsidian/` directory). For each file: tokenize headers and tasks line-by-line, compute fingerprint per task line, accumulate `(fingerprint, text, file_path, header_chain, line_number)` records.
2. **Reconcile pass.** In one transaction:
   - For each record: `INSERT … ON CONFLICT(id) DO UPDATE SET last_seen_at = ?, line_number = ?` (never overwrite `state`, `text`, `first_seen_at`, or `header_chain` — those are the entry's identity-bound metadata, not refreshed).
   - For every row whose `last_seen_at` < this scan's start time AND `state = 'open'`: transition to `retired`, write audit-log entry.
   - Upserts that produced a fresh row (no prior conflict) emit a `first-seen` audit entry.

**Why one transaction:** atomicity. Either the whole scan lands or none of it does, so a power loss or panic mid-scan can't leave the table in a half-state.

**Why two passes (not stream-as-you-go):** simplifies the retire-detection logic — it just looks at rows whose `last_seen_at` is older than the scan-start timestamp. Streaming would force per-file partial commits.

**Memory budget:** the discovery pass holds all detected todo records in a `Vec`. At a few thousand todos across a few hundred files, this is single-digit MB — fine.

### Decision 5: Markdown task parsing is line-level + simple

**Choice:** A line is a task line if and only if its leading non-whitespace characters match `- [ ]` or `- [x]` (case-sensitive on `x`, with an optional space before the `]`). Indented-list children, nested tasks, and pseudo-tasks (`* [ ]`, `+ [ ]`) are treated as plain task lines if they match `(?:[-*+])\s+\[[ xX]\]`. We accept `- [X]` (uppercase) as completed too — Obsidian users hit this.

Header parsing: ATX only (`#`, `##`, …, up to `######`). Setext headers (`====`/`----`) are parsed as ordinary lines. The header chain is reset to empty when the file's frontmatter ends and rebuilt as we walk; entering a deeper header (more `#`s) appends, entering a shallower or equal header replaces from that depth down.

Frontmatter is skipped: if the file starts with `---`, lines through the next `---` are not parsed.

Code fences (```` ``` ```` and `~~~`) toggle a "in code" flag — task lines inside code fences are ignored.

**Why line-level (not full markdown AST):** correctness for our needs is bounded by what we're looking for: the four characters `- [ ]` or `- [x]` at the start of an unfenced, post-frontmatter line. Pulling in `pulldown-cmark` or `markdown-it` would buy us nothing and add a dependency we'd need to keep in sync with the user's Obsidian flavor.

**Edge cases accepted as v1:**

- HTML-comment-wrapped task lines are scanned. Likely fine.
- Tab-indented vs space-indented don't matter — both are stripped before the prefix check.
- Lists of tasks inside admonitions (`> - [ ] …`) are scanned. Acceptable — they're real tasks the user wrote.
- Templater `<% %>` placeholders inside task text become part of the fingerprint. If the user post-renders the template, the fingerprint changes (old retires, new appears). Accepted.

### Decision 6: `wiki/todos.md` is created on first Promote-to-wiki, not by this change's deploy

**Choice:** The Promote-to-wiki endpoint:

1. Checks for `~/Documents/Obsidian Vault/Second brain/wiki/todos.md`.
2. If absent, creates it with this exact stub:

   ```markdown
   ---
   type: project
   summary: Outstanding todos surfaced from raw notes via the JakeOS dashboard.
   sources: []
   updated: <today YYYY-MM-DD>
   tags:
     - wiki/todos
   ---

   # Todos

   ```
3. Appends a single line: `- [ ] <text>  <!-- from raw-inbox <id-prefix> -->` plus a final newline.

The trailing HTML comment carries an 8-char prefix of the inbox fingerprint so a future change can implement Promote-to-wiki idempotency by greping for the prefix. v1 does not implement that — re-clicking Promote-to-wiki on an already-`promoted-wiki` row is a no-op at the sidecar layer (state check), so the comment is informational.

**Why a project-typed page** (not a synthesis or hub): per `AGENTS.md`'s canonical types, "active outcome with status and next actions" is the closest fit. The page accumulates over time, the user prunes it manually, and it stays as a working list. The agent-readable frontmatter lets the wiki ingest pipeline include it in indices.

**Why not have the change's deploy pre-create the file:** keeps this change strictly additive — if the user has never used Promote-to-wiki, no file appears. The first append is the user's signal that they want this surface to exist.

**Atomicity:** the append is done with `OpenOptions::new().append(true).create(true)` followed by a single `write_all` and an explicit `sync_all`. This is sufficient for our use — Obsidian re-reads the file on inotify, so the user sees the line on the next vault refresh. If the write fails mid-flight, the endpoint returns 500 and the inbox state stays `open`.

**File-locking concerns:** if Obsidian is editing the file at the same instant, the append can interleave with the user's edits. v1 accepts this risk — Obsidian's editor performs its own atomic save dance, and a stray duplicate or out-of-order line is a manual cleanup the user can do. If this becomes a real problem, switch to a `flock`-style advisory lock as a follow-up change.

### Decision 7: Inbox region renders inside the existing todos card

**Choice:** Extend `renderTodos` in `sections.js` to call `renderRawInbox` first and concatenate the result above the existing open-todos rendering. Visual treatment:

```
┌─ TODOS card body ──────────────────────────┐
│   Inbox  (3 from raw notes)                │
│   ─────                                    │
│   • Schedule eye doctor appointment        │
│     daily 2026-04-29 › todos               │
│     [Promote] [Wiki] [Dismiss]             │
│   • Reply to Stouthouse re: Aug shoot      │
│     2026-04-30 photo questions             │
│     [Promote] [Wiki] [Dismiss]             │
│                                            │
│   Active                                   │
│   ─────                                    │
│   ☐ Existing sidecar todo …  [done]        │
│   …                                        │
│   ↪ undo: completed-today todo  [undo]     │
│   [+ Add a todo] [Add]                     │
└────────────────────────────────────────────┘
```

The "Inbox" region is hidden when there are no `state=open` entries (no header, no rule). When non-empty, it always shows the count in the header. Each row's secondary line shows the header chain (last 1-2 segments) as breadcrumbs; full path is in the `title` attribute on hover.

The three buttons each fire `hx-post` to the matching sidecar-proxy route in `server.js`, with `hx-target="#card-todos .card-body"` so the entire card body re-renders from authoritative state — same shape as the existing complete/reopen/add buttons from `jakeos-todos-module`.

**Why one card, not a separate "Inbox" card:** the user's mental model is "things I have to do." Splitting into two cards (Inbox vs Todos) doubles the eyepath without splitting the action. Promote-to-todo moves an item from one region to the other within the same card — clear visual grammar.

**Polling cadence:** the existing 10s poll on `/sections/todos` covers it. No new endpoint cadence to manage.

**Alternatives rejected:**

- *New "Raw Inbox" card alongside todos:* rejected per the mental-model argument above.
- *Modal popup for Promote-to-wiki:* rejected — extra click for no UX gain.

### Decision 8: Audit-log shape uses existing `entity_type=raw_inbox`

**Choice:** Reuse the existing audit_log table from migration 1. Inbox writes use:

- `entity_type = "raw_inbox"`
- `entity_id = <fingerprint>`
- `action ∈ {"first-seen", "promote-todo", "promote-wiki", "dismiss", "retire"}`
- `surface = "scanner" | "dashboard"` (or `Surface::Scanner` / `Surface::Dashboard` in Rust enum form — needs adding `Scanner` to the existing surface enum if it isn't there already; otherwise the scanner uses `surface = "sidecar-internal"` which already exists per the data-contract spec)
- `prior_value` / `new_value`: small JSON objects `{state: "open"}` etc.

Promote-to-todo *also* emits the existing `entity_type=todo, action=create` audit row from the existing `POST /todos` path, so the trace shows two correlated writes.

**Why surface=scanner:** distinguishes user-initiated (dashboard) from system-initiated (scanner) transitions in the audit log, useful for forensics if the scanner ever produces unexpected retires.

## Risks / Trade-offs

- **False-positive task detection** — a markdown line that looks like a task but isn't (e.g., a code snippet outside a fenced block, a quoted email line) appears in the inbox. Mitigation: the user dismisses it; cost is one click. v1 accepts this over heuristic complexity.
- **`wiki/todos.md` collisions with concurrent Obsidian editing** — design.md decision 6 documents this and accepts manual-cleanup as the v1 mitigation.
- **Fingerprint instability under todo-text edits** — an edit to the todo's text retires the old entry and creates a new one. If the user processed the original (Promote-to-todo) and then edits the source line, a "new" inbox entry appears. Mitigation: visible to the user as a fresh inbox row; they Dismiss it. The `todos` row from the earlier Promote is unaffected.
- **Scanner blocking the watcher loop** — the inbox scan runs synchronously in the watcher's task. A pathological vault (10k files) could stall debounced ingest by hundreds of ms. Mitigation: the v1 scope (~hundreds of files) is well below this; if it becomes real, move to a `tokio::spawn` and make the trigger fire-and-forget.
- **Schema migration on a running sidecar** — adding `0002_raw_inbox.sql` requires the new binary to boot. The migrations.rs path already enforces "binary's max-known-version >= on-disk version" so a downgrade after upgrade is blocked. Operationally this is the same `cargo build --release && launchctl kickstart` dance documented in the project memory.
- **`raw/` symlinks pointing outside the vault** — the recursive walk could follow them. Mitigation: walk with `walkdir::WalkDir::new(...).follow_links(false)` (default).
- **Privacy in the audit log** — todo text appears in `prior_value`/`new_value`. The audit log is local-only (sidecar SQLite), so this is acceptable; if Jake ever exports the audit log, it's his to redact.

## Migration Plan

1. Branch `jakeos-raw-inbox-module` off `main` in [Second-brain-helper-app](Documents/Second-brain-helper-app); same in [jakeos-web](Documents/jakeos-web) off `phase-3.1-scaffold`.
2. **Sidecar:**
   - Add `0002_raw_inbox.sql`, append a `Migration { version: 2, … }` entry, bump `MAX_KNOWN_SCHEMA_VERSION` to 2.
   - Add `src/inbox/{mod.rs,scanner.rs,identity.rs}` and `src/api/raw_inbox.rs`.
   - Wire the scanner into `src/ingest/watcher.rs` and the 10-min poll into `src/bin/jakeos-sidecar.rs`.
   - `cargo build --release --bin jakeos-sidecar`.
   - Local smoke: `curl http://127.0.0.1:7843/raw-inbox?state=open | jq` after dropping a `- [ ] smoke test` into a daily note.
   - `launchctl kickstart -k gui/$(id -u)/com.jakeos.sidecar`.
3. **Web:**
   - Add `renderRawInbox` to `sections.js`, wire it into `renderTodos`.
   - Add 3 routes to `server.js`.
   - Add CSS to `layout.js`.
   - `node --check` everything; build + push image via `scripts/push-image.sh`.
4. **Deploy:** `cd ~/Documents/jakeos/phase-3/scripts && ./unraid.sh up`.
5. **Verify** end-to-end per `tasks.md`'s "Verification" section.
6. **Open PRs** for each repo and the JakeOS umbrella.

**Rollback:**

- *Sidecar regression:* revert the binary; the new SQLite tables stay in place (idempotent migrations don't roll back automatically). The `MAX_KNOWN_SCHEMA_VERSION` check protects against the *opposite* direction; downgrade from a binary that knew about migration 2 to one that doesn't is blocked. So rollback uses the *same* binary version + `git revert` on the calling code, not a binary downgrade. If we truly need to undo migration 2, we'd add a `0003_drop_raw_inbox.sql` follow-up.
- *Web regression:* `docker tag` the previous `:phase-3.x` digest as `:latest` and redeploy. Sidecar contract is additive, so old web ↔ new sidecar continues to work (the old web simply doesn't surface the new endpoints).

## Open Questions

- *Should the inbox scanner have its own audit-log surface label, or reuse `sidecar-internal`?* Decision 8 picks `scanner` for clarity; if the existing `Surface` enum doesn't permit it, we either widen the enum (small change) or fall back to `sidecar-internal`.
- *Should `wiki/todos.md`'s frontmatter `sources` field be populated with the raw file path on each promote?* Likely yes long-term, but v1 keeps it as `sources: []` and lets the user/wiki-ingest pipeline backfill. Tracked as a follow-up.
- *Should we expose a "show retired" filter in the dashboard?* No for v1; the audit log answers "what happened to that todo I jotted last Tuesday" without UI.
- *Recursive header chain depth limit?* No explicit cap; ATX headers max at depth 6 anyway, so any chain is at most six segments. If users somehow nest deeper via comments, the chain is already bounded.
