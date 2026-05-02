# dashboard — Specification

## Purpose

Defines the JakeOS dashboard — the standalone web surface at `https://jakeos.jakehallman.com` that Jake keeps open as a daily tab. The dashboard renders todos, important emails, calendar (today + condensed upcoming), employment-application status, contextual briefings, recent captures, and the self-improvement-loop review queue, plus a persistent Cowork input field for ad-hoc capture and questions. It is single-user, authenticated via Google OAuth per [auth](../auth/spec.md), and reads/writes through the Rust sidecar API per [data-contract](../data-contract/spec.md). When the sidecar is unreachable, the dashboard degrades to a read-only last-known-state view with a clear offline banner.

**Status:** Active.
**Introduced by:** `jakeos-dashboard-v1` (2026-05-01).
**Owner:** Jake Hallman.
**Surface:** Standalone web app at `https://jakeos.jakehallman.com` (subdomain hosted on UnRAID, exposed publicly via Cloudflare Tunnel).

## Requirements

### Requirement: Single-user scope

The dashboard SHALL serve exactly one user (Jake Hallman, `jake.hallman@gmail.com`). Multi-user support is out of scope.

#### Scenario: Any unauthenticated visitor

- **WHEN** a request reaches the dashboard surface without valid Jake credentials
- **THEN** the surface MUST refuse to render dashboard content and MUST NOT leak any data fetched from connected sources

#### Scenario: A second authenticated identity attempts access

- **WHEN** any identity other than Jake's authenticates against the surface
- **THEN** the surface MUST refuse the session, regardless of role or permission level
- **AND** rejection MUST be enforced per [auth](../auth/spec.md)'s single-allowed-account guard

### Requirement: Sectioned layout

The dashboard SHALL render the following sections, in this order, on its primary view: todos, important emails, calendar (today + condensed upcoming), employment, briefings, recent captures, self-loop queue, and a Cowork input field anchored at the bottom.

The todos section SHALL show open todos and recently-completed todos in the same section, with check, uncheck, and inline-add affordances per "Todo round-trip visibility" below. The todos section SHALL ALSO render a "Raw inbox" region at the top when the sidecar reports any open raw-inbox entries, per "Raw inbox surface in todos card" below.

The calendar section SHALL show today's events prominently and the next 7 days condensed, sourced from the user's primary Google Calendar via the sidecar, per "Calendar surface — today and next 7 days" below.

#### Scenario: First load on a normal day

- **WHEN** Jake opens the dashboard
- **THEN** all sections MUST be present
- **AND** sections with no relevant data MUST render an empty-state message rather than be hidden
- **AND** the todos section MUST surface its inline-add affordance even when both the open and completed-today lists are empty
- **AND** the todos section MUST render the inbox region above the active list whenever any open raw-inbox entries exist
- **AND** the calendar section MUST render its "Today" region even when today has no events

### Requirement: Calendar surface — today and next 7 days

The dashboard SHALL render two regions in the calendar section: a prominent "Today" region and a condensed "Next 7 days" region. The data SHALL come from the user's primary Google Calendar via the sidecar's `GET /calendar/upcoming` endpoint, which calls Google with the access token forwarded as `X-Google-Access-Token` from oauth2-proxy through jakeos-web.

The calendar section is read-only in v1: no event creation, editing, or deletion controls.

The "Today" region SHALL show events whose start falls within Jake's local-timezone calendar day, in event-start order, each with start time, title, and location (when present). All-day events SHALL render with an "all day" label in place of a time.

The "Next 7 days" region SHALL show events whose start falls after end-of-today-local through `now + 7 days`, grouped under day headings, in event-start order, each as a single line with time and title.

The section's empty states SHALL be:

- No events at all in the next 7 days: render a single empty-state message.
- No events today, but events later in the window: the "Today" region renders an explicit "Nothing today" empty state and the upcoming region renders normally.
- Events today, no events later in the window: the "Today" region renders normally and the "Next 7 days" region is omitted.

