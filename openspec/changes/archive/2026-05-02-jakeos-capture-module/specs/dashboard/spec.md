## MODIFIED Requirements

### Requirement: Recent captures surface

The dashboard SHALL surface a recent-captures view per [capture](../capture/spec.md), showing the last N items (default 8) with timestamp, filename, mime type, file size (when known), and a link to the companion `.md` in the wiki (when present). Each row's data SHALL come from the sidecar's `GET /captures?limit=N` endpoint per [data-contract](../data-contract/spec.md).

When a capture's metadata fields (`mime_type`, `size_bytes`, `companion_path`) are absent — for example, on legacy rows seeded before this change — the row MUST render gracefully with the available fields and omit the missing ones.

When the sidecar reports a capture as a duplicate (per the `is_duplicate: true` response from `POST /captures`), the dashboard MUST NOT render a second row; the existing row's `created_at` MAY be refreshed to the most recent drop time so the entry remains discoverable.

#### Scenario: Jake just dropped three files

- **WHEN** the dashboard refreshes
- **THEN** those captures MUST appear in the recent-captures view within one sync cycle
- **AND** each entry MUST link to its companion note in the wiki when `companion_path` is present
- **AND** each entry MUST show timestamp, filename, mime type, and file size when those fields are populated

#### Scenario: A capture from before this change is still in the table

- **WHEN** the dashboard renders a row whose `mime_type` / `size_bytes` / `companion_path` are null
- **THEN** the row MUST still render with the available fields (filename, original_kind, created_at)
- **AND** no error MUST surface for the missing fields

#### Scenario: Duplicate drop already in the captures list

- **WHEN** Jake drops a file whose `sha256` matches an existing capture
- **AND** the sidecar responds with `is_duplicate: true` referencing the existing row
- **THEN** the dashboard's "Recent captures" list MUST NOT gain a new row
- **AND** the existing row MAY have its `created_at` updated to surface the duplicate-drop in the recent view
