## MODIFIED Requirements

### Requirement: API surface

The sidecar SHALL expose an HTTP API over Tailscale with at least: read endpoints for todos, ideas, recent captures, recent important emails, upcoming calendar, employment tracker, self-loop queue, audit log, raw inbox, **and ingest status**; write endpoints for todo create/complete, idea capture, capture event recording, calendar-add-from-email, email-mark-important, self-loop approve/reject/defer, manual ingest rescan, and raw-inbox process verbs (promote-todo, promote-wiki, dismiss).

The ingest-status read endpoint SHALL be `GET /ingest/status` and SHALL return the JSON shape defined in [ingest](../ingest/spec.md)'s "Surface visibility" requirement. The endpoint SHALL be a SELECT-only projection over the existing trigger audit-log table plus the watcher's in-memory manifest — no new tables, no new columns, no new pipeline logic.

#### Scenario: The dashboard requests today's data

- **WHEN** the dashboard's initial load fires
- **THEN** all required reads MUST be available via the API surface
- **AND** authentication MUST be enforced per [auth](../auth/spec.md)

#### Scenario: The dashboard processes a raw-inbox entry

- **WHEN** the dashboard sends a process-verb request to the sidecar
- **THEN** the matching write endpoint MUST be available at `POST /raw-inbox/:id/promote-todo`, `POST /raw-inbox/:id/promote-wiki`, or `POST /raw-inbox/:id/dismiss`
- **AND** authentication MUST be enforced per [auth](../auth/spec.md)

#### Scenario: The dashboard polls ingest status

- **WHEN** the dashboard's footer-chrome ingest indicator polls `GET /ingest/status`
- **THEN** the endpoint MUST return the documented JSON shape per [ingest](../ingest/spec.md)'s "Surface visibility" requirement
- **AND** the response MUST be derivable purely from the existing audit-log table plus the watcher's manifest (no new persistence)
- **AND** authentication MUST be enforced per [auth](../auth/spec.md)
