## ADDED Requirements

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

## MODIFIED Requirements

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
