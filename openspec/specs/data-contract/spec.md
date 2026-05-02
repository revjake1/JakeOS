# data-contract — Specification

## Purpose

Defines the cross-surface data contract between the macOS Helper.app, the Rust sidecar, and the JakeOS dashboard. Establishes the sidecar as the single source of truth for JakeOS data (todos, ideas, audit log, self-loop queue, capture metadata, cached email/calendar state) and establishes the wiki at `~/Documents/Obsidian Vault/Second brain/` as the source of truth for note text. Specifies how writes propagate, how conflicts resolve (most-recent-wins with audit-log preservation), what the API surface must expose, and how schema migrations are handled. The transport is the sidecar's HTTP API, reached by the dashboard over Tailscale.

**Status:** Active.
**Introduced by:** `jakeos-dashboard-v1` (2026-05-01).
**Owner:** Jake Hallman.
**Transport:** HTTP API hosted by the Rust sidecar at `~/Documents/Second-brain-helper-app/sidecar/`, reached by the dashboard over Tailscale.

## Requirements

### Requirement: Sidecar is the source of truth

The Rust sidecar SHALL be the single source of truth for JakeOS data: todos, ideas, audit log, self-loop queue, capture metadata, and any cached email/calendar state. The dashboard MAY cache data for offline rendering but MUST defer to the sidecar on conflict.

#### Scenario: Dashboard cache and sidecar disagree

- **WHEN** the dashboard reconnects after offline operation
- **THEN** the sidecar's state MUST be authoritative
- **AND** any local-only edits the dashboard accumulated while offline MUST be surfaced to Jake for resolution, not silently overwritten

### Requirement: Wiki is the source of truth for note text

The wiki at `~/Documents/Obsidian Vault/Second brain/` (governed by `AGENTS.md`) SHALL be the source of truth for note text and note metadata. The sidecar MUST NOT duplicate wiki content; it indexes and references the wiki, but the wiki files are canonical.

#### Scenario: A wiki page is edited in Obsidian

- **WHEN** Jake edits a wiki page directly
- **THEN** the sidecar's index MUST update via the FSEvents watcher per [ingest](../ingest/spec.md)
- **AND** the sidecar MUST NOT modify wiki files except through the ingest pipeline's defined writes

### Requirement: Todo bidirectional sync

Todos SHALL be readable and writable from the dashboard. Completion state changes SHALL be persisted to the sidecar's store immediately and propagate to any other surface within one sync cycle.

#### Scenario: Jake completes a todo on the dashboard

- **WHEN** the dashboard marks a todo complete
- **THEN** the sidecar's store MUST reflect completion
- **AND** the timestamp of completion MUST be preserved
- **AND** an audit-log entry MUST be written

### Requirement: Conflict resolution rule

Where two writes target the same entity, the most recent timestamped write SHALL win. Both versions MUST be preserved in the audit log so any unintended overwrite is recoverable.

#### Scenario: Two writes arrive within milliseconds

- **WHEN** the sidecar receives two writes for the same todo with timestamps `T` and `T+5ms`
- **THEN** the `T+5ms` write MUST be the final state
- **AND** the audit log MUST record both writes with their timestamps
- **AND** Jake MAY review the prior value in the audit log

### Requirement: Idea / capture inbox

Free-form text captured via Cowork input or via the Helper.app's drop target SHALL flow into a single shared inbox in the sidecar. Items are not duplicated across paths.

#### Scenario: Same text captured via Cowork and via drag-drop within the same session

- **WHEN** Jake captures the same content twice through different paths
- **THEN** both entries MUST be preserved (no automatic de-duplication in v1)
- **AND** the dashboard MUST visually surface near-duplicates so Jake can manually merge

### Requirement: Audit trail for all writes

Every write to sidecar-owned state SHALL be recorded in an append-only audit log with: timestamp, originating surface (dashboard / Helper.app / sidecar-internal / self-loop), target entity, action, and (where applicable) the prior value.

#### Scenario: Self-loop applies an approved proposal

- **WHEN** the loop writes a config change after Jake approves
- **THEN** an audit-log entry MUST exist containing the diff, the rationale, and the approval timestamp
- **AND** the entry MUST be readable from the dashboard

### Requirement: API surface

The sidecar SHALL expose an HTTP API over Tailscale with at least: read endpoints for todos, ideas, recent captures, recent important emails, upcoming calendar, employment tracker, self-loop queue, audit log, and **raw inbox**; write endpoints for todo create/complete, idea capture, capture event recording, calendar-add-from-email, email-mark-important, self-loop approve/reject/defer, manual ingest rescan, and **raw-inbox process verbs (promote-todo, promote-wiki, dismiss)**.

#### Scenario: The dashboard requests today's data

- **WHEN** the dashboard's initial load fires
- **THEN** all required reads MUST be available via the API surface
- **AND** authentication MUST be enforced per [auth](../auth/spec.md)

