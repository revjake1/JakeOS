## MODIFIED Requirements

### Requirement: API surface

The sidecar SHALL expose an HTTP API over Tailscale with at least: read endpoints for todos, ideas, recent captures, recent important emails, upcoming calendar, employment tracker, self-loop queue, audit log, raw inbox, and ingest status; write endpoints for todo create/complete, idea capture, **capture event recording (with metadata + duplicate detection)**, calendar-add-from-email, email-mark-important, self-loop approve/reject/defer, manual ingest rescan, and raw-inbox process verbs (promote-todo, promote-wiki, dismiss).

The capture-event-recording write endpoint SHALL be `POST /captures` and SHALL accept the following JSON body:

```
{
  "raw_path":        <string, required>,
  "original_kind":   <string, required>,
  "source":          <string, optional, default "helper-app">,
  "filename":        <string, optional>,
  "mime_type":       <string, optional>,
  "size_bytes":      <integer, optional>,
  "sha256":          <string, optional, hex>,
  "companion_path":  <string, optional>,
  "captured_at":     <RFC 3339 timestamp, optional, defaults to server now()>
}
```

The endpoint SHALL respond with the persisted capture row plus an `is_duplicate: bool` flag. When `sha256` is present in the request AND a row with that hash already exists in the `captures` table, the handler MUST NOT insert a new row — it MUST return `is_duplicate: true` referencing the existing capture and MUST record an audit-log entry with `action: "duplicate-skipped"`.

The `GET /captures?limit=N` endpoint's response SHALL include the additional metadata fields when populated; legacy rows with null metadata MUST still serialize cleanly.

The ingest-status read endpoint SHALL be `GET /ingest/status` and SHALL return the JSON shape defined in [ingest](../ingest/spec.md)'s "Surface visibility" requirement.

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

#### Scenario: The Helper.app records a successful capture

- **WHEN** the Helper.app POSTs to `/captures` with a fully-populated body (including `sha256`)
- **THEN** the sidecar MUST insert a row into the `captures` table with all the populated fields
- **AND** an `audit_log` entry MUST be written with `entity_type: "capture"`, `action: "create"`, and the new row's metadata in the `new_value` field
- **AND** the response MUST carry `is_duplicate: false`
- **AND** authentication MUST be enforced per [auth](../auth/spec.md)

#### Scenario: A duplicate capture is registered

- **WHEN** the Helper.app POSTs to `/captures` with a `sha256` matching an existing `captures` row
- **THEN** the sidecar MUST NOT insert a new row
- **AND** the response MUST reference the existing capture's id with `is_duplicate: true`
- **AND** an `audit_log` entry MUST be written with `action: "duplicate-skipped"` and the new request's metadata in the `new_value` field for traceability
