## Why

The second-brain wiki at `~/Documents/Obsidian Vault/Second brain/` already contains daily notes, meeting notes, and clipped materials full of `- [ ] …` task lines that Jake captured in the moment. They sit in `raw/` indefinitely because nothing surfaces them — ingest summarizes raw sources into wiki pages but doesn't extract todos. The dashboard's todos card (per [`jakeos-todos-module`](../archive/2026-05-01-jakeos-todos-module/proposal.md)) shows sidecar-native todos only. Result: every "remind me to call X" or "look up Y" Jake jots in a daily note disappears into the vault. This change adds a single coherent surface that mirrors raw-file todos to the dashboard so Jake can see them, act on them, and let the originals stay where they are.

The architectural constraint is non-negotiable: per `~/Documents/Obsidian Vault/Second brain/AGENTS.md` line 254:

> **Never modify or delete an existing source file in `raw/`.**

This module is built around honoring that rule. JakeOS reads `raw/` markdown to detect todos and *mirrors* them into a sidecar-owned table; it does not check, uncheck, or rewrite the source. The user's "process" verbs (Promote to todo, Promote to wiki/todos.md, Dismiss) operate on the *mirror* row, never on the source file.

Phase 4 of [`jakeos-dashboard-v1`](../jakeos-dashboard-v1/proposal.md) already established the dashboard frame, the sidecar's audit log, and the FSEvents watcher on `raw/`. [`jakeos-todos-module`](../archive/2026-05-01-jakeos-todos-module/proposal.md) shipped sidecar-native todos with full check/uncheck round-trip. `jakeos-ingest-trigger` (the change that will archive Phase 4.8 — currently still inside `jakeos-dashboard-v1` as the implementation of the FSEvents watcher in `ingest/spec.md`; cite as parent if/when it lands as its own archived change) defines the scan trigger contract this module hooks into.

## What Changes

### Sidecar — Second-brain-helper-app

- **New SQLite table** `raw_inbox` introduced via a new numbered migration (`0002_raw_inbox.sql`). Columns: `id` (sha256 fingerprint, primary key), `text` (todo text, not normalized), `file_path` (relative-to-vault), `header_chain` (pipe-joined), `line_number`, `state` (`open` | `promoted-todo` | `promoted-wiki` | `dismissed` | `retired`), `first_seen_at`, `last_seen_at`, `state_changed_at`, `state_change_source` (the surface that promoted/dismissed it).
- **New scanner module** `sidecar/src/inbox/scanner.rs` (or similar) that walks `~/Documents/Obsidian Vault/Second brain/raw/**/*.md`, parses each file for `- [ ] …` and `- [x] …` task lines, computes the locked `sha256(normalize(file_path) | normalize(header_chain) | normalize(todo_text))` fingerprint per entry, upserts into `raw_inbox`, and transitions entries no longer found to `retired`. Triggered by (a) the existing FSEvents watcher in [`ingest/spec.md`](../../specs/ingest/spec.md) on every debounced fire, and (b) a 10-minute periodic poll inside the sidecar as a belt-and-suspenders fallback.
- **New read endpoint** `GET /raw-inbox?state=open&limit=N` returning entries in scan order with `text`, `file_path`, `header_chain`, `nearest_header`, `first_seen_at`.
- **New write endpoints** for the three process verbs:
  - `POST /raw-inbox/:id/promote-todo` → inserts a row into the existing `todos` table (per the contract from [`jakeos-todos-module`](../archive/2026-05-01-jakeos-todos-module/design.md)) with `text` carried over and `source: "raw-inbox"`, then transitions the inbox row to `promoted-todo`.
  - `POST /raw-inbox/:id/promote-wiki` → appends `- [ ] <text>` to `wiki/todos.md` (creates it with a one-line frontmatter stub if missing — see design.md decision 6), then transitions to `promoted-wiki`.
  - `POST /raw-inbox/:id/dismiss` → transitions to `dismissed` with no further action.