When Google's response indicates the OAuth grant is missing or insufficient (the sidecar reports `oauth_wired: false`), the section MUST render the same empty state with a muted "Google Calendar OAuth not wired" hint, NOT a sidecar-unreachable error.

When the sidecar itself is unreachable, the section MUST fall back to the cached calendar response per the dashboard's "Graceful degradation when sidecar unreachable" requirement.

#### Scenario: Jake opens the dashboard with a normal day ahead

- **WHEN** Jake opens the dashboard
- **AND** his primary Google Calendar has events both today and later in the next 7 days
- **THEN** the calendar section MUST render a "Today" region listing today's events with start time, title, and (where set) location, in start-time order
- **AND** the calendar section MUST render a "Next 7 days" region grouped by day, each row condensed to time + title
- **AND** at least one event from his Google Calendar MUST be visible at `https://jakeos.jakehallman.com` without the user taking any extra action

#### Scenario: A real event appears end-to-end

- **WHEN** Jake creates an event in Google Calendar today
- **AND** waits up to one polling cycle (60s) plus the sidecar's 10s cache TTL
- **THEN** the event MUST appear in the dashboard's "Today" region
- **AND** no manual reload of credentials, sessions, or services MUST be required

#### Scenario: All-day event today

- **WHEN** today contains an all-day event
- **THEN** the event MUST render in the "Today" region with an "all day" label in place of a time
- **AND** the event title MUST render as it does for timed events

#### Scenario: Nothing today but a meeting tomorrow

- **WHEN** today has no events but a meeting exists tomorrow within the 7-day window
- **THEN** the "Today" region MUST render with an explicit "Nothing today" empty state
- **AND** the "Next 7 days" region MUST render the upcoming meeting under tomorrow's date heading

#### Scenario: Meetings today but a quiet rest of the week

- **WHEN** today contains events but no events fall after end-of-today-local within the 7-day window
- **THEN** the "Today" region MUST render normally
- **AND** the "Next 7 days" region MUST be omitted

#### Scenario: OAuth scope missing or revoked

- **WHEN** the sidecar's `/calendar/upcoming` response carries `oauth_wired: false`
- **THEN** the calendar card MUST render the no-events empty state with a muted "Google Calendar OAuth not wired" hint
- **AND** the calendar card MUST NOT show a sidecar-unreachable error

#### Scenario: Sidecar unreachable

- **WHEN** the sidecar is unreachable
- **AND** a previous successful response is in the dashboard's offline cache
- **THEN** the calendar section MUST render that cached response read-only with the dashboard's offline banner active
- **AND** the section MUST behave per the existing "Graceful degradation when sidecar unreachable" requirement

### Requirement: Todo round-trip visibility

The dashboard SHALL surface recently-completed todos alongside open todos in the todos section, so the user can uncheck (reopen) a todo without leaving the dashboard. Uncheck SHALL round-trip to the sidecar per [data-contract](../data-contract/spec.md)'s "Todo bidirectional sync" requirement.

The todos section SHALL also expose an inline "add todo" affordance distinct from the Cowork input. The inline affordance creates a sidecar-native todo directly (no Cowork classifier).

The todos section SHALL also render the "Raw inbox" region above the active list per "Raw inbox surface in todos card" below. Promoting a raw-inbox entry to a sidecar todo SHALL produce a row visible in the active list within the same render cycle.

When the sidecar is unreachable, write controls (add, complete, reopen, plus the three inbox process verbs) MUST disable, consistent with the dashboard's "Graceful degradation when sidecar unreachable" requirement. Recently-completed visibility and the cached inbox region fall back to the last cached state.

#### Scenario: Jake completes a todo and immediately changes his mind

- **WHEN** Jake clicks "done" on an open todo
- **AND** the row visibly moves to a completed-today area within the same section
- **AND** Jake then clicks the uncheck affordance on that completed row
- **THEN** the todo MUST return to the open list
- **AND** both transitions MUST be reflected in the sidecar's `todos` table per [data-contract](../data-contract/spec.md)
- **AND** an audit-log entry MUST exist for each transition

#### Scenario: Jake adds a todo via the inline input

