## ADDED Requirements

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

## MODIFIED Requirements

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
