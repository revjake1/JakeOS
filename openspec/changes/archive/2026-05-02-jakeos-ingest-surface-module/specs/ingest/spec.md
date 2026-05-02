## MODIFIED Requirements

### Requirement: Surface visibility

The dashboard SHALL show the time of the most recent successful ingest cycle and the count of pending RAW files awaiting the next cycle, sourced from the sidecar's `GET /ingest/status` read endpoint. The endpoint SHALL be a SELECT-only projection over the existing trigger audit-log table plus the watcher's in-memory manifest, and SHALL return JSON with the following shape:

```
{
  "last_successful_at": <ISO-8601 timestamp | null>,
  "last_error_at": <ISO-8601 timestamp | null>,
  "last_error_message": <string | null>,
  "pending_count": <integer >= 0>,
  "recent_events": [
    {
      "at": <ISO-8601 timestamp>,
      "mechanism": "fsevents" | "manual-rescan",
      "outcome": "ingest-run" | "no-op" | "error",
      "trigger_files": [<relative path>, ...],
      "manifest_hash": <string>,
      "error_message": <string | null>
    },
    ...
  ]
}
```

`recent_events` SHALL contain up to the ten most recent audit-log entries in `at` desc order. `pending_count` SHALL be derived from the watcher's manifest as the count of files whose hash differs from the most-recent successful ingest's manifest, plus any files in the watcher's debounce window that have not yet fired. The endpoint shape is the v1 contract; future fields SHALL be additive only.

The dashboard SHALL render this data via a persistent ingest status indicator per [dashboard](../dashboard/spec.md)'s "Ingest status indicator" requirement, including coloring on the most recent attempt's outcome and a drawer that exposes the audit-log entries for inspection.

#### Scenario: Jake opens the dashboard the morning after a failed ingest

- **WHEN** the most recent ingest attempt errored
- **THEN** the dashboard MUST display a "last ingest: failed at <time>" indicator (amber when within 24 hours, red beyond) per [dashboard](../dashboard/spec.md)'s "Ingest status indicator"
- **AND** clicking it MUST reveal the audit-log entry containing the originating mechanism, the manifest hash at fire time, the trigger files, and the error message

#### Scenario: The status endpoint is queried while a debounce window is open

- **WHEN** files have arrived in `raw/` but the FSEvents debounce window has not yet elapsed
- **AND** the dashboard polls `GET /ingest/status`
- **THEN** the response's `pending_count` MUST be greater than zero
- **AND** the response's `recent_events` MUST NOT yet contain a row for the in-flight batch
- **AND** once the debounce elapses and the cycle fires, a subsequent poll MUST show `pending_count = 0` and the new event at the top of `recent_events`

#### Scenario: The status endpoint is queried on a fresh sidecar with no audit log

- **WHEN** the sidecar has never recorded an ingest event (fresh install)
- **AND** the dashboard polls `GET /ingest/status`
- **THEN** `last_successful_at` MUST be null
- **AND** `last_error_at` MUST be null
- **AND** `recent_events` MUST be an empty array
- **AND** `pending_count` MUST reflect the watcher's manifest (zero or more, depending on what files exist in `raw/`)
