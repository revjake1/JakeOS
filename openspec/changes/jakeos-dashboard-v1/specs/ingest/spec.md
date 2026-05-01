# ingest — spec delta

> The RAW-folder watcher contract. The trigger mechanism (FSEvents / server cron / Cowork schedule) lands during `/opsx:apply` after design.md Q5.

## ADDED Requirements

### Requirement: Defer to wiki ingest rules

Ingest cycles SHALL follow the rules defined in `~/Documents/Obsidian Vault/Second brain/AGENTS.md`. JakeOS does NOT define its own ingest semantics — it triggers the existing pipeline.

#### Scenario: AGENTS.md changes its ingest rules

- **WHEN** the wiki's `AGENTS.md` is updated
- **THEN** the next ingest cycle MUST honor the new rules without requiring a JakeOS code change
- **AND** the trigger MUST NOT cache rule contents across cycles

### Requirement: Idempotent triggers

A trigger SHALL be safe to fire repeatedly. Two consecutive triggers with no new RAW content MUST NOT produce duplicate ingest work.

#### Scenario: The trigger fires twice within a minute on an unchanged RAW folder

- **WHEN** two trigger events arrive for the same RAW state
- **THEN** the second trigger MUST be a no-op
- **AND** an audit-log entry MUST record the no-op

### Requirement: Trigger audit log

Every trigger fire SHALL be recorded with: timestamp, originating mechanism (FSEvents / cron / Cowork), the RAW manifest hash at fire time, and the outcome (ingest-run / no-op / error).

#### Scenario: An ingest run errors mid-cycle

- **WHEN** the wiki ingest pipeline returns a non-zero status
- **THEN** the audit-log entry MUST capture the error
- **AND** the dashboard MUST surface a notification rather than silently retry

### Requirement: Surface visibility

The dashboard SHALL show the time of the most recent successful ingest cycle and the count of pending RAW files awaiting the next cycle.

#### Scenario: Jake opens the dashboard the morning after a failed ingest

- **WHEN** the most recent ingest attempt errored
- **THEN** the dashboard MUST display a "last ingest: failed at <time>" indicator
- **AND** clicking it MUST reveal the audit-log entry

### Requirement: FSEvents-based watcher in the Rust sidecar

The trigger mechanism SHALL be a macOS FSEvents watcher hosted inside the Rust sidecar process. The watcher SHALL subscribe to changes in `~/Documents/Obsidian Vault/Second brain/raw/` and SHALL fire on file creation, modification, and rename within that directory.

#### Scenario: A new .md companion lands in raw/

- **WHEN** a new file appears in `raw/`
- **THEN** an FSEvents callback MUST fire within macOS's normal latency
- **AND** the watcher MUST add the file to the pending-trigger queue
- **AND** the watcher MUST NOT process the file until the debounce window has elapsed (see below)

### Requirement: Debounce window

The watcher SHALL apply a debounce of 1.5 seconds before treating a file as ready for ingest. This avoids firing on partial writes (the capture pipeline writes atomically, but third-party sync clients may not).

#### Scenario: A 50MB PDF is being copied into raw/

- **WHEN** FSEvents fires multiple times during the copy
- **THEN** the watcher MUST coalesce the events
- **AND** ingest MUST NOT begin until 1.5 seconds have passed with no further activity on that file

### Requirement: Resume on wake

The watcher SHALL persist a checkpoint (the FSEvents event ID of the last processed event) and on sidecar startup SHALL resume from that checkpoint, processing any events that occurred while the sidecar was not running.

#### Scenario: The Mac sleeps overnight; files appear via cloud sync

- **WHEN** the Mac wakes and the sidecar starts
- **THEN** the watcher MUST query FSEvents for events since the last checkpoint
- **AND** any new files in `raw/` MUST be processed in arrival order
- **AND** an audit-log entry MUST record "resumed-from-checkpoint" with the time gap

### Requirement: Manual rescan endpoint

The sidecar SHALL expose a `POST /ingest/rescan` endpoint that triggers a full directory walk of `raw/`, comparing each file's hash to the watcher's last-seen state. The dashboard SHALL surface a "Re-scan now" control wired to this endpoint.

#### Scenario: A file appeared in raw/ via a sync client the watcher missed

- **WHEN** Jake clicks "Re-scan now"
- **THEN** the sidecar MUST walk `raw/` and queue any new or modified files
- **AND** the dashboard MUST show progress + outcome
- **AND** the rescan MUST be safe to run while a normal watcher cycle is also active (no double-processing)

### Requirement: Manifest format

The watcher SHALL maintain an internal manifest of `raw/` content, keyed by path, holding `{ size, mtime, content_hash }`. Trigger decisions are based on hash diff, not mtime alone (mtime updates from sync clients are unreliable).

#### Scenario: A sync client touches a file but doesn't change its content

- **WHEN** the watcher sees a modify event for a file whose hash is unchanged
- **THEN** the trigger MUST be a no-op
- **AND** an audit-log entry MUST record "touched-but-unchanged"

## Locked decisions (from design.md)

- Q5 = ① (FSEvents on Mac, in the Rust sidecar). All requirements above implement this choice.
