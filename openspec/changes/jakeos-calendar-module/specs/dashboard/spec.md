## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Sectioned layout

The dashboard SHALL render the following sections, in this order, on its primary view: todos, important emails, calendar (today + condensed upcoming), employment, briefings, recent captures, self-loop queue, and a Cowork input field anchored at the bottom.

The todos section SHALL show open todos and recently-completed todos in the same section, with check, uncheck, and inline-add affordances per "Todo round-trip visibility" above.

The calendar section SHALL show today's events prominently and the next 7 days condensed, sourced from the user's primary Google Calendar via the sidecar, per "Calendar surface — today and next 7 days" above.

#### Scenario: First load on a normal day

- **WHEN** Jake opens the dashboard
- **THEN** all sections MUST be present
- **AND** sections with no relevant data MUST render an empty-state message rather than be hidden
- **AND** the todos section MUST surface its inline-add affordance even when both the open and completed-today lists are empty
- **AND** the calendar section MUST render its "Today" region even when today has no events
