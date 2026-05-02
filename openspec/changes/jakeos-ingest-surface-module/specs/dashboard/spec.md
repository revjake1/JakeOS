## ADDED Requirements

### Requirement: Ingest status indicator

The dashboard SHALL render a persistent ingest status indicator in the dashboard's footer chrome on every primary view, fed by the sidecar's `GET /ingest/status` endpoint per [data-contract](../data-contract/spec.md). The collapsed indicator SHALL render a single line of the form `Ingest: <relative_time>, <N> pending [Re-scan]`, where:

- `<relative_time>` is the relative time since `last_successful_at` (e.g., "2 minutes ago", "yesterday"). When `last_successful_at` is null, the indicator SHALL render `Ingest: never run, <N> pending [Re-scan]` instead.
- `<N>` is the `pending_count` field returned by the endpoint.
- `[Re-scan]` is a button wired to the existing `POST /ingest/rescan` endpoint per [ingest](../ingest/spec.md).

The indicator SHALL color-code based on the most recent attempt's outcome:

- **Neutral** when `last_error_at` is null OR `last_error_at < last_successful_at`.
- **Amber** when `last_error_at > last_successful_at` AND the error is within the last 24 hours.
- **Red** when `last_error_at > last_successful_at` AND the error is older than 24 hours.

When the indicator is in an error state (amber or red), the indicator SHALL render `last_error_message` as a hover tooltip.

Clicking the indicator SHALL toggle a footer-anchored drawer that lists the ten most recent ingest events from the endpoint's `recent_events` array, each row showing timestamp, mechanism (`fsevents` | `manual-rescan`), outcome (`ingest-run` | `no-op` | `error`), and — for error rows — the full error message.

Clicking the `[Re-scan]` button SHALL POST to `/ingest/rescan`, disable the button while the request is in flight, and re-render the drawer body with the resulting outcome banner: `0 new` (no new files were queued), `N queued for ingest` (where N > 0), or `error: <message>`.

When the sidecar is unreachable, the indicator SHALL render the last cached `/ingest/status` response read-only with the existing offline banner active, and the `[Re-scan]` button SHALL appear disabled per the dashboard's "Graceful degradation when sidecar unreachable" requirement.

#### Scenario: Healthy steady-state load

- **WHEN** Jake opens the dashboard
- **AND** the sidecar's most recent ingest cycle was successful within the last hour
- **AND** no files are pending in `raw/`
- **THEN** the footer MUST render an ingest indicator with neutral coloring
- **AND** the indicator text MUST follow the form `Ingest: <relative_time>, 0 pending [Re-scan]`

#### Scenario: A new file lands in raw/

- **WHEN** a new file appears in `~/Documents/Obsidian Vault/Second brain/raw/` between dashboard polls
- **AND** the sidecar's watcher has registered the file but the debounced cycle has not yet fired
- **AND** the dashboard's next poll fires
- **THEN** the indicator MUST update to show `pending_count` of 1 (or higher, if more files arrived)
- **AND** within the watcher's debounce window plus one poll cycle, the indicator MUST settle back to `0 pending` once the cycle completes successfully

#### Scenario: Jake clicks the indicator

- **WHEN** Jake clicks the ingest indicator
- **THEN** a footer-anchored drawer MUST open
- **AND** the drawer MUST list up to ten of the most recent events from `/ingest/status`'s `recent_events` array, newest first
- **AND** each row MUST show timestamp, mechanism, and outcome
- **AND** any error rows MUST show the full `error_message`

#### Scenario: Jake clicks Re-scan with no new files

- **WHEN** Jake clicks the `[Re-scan]` button
- **AND** the sidecar's `POST /ingest/rescan` returns successfully with no new files queued
- **THEN** the `[Re-scan]` button MUST be disabled while the request is in flight
- **AND** the drawer MUST re-render with a "0 new" outcome banner
- **AND** the just-fired event MUST appear at the top of the drawer's event list with `mechanism: manual-rescan` and `outcome: no-op`

#### Scenario: A recent ingest cycle errored

- **WHEN** the sidecar's most recent ingest attempt errored
- **AND** the error is less than 24 hours old
- **THEN** the indicator MUST render with amber coloring
- **AND** hovering the indicator MUST show the error message as a tooltip
- **AND** opening the drawer MUST show the error row at the top with the full message visible

#### Scenario: Ingest has been broken for more than a day

- **WHEN** `last_error_at` is more than 24 hours after `last_successful_at`
- **AND** the most recent attempt was an error
- **THEN** the indicator MUST render with red coloring
- **AND** opening the drawer MUST show the persistent error pattern across multiple recent events

#### Scenario: Sidecar unreachable

- **WHEN** the sidecar is unreachable
- **AND** a previous successful `/ingest/status` response is in the dashboard's offline cache
- **THEN** the indicator MUST render the cached state read-only
- **AND** the offline banner MUST be active
- **AND** the `[Re-scan]` button MUST be disabled with the offline-banner reason

#### Scenario: Fresh install, never run

- **WHEN** the sidecar's audit log contains no successful ingest events
- **THEN** the indicator MUST render `Ingest: never run, <N> pending [Re-scan]` where `<N>` is the watcher's manifest count
- **AND** clicking `[Re-scan]` MUST be the recommended action (the button is enabled and prominently styled in this state)

## MODIFIED Requirements

### Requirement: Manual ingest rescan control

The dashboard SHALL expose a "Re-scan now" control wired to the sidecar's manual rescan endpoint per [ingest](../ingest/spec.md). The control SHALL be hosted inside the ingest status indicator surface defined under "Ingest status indicator" — both the collapsed indicator's `[Re-scan]` button and the drawer's re-render-on-click contract satisfy this requirement.

#### Scenario: A file landed in `raw/` via cloud sync that the watcher missed

- **WHEN** Jake clicks "Re-scan now" from the ingest status indicator
- **THEN** progress and outcome MUST surface in the drawer per the "Ingest status indicator" requirement's Re-scan scenarios
- **AND** the resulting event MUST appear in the drawer's `recent_events` list with `mechanism: manual-rescan`