#### Scenario: The dashboard processes a raw-inbox entry

- **WHEN** the dashboard sends a process-verb request to the sidecar
- **THEN** the matching write endpoint MUST be available at `POST /raw-inbox/:id/promote-todo`, `POST /raw-inbox/:id/promote-wiki`, or `POST /raw-inbox/:id/dismiss`
- **AND** authentication MUST be enforced per [auth](../auth/spec.md)

### Requirement: Raw inbox is mirrored, never authoritative

The sidecar SHALL maintain a `raw_inbox` table that mirrors task lines (`- [ ]` / `- [x]`) detected in `~/Documents/Obsidian Vault/Second brain/raw/**/*.md`. The mirror is sidecar-owned and authoritative for inbox state (open / promoted-todo / promoted-wiki / dismissed / retired), but the underlying markdown lines in `raw/` SHALL remain the source-of-record for the *content* of the todo and SHALL NEVER be modified by JakeOS.

This requirement codifies the rule from `~/Documents/Obsidian Vault/Second brain/AGENTS.md`: "Never modify or delete an existing source file in `raw/`."

Each inbox entry SHALL be uniquely identified by `sha256(normalize(file_path) || "\n" || normalize(header_chain) || "\n" || normalize(todo_text))`, where:

- `file_path` is the entry's source markdown file relative to the vault root, lowercase, forward-slash separators, NFC-normalized.
- `header_chain` is the ATX header chain preceding the line, joined by `|`, each header lowercased and trimmed.
- `todo_text` is the line minus the `- [ ]` / `- [x]` prefix, lowercased, internal whitespace collapsed to a single space, surrounding whitespace trimmed.

This identity scheme SHALL be stable across check/uncheck flips and across surrounding-text edits in the source file. Edits to the todo text itself SHALL produce a new fingerprint; the old fingerprint's entry SHALL transition to `retired` on the next scan.

The dashboard SHALL render only entries with `state = open`. The three "process" verbs (`promote-todo`, `promote-wiki`, `dismiss`) SHALL transition entries to terminal states without modifying any file under `raw/`.

#### Scenario: A daily note in raw/ adds a `- [ ]` line

- **WHEN** a markdown file under `raw/` gains a line matching `- [ ] …` or `- [x] …`
- **AND** the inbox scanner runs on the next FSEvents debounce or 10-minute poll
- **THEN** a row MUST exist in `raw_inbox` with the locked fingerprint as primary key
- **AND** an audit-log entry with `entity_type=raw_inbox, action=first-seen` MUST be written
- **AND** the source file's bytes MUST be unchanged

#### Scenario: The same line is checked, edited around, then unchecked

- **WHEN** Jake checks the source line, adds a new paragraph above it, then unchecks it
- **AND** the inbox scanner runs after each change
- **THEN** the inbox row's primary key MUST remain the same across all three scans
- **AND** the row's state MUST remain `open` (no spurious transition)
- **AND** the source file MUST be modified only by the user, never by JakeOS

#### Scenario: The todo text is edited

- **WHEN** Jake edits the source line's todo text
- **AND** the inbox scanner runs
- **THEN** the old fingerprint's row MUST transition to `retired`
- **AND** a new row with the new fingerprint MUST be inserted in `state=open`
- **AND** both transitions MUST be recorded in the audit log

#### Scenario: A process verb fires

- **WHEN** the sidecar receives a request to promote-todo, promote-wiki, or dismiss an inbox row
- **THEN** the row's state MUST transition accordingly with timestamp and `state_change_source` recorded
- **AND** an audit-log entry MUST be written with prior state, new state, and originating surface
- **AND** the source file in `raw/` MUST be unchanged on disk
- **AND** for `promote-todo`, a new row MUST be inserted into the existing `todos` table with the entry's text and `source = "raw-inbox"`
- **AND** for `promote-wiki`, the line `- [ ] <text>` MUST be appended to `wiki/todos.md` (creating the file with the canonical frontmatter stub if absent)

### Requirement: Schema migrations are explicit

Schema changes to the sidecar's store SHALL be applied via numbered, idempotent migrations. The sidecar MUST refuse to start if its on-disk schema version is ahead of the binary's known schema version.

#### Scenario: A development binary boots against a production-version store

- **WHEN** the binary's max-known-version is lower than the on-disk schema version
- **THEN** the sidecar MUST refuse to boot
- **AND** MUST log the version mismatch clearly

## Open implementation details

- Concrete schema (table list, columns) — defined during Phase 2 implementation.
- API endpoint paths and JSON shapes — defined during Phase 2.2.
- The sidecar's storage backend (SQLite vs. filesystem-backed) — chosen during Phase 2.1; recorded back into this spec.
- Sync-cycle latency budget — measured during Phase 6.2.
