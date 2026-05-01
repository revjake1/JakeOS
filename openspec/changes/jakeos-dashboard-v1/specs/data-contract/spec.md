# data-contract — spec delta

> The cross-surface data contract between the macOS Second Brain Helper and the JakeOS dashboard. Architecture-independent requirements only; transport details (local socket, REST, websocket, shared DB) land during `/opsx:apply` after Q1 + Q2 decisions.

## ADDED Requirements

### Requirement: Source of truth for note content

The macOS Second Brain Helper SHALL be the source of truth for note text and note metadata. The dashboard MAY cache note content but MUST NOT diverge from the Helper's state for longer than a sync cycle defined elsewhere in this spec.

#### Scenario: Helper updates a note while dashboard is offline

- **WHEN** the Helper writes a change and the dashboard later reconnects
- **THEN** the dashboard MUST adopt the Helper's version
- **AND** any local-only edits the dashboard accumulated MUST be surfaced to Jake for resolution, not silently overwritten

### Requirement: Todo bidirectional sync

Todos SHALL be readable and writable from both surfaces. Completion state changes on either surface SHALL propagate to the other.

#### Scenario: Jake completes a todo on the dashboard

- **WHEN** the dashboard marks a todo complete
- **THEN** the Helper's representation of that todo MUST reflect completion within one sync cycle
- **AND** the timestamp of completion MUST be preserved across surfaces

#### Scenario: Conflicting completion states across surfaces

- **WHEN** both surfaces have changed completion state of the same todo since the last sync
- **THEN** the resolution rule defined in this spec MUST apply (TBD pending Q2; until then: most-recent-write-wins, with both timestamps preserved in the audit log)

### Requirement: Idea / capture inbox

Free-form text captured via Cowork input or via the Helper's capture surface SHALL be stored in a single shared inbox. Items are not duplicated across surfaces.

#### Scenario: Same idea captured twice within the same sync window

- **WHEN** Jake captures the same text twice (once on each surface) before the next sync
- **THEN** both entries MUST be preserved (de-duplication is NOT automatic at v1)
- **AND** the dashboard MUST visually surface near-duplicates so Jake can manually merge

### Requirement: Audit trail for cross-surface writes

Every write that crosses the surface boundary SHALL be recorded in an append-only audit log with: timestamp, originating surface, target entity, action, and (if applicable) the prior value.

#### Scenario: Self-improvement loop modifies a config

- **WHEN** the loop writes a config change (per `self-loop/spec.md`)
- **THEN** an audit-log entry MUST exist containing the diff and the rationale
- **AND** the entry MUST be readable from the dashboard for review

## TBD pending design.md decisions

- Transport mechanism (Q2 = α/β/γ/δ)
- Sync cycle latency budget
- Conflict-resolution rule (currently provisional: most-recent-write-wins)
- Schema location and migration policy
