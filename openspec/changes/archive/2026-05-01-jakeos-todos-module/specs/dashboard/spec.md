## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Sectioned layout

The dashboard SHALL render the following sections, in this order, on its primary view: todos, important emails, calendar (today + condensed upcoming), employment, briefings, recent captures, self-loop queue, and a Cowork input field anchored at the bottom.

The todos section SHALL show open todos and recently-completed todos in the same section, with check, uncheck, and inline-add affordances per "Todo round-trip visibility" above.

#### Scenario: First load on a normal day

- **WHEN** Jake opens the dashboard
- **THEN** all sections MUST be present
- **AND** sections with no relevant data MUST render an empty-state message rather than be hidden
- **AND** the todos section MUST surface its inline-add affordance even when both the open and completed-today lists are empty