- **WHEN** Jake types into the todos card's inline input and submits
- **THEN** the new todo MUST appear in the open list within one render cycle
- **AND** the sidecar `todos` row MUST have `source = "dashboard"`
- **AND** the input MUST clear after submission

#### Scenario: Sidecar unreachable while interacting with todos

- **WHEN** the sidecar is unreachable and Jake attempts to add, complete, reopen, promote, wiki-promote, or dismiss
- **THEN** the affected control MUST appear disabled with the offline-banner reason
- **AND** the cached open + completed-today + inbox lists MUST remain visible read-only

### Requirement: Raw inbox surface in todos card

The dashboard SHALL render a "Raw inbox" region at the top of the todos card whenever the sidecar's `GET /raw-inbox?state=open` returns at least one entry. The region SHALL list each open inbox entry with: the todo text, the source file's path (last-segment label, full path on hover), the nearest preceding header chain (or `(no heading)` when the file has none), and three action buttons — **Promote**, **Wiki**, **Dismiss** — corresponding to `POST /raw-inbox/:id/promote-todo`, `POST /raw-inbox/:id/promote-wiki`, and `POST /raw-inbox/:id/dismiss` on the sidecar.

The "Raw inbox" region MUST collapse entirely when the sidecar reports zero `state=open` entries; the active-todos rendering below MUST be unchanged in that case.

The dashboard MUST NOT render any control that modifies a file in `~/Documents/Obsidian Vault/Second brain/raw/`. The three action buttons act on the sidecar's mirror entry only.

When the sidecar is unreachable, the inbox region MUST fall back to the last cached inbox response read-only with the existing offline banner active, and the three action buttons MUST appear disabled per the dashboard's "Graceful degradation when sidecar unreachable" requirement.

#### Scenario: Jake jots a todo in a daily note and refreshes the dashboard

- **WHEN** Jake adds a `- [ ] …` line to a markdown file under `~/Documents/Obsidian Vault/Second brain/raw/`
- **AND** the next dashboard poll fires after the sidecar's scanner has run
- **THEN** the todos card MUST render a "Raw inbox" region listing that entry above the active todos
- **AND** the entry's source file path and nearest header chain MUST be visible on the row

#### Scenario: Jake clicks Promote on an inbox entry

- **WHEN** Jake clicks the **Promote** button on an open inbox entry
- **THEN** the sidecar MUST insert a row into `todos` with the entry's text and `source = "raw-inbox"`
- **AND** the inbox entry's state MUST transition to `promoted-todo`
- **AND** within the same render cycle the entry MUST disappear from the inbox region
- **AND** within the same render cycle the entry MUST appear in the active-todos list

#### Scenario: Jake clicks Wiki on an inbox entry

