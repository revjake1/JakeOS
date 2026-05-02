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

The todos section SHALL show open todos and recently-completed todos in the same section, with check, uncheck, and inline-add affordances per "Todo round-trip visibility" below.

The calendar section SHALL show today's events prominently and the next 7 days condensed, sourced from the user's primary Google Calendar via the sidecar, per "Calendar surface — today and next 7 days" below.

#### Scenario: First load on a normal day

- **WHEN** Jake opens the dashboard
- **THEN** all sections MUST be present
- **AND** sections with no relevant data MUST render an empty-state message rather than be hidden
- **AND** the todos section MUST surface its inline-add affordance even when both the open and completed-today lists are empty
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

When the sidecar is unreachable, write controls (add, complete, reopen) MUST disable, consistent with the dashboard's "Graceful degradation when sidecar unreachable" requirement. Recently-completed visibility falls back to the last cached state.

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

- **WHEN** the sidecar is unreachable and Jake attempts to add, complete, or reopen a todo
- **THEN** the affected control MUST appear disabled with the offline-banner reason
- **AND** the cached open + completed-today list MUST remain visible read-only

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

The dashboard SHALL surface a recent-captures view per [capture](../capture/spec.md), showing the last N items with links to companion notes in the wiki.

#### Scenario: Jake just dropped three files

- **WHEN** the dashboard refreshes
- **THEN** those captures MUST appear in the recent-captures view within one sync cycle

### Requirement: Manual ingest rescan control

The dashboard SHALL expose a "Re-scan now" control wired to the sidecar's manual rescan endpoint per [ingest](../ingest/spec.md).

#### Scenario: A file landed in `raw/` via cloud sync that the watcher missed

- **WHEN** Jake clicks "Re-scan now"
- **THEN** progress and outcome MUST surface in the dashboard

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
