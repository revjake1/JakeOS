# dashboard — spec delta

> Architecture-independent requirements only. Architecture-dependent details (route shape, framework, deploy unit) land during `/opsx:apply` once `design.md` Q1 is decided.

## ADDED Requirements

### Requirement: Single-user scope

The dashboard SHALL serve exactly one user (Jake Hallman, `jake.hallman@gmail.com`). Multi-user support is out of scope for v1.

#### Scenario: Any unauthenticated visitor

- **WHEN** a request reaches the dashboard surface without valid Jake credentials
- **THEN** the surface MUST refuse to render dashboard content and MUST NOT leak any data fetched from connected sources

#### Scenario: A second authenticated identity attempts access

- **WHEN** any identity other than Jake's authenticates against the surface
- **THEN** the surface MUST refuse the session, regardless of role or permission level

### Requirement: Sectioned layout

The dashboard SHALL render the following sections, in this order, on its primary view: todos, important emails, calendar (today + condensed upcoming), employment, briefings, and a Cowork input field anchored at the bottom.

#### Scenario: First load on a normal day

- **WHEN** Jake opens the dashboard
- **THEN** all six sections MUST be present
- **AND** sections with no relevant data MUST render an empty-state message rather than be hidden

### Requirement: Auto-update on new signal

The dashboard SHALL refresh affected sections when new data arrives from any connected source (email, calendar, todos, ingest), without a full page reload.

#### Scenario: A new important email arrives while the dashboard is open

- **WHEN** the email pipeline classifies a new message as important
- **THEN** the important-emails section MUST update within the v1 latency budget defined in this spec's "Performance" section below
- **AND** other sections MUST NOT re-render

### Requirement: Token / context budget

The dashboard SHALL meet a per-load token budget defined and recorded during Phase 6.2 of `tasks.md`. Initial loads and incremental updates each have their own budget.

#### Scenario: Token-budget regression

- **WHEN** a code change causes per-load tokens to exceed the recorded v1 budget by more than 20%
- **THEN** the change MUST be flagged and either justified by added value or reverted

### Requirement: Cowork input

The dashboard SHALL expose a persistent input field at the bottom of the view that accepts free text and routes it to a Cowork session for handling (new todo, idea capture, or question).

#### Scenario: Jake types a sentence and presses enter

- **WHEN** the input is submitted
- **THEN** the input MUST clear
- **AND** the submitted text MUST appear (a) as a new todo if Cowork classified it as one, or (b) in an "ideas / inbox" surface otherwise
- **AND** the surface MUST never silently drop the input

## TBD pending design.md decisions

The following requirements depend on design.md Q1 (surface architecture) and Q3 (auth model). They will be added in this delta during `/opsx:apply`:

- ~~The surface platform requirement (web at `/jakeos`, native macOS, or both)~~ → Resolved: standalone web app at `https://jakeos.jakehallman.com`.
- The deploy/update mechanism
- The auth surface contract (this spec will reference `auth/spec.md`)
- The latency budget for "auto-update on new signal" (depends on backend choice from Q2)
