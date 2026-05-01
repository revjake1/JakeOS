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

The sidecar SHALL expose an HTTP API over Tailscale with at least: read endpoints for todos, ideas, recent captures, recent important emails, upcoming calendar, employment tracker, self-loop queue, and audit log; write endpoints for todo create/complete, idea capture, capture event recording, calendar-add-from-email, email-mark-important, self-loop approve/reject/defer, and manual ingest rescan.

#### Scenario: The dashboard requests today's data

- **WHEN** the dashboard's initial load fires
- **THEN** all required reads MUST be available via the API surface
- **AND** authentication MUST be enforced per [auth](../auth/spec.md)

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