- **WHEN** Jake clicks the **Wiki** button on an open inbox entry
- **THEN** the sidecar MUST append a `- [ ] <text>` line to `~/Documents/Obsidian Vault/Second brain/wiki/todos.md`
- **AND** the inbox entry's state MUST transition to `promoted-wiki`
- **AND** within the same render cycle the entry MUST disappear from the inbox region
- **AND** the dashboard MUST NOT render the entry in the active-todos list (it lives in the wiki page now, not the sidecar's `todos` table)

#### Scenario: Jake clicks Dismiss on an inbox entry

- **WHEN** Jake clicks the **Dismiss** button on an open inbox entry
- **THEN** the inbox entry's state MUST transition to `dismissed`
- **AND** within the same render cycle the entry MUST disappear from the inbox region
- **AND** the active-todos list MUST be unchanged

#### Scenario: Source file in raw/ remains untouched after any process verb

- **WHEN** any of Promote / Wiki / Dismiss is clicked
- **THEN** the originating file under `raw/` MUST be unchanged on disk (size, hash, mtime)
- **AND** no control on the dashboard MUST exist that would write to a file under `raw/`

#### Scenario: No open inbox entries

- **WHEN** the sidecar reports zero `state=open` entries
- **THEN** the todos card MUST NOT render an inbox region at all (no header, no rule, no empty-state copy)
- **AND** the active-todos rendering MUST be visually identical to its pre-change shape

#### Scenario: Sidecar unreachable while interacting with the inbox

- **WHEN** the sidecar is unreachable and a previous successful inbox response is in the dashboard's offline cache
- **THEN** the cached inbox region MUST render read-only with the offline banner active and `staleTag` shown
- **AND** the three action buttons MUST appear disabled with the offline-banner reason

### Requirement: Auto-update on new signal

The dashboard SHALL refresh affected sections when new data arrives from any connected source (email, calendar, todos, ingest, capture), without a full page reload. Updates arrive via WebSocket or Server-Sent Events from the sidecar.

#### Scenario: A new important email arrives while the dashboard is open

- **WHEN** the email pipeline classifies a new message as important
- **THEN** the important-emails section MUST update within the v1 latency budget defined below
- **AND** other sections MUST NOT re-render

### Requirement: Token / context budget

The dashboard SHALL meet a per-load token budget that is measured and recorded during initial implementation (Phase 6.2 of `tasks.md`). Initial loads and incremental updates each have their own budget. Once recorded, the budget becomes part of this spec.

#### Scenario: Token-budget regression

- **WHEN** a code change causes per-load tokens to exceed the recorded v1 budget by more than 20%
- **THEN** the change MUST be flagged in the orchestration drift audit per [orchestration](../orchestration/spec.md)
- **AND** the change MUST be either justified by added value or reverted

### Requirement: Cowork input

The dashboard SHALL expose a persistent input field at the bottom of the view that accepts free text and routes it to a Cowork session for handling (new todo, idea capture, or question).

#### Scenario: Jake types a sentence and presses enter

- **WHEN** the input is submitted
- **THEN** the input MUST clear
- **AND** the submitted text MUST appear (a) as a new todo if Cowork classified it as one, or (b) in an "ideas / inbox" surface otherwise
- **AND** the surface MUST never silently drop the input

### Requirement: Self-loop review surface

The dashboard SHALL surface the self-improvement loop's review queue per [self-loop](../self-loop/spec.md): pending proposal count, age of oldest pending item, approve/reject/defer controls per proposal.

#### Scenario: The queue has any pending proposals

- **WHEN** Jake opens the dashboard
- **THEN** the self-loop section MUST show queue depth and oldest-age at a glance, without requiring section expansion

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

### Requirement: Manual ingest rescan control

The dashboard SHALL expose a "Re-scan now" control wired to the sidecar's manual rescan endpoint per [ingest](../ingest/spec.md). The control SHALL be hosted inside the ingest status indicator surface defined under "Ingest status indicator" — both the collapsed indicator's `[Re-scan]` button and the drawer's re-render-on-click contract satisfy this requirement.

#### Scenario: A file landed in `raw/` via cloud sync that the watcher missed

- **WHEN** Jake clicks "Re-scan now" from the ingest status indicator
- **THEN** progress and outcome MUST surface in the drawer per the "Ingest status indicator" requirement's Re-scan scenarios
- **AND** the resulting event MUST appear in the drawer's `recent_events` list with `mechanism: manual-rescan`

### Requirement: Graceful degradation when sidecar unreachable

When the sidecar is unreachable (Mac asleep, off-network, Tailscale outage), the dashboard SHALL render last-known state read-only, with a banner indicating "last sync at <time>" and that writes are disabled until reconnection.

#### Scenario: Mac in Jake's bag during commute

- **WHEN** the dashboard cannot reach the sidecar via Tailscale
- **THEN** the dashboard MUST display the offline banner
- **AND** previously-cached content MUST remain readable
- **AND** any input controls (Cowork input, approve/reject buttons, capture rescan) MUST be disabled with a tooltip explaining the offline state

## Open implementation details

These items resolve during implementation, not at spec time:

- The exact framework for the standalone web app (SvelteKit, Astro, Next.js, etc.) — chosen at Phase 3 implementation.
- The latency budget for "auto-update on new signal" — measured during Phase 6.2 and recorded back into this spec.
- The token budget value — same.