- **Audit-log writes** on every state transition per [`data-contract/spec.md`](../../specs/data-contract/spec.md) "Audit trail for all writes": `entity_type=raw_inbox`, `action=promote-todo|promote-wiki|dismiss|retire|first-seen`, prior + new state captured.
- **No mutation of `raw/`** — the scanner reads files only. Strict invariant: under no circumstance does this module open a file in `raw/` for write.

### Web — jakeos-web

- **Inbox region** added to the top of the existing todos card in [`src/sections.js`](../../../jakeos-web/src/sections.js)'s `renderTodos`, above the active todos list. Each open inbox entry renders: text, source-file path (last segment + tooltip with full path), nearest header (or `(no heading)` when none), and three buttons: **Promote**, **Wiki**, **Dismiss**.
- **Server routes** in [`src/server.js`](../../../jakeos-web/src/server.js) for the three process verbs, each calling the corresponding sidecar endpoint and re-rendering the todos card body so HTMX swaps the section atomically.
- **Empty state** when no open entries: the inbox region collapses entirely (the active-todos UX is unchanged).
- **Offline behavior**: identical to the rest of the dashboard — a stale-cached inbox renders read-only with the existing offline banner; write controls disable.

### Spec deltas

- `dashboard/spec.md` — modify `Sectioned layout` and `Todo round-trip visibility` requirements to reference the new inbox region; ADD a new requirement `Raw inbox surface in todos card` capturing the contract.
- `data-contract/spec.md` — modify `API surface` to include the new `raw-inbox` reads and writes; ADD a new requirement `Raw inbox is mirrored, never authoritative` that codifies the read-only-source rule and points at AGENTS.md.
- `ingest/spec.md` — ADD a new requirement `Raw-inbox scanner hooks into the trigger` so the FSEvents watcher fires the scanner on every debounced cycle.

## Capabilities

### New Capabilities

(none — this change extends three existing capabilities)

### Modified Capabilities

- `dashboard`: add the inbox region to the todos card; modify two existing requirements + add one (`Raw inbox surface in todos card`).
- `data-contract`: extend API surface; add `Raw inbox is mirrored, never authoritative`.
- `ingest`: add `Raw-inbox scanner hooks into the trigger`.

## Impact

- **Code**:
  - Sidecar (`~/Documents/Second-brain-helper-app/sidecar`):
    - `src/db/migrations/0002_raw_inbox.sql` — new
    - `src/db/migrations.rs` — append entry; `src/db/mod.rs` — bump `MAX_KNOWN_SCHEMA_VERSION`
    - `src/inbox/mod.rs`, `src/inbox/scanner.rs`, `src/inbox/identity.rs` — new
    - `src/api/raw_inbox.rs` — new (read + 3 write endpoints)
    - `src/api/mod.rs` — register the new router
    - `src/ingest/watcher.rs` — call the inbox scanner after each debounced cycle
    - `src/bin/jakeos-sidecar.rs` — spawn the 10-minute periodic poll
  - Web (`~/Documents/jakeos-web`):
    - `src/sections.js` — add `renderRawInbox` and call it from `renderTodos`
    - `src/server.js` — three new POST routes
    - `src/layout.js` — minor CSS for the inbox region
  - Wiki (`~/Documents/Obsidian Vault/Second brain/wiki/todos.md`) — created on first Promote-to-Wiki if missing; v1 stub with `type: project`-style frontmatter, then appended to.
- **APIs**: 1 new read endpoint, 3 new write endpoints. No change to existing `todos` API (Promote-to-todo writes via the existing `POST /todos` contract).
- **Dependencies**: None new on the web side. Sidecar may need `sha2` or use `blake3`'s SHA-256 mode — likely just `sha2 = "0.10"` since we already pull `blake3` for token hashing; SHA-256 is the locked algorithm per the user's spec.
- **Systems**: UnRAID stack picks up the new web image on next push. Sidecar binary rebuilds + relaunches via `launchctl kickstart` per the project memory note.
- **Tasks**: Marks task **4.8 partial credit** in `jakeos-dashboard-v1/tasks.md` once verified — this change implements the dashboard *surface* for raw-inbox-derived todos, but the broader Phase 4.6 (daily staleness sweep) and 4.8 (RAW ingest trigger fully wired to the wiki pipeline) work remains separate.
