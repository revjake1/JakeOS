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

#### Scenario: First load on a normal day

- **WHEN** Jake opens the dashboard
- **THEN** all sections MUST be present
- **AND** sections with no relevant data MUST render an empty-state message rather than be hidden
- **AND** the todos section MUST surface its inline-add affordance even when both the open and completed-today lists are empty

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
