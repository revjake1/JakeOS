# self-loop — Specification

## Purpose

Defines the daily self-improvement loop that lets JakeOS evolve over time. The loop runs once per day, examines the prior day's activity and lessons, and generates *proposals* for changes to JakeOS configuration and skill files. The loop never auto-applies — Jake is the human in the loop, reviewing each proposal via the dashboard's approval UI. The spec covers bounded write scope (only specified allowlisted paths), the diff-and-approve approval flow, mandatory audit trail and reversibility (30-day rollback), and graceful behavior when Jake misses a review day: queue-depth visibility, automatic coalescing of overlapping proposals, stale-proposal re-evaluation against current state, and full generation pause after 14 consecutive days without review activity. The loop is forbidden from modifying itself, the orchestrator, the safety boundary, the audit-log writer, or the snapshot mechanism.

**Status:** Active.
**Introduced by:** `jakeos-dashboard-v1` (2026-05-01).
**Owner:** Jake Hallman.
**Safety boundary:** Diff-and-approve (Q4 = Ⅰ). Nothing applies without explicit human approval.

## Requirements

### Requirement: Bounded write scope

The loop SHALL only write to a defined allowlist of paths: skill files under `~/.claude/skills/` and JakeOS config files in this repo (`~/Documents/jakeos/`). Writes outside the allowlist MUST be rejected by the loop's runner before any change is applied.

#### Scenario: The loop attempts to modify a child repo

- **WHEN** the loop's plan includes a write to `~/Documents/Second-brain-helper-app/` or `~/Documents/New_Jakehallman_site/`
- **THEN** the runner MUST reject the plan
- **AND** MUST surface the rejected plan to Jake for manual handling

### Requirement: Diff-and-approve safety boundary

The loop SHALL NOT apply any change without explicit human approval. Each loop run produces a set of *proposals*; proposals enter a review queue; nothing in the queue applies until Jake clicks approve.

#### Scenario: A loop run completes with three proposed changes

- **WHEN** the run finishes
- **THEN** the three proposals MUST land in the review queue
- **AND** the underlying files MUST remain unchanged
- **AND** Jake MUST be notified of the new queue depth via the dashboard per [dashboard](../dashboard/spec.md)

### Requirement: Approval UI on the dashboard

The dashboard SHALL surface a "Self-loop review" view showing each pending proposal with: a human-readable summary, the full diff, the rationale, the affected file paths, and approve / reject / defer controls.

#### Scenario: Jake approves a proposal

- **WHEN** Jake clicks approve
- **THEN** a snapshot of affected files MUST be created BEFORE the write
- **AND** the change MUST be applied to the target files
- **AND** the proposal MUST move from "pending" to "applied" with the timestamp recorded
- **AND** an audit-log entry per [data-contract](../data-contract/spec.md) MUST be written

#### Scenario: Jake rejects a proposal

- **WHEN** Jake clicks reject and (optionally) writes a reason
- **THEN** the proposal MUST be removed from the queue
- **AND** the rejection (with reason if given) MUST be recorded in the audit log
- **AND** the loop MUST consider the rejection rationale on subsequent runs (no re-proposing the exact same change without new evidence)

### Requirement: Mandatory audit trail

Every loop run SHALL produce an audit-log entry containing: run timestamp, files considered, files written (or proposed), the diff, the rationale, and the outcome (applied / pending-review / coalesced / retired-stale / rejected).

#### Scenario: A loop run completes with no changes

- **WHEN** the loop runs and decides to do nothing
- **THEN** an audit-log entry MUST still be written recording the no-op decision
- **AND** the entry MUST be readable from the dashboard

### Requirement: Reversibility

Every applied change SHALL be reversible to the prior state for at least 30 days, via a snapshot mechanism captured before the write.

#### Scenario: Jake notices a regression three days after a loop change

- **WHEN** Jake invokes rollback on the loop's most recent run
- **THEN** the runner MUST restore the affected files to their pre-run state
- **AND** the rollback MUST itself be audit-logged

### Requirement: No loop on the loop

The loop SHALL NOT modify itself, the orchestrator skill (per [orchestration](../orchestration/spec.md)), the safety boundary, the audit-log writer, or the snapshot mechanism. Changes to those subsystems require manual edits by Jake.

#### Scenario: The loop proposes a change to its own safety code

- **WHEN** a planned write targets the loop's runner, the safety-boundary policy, the audit-log writer, or the orchestrator skill
- **THEN** the runner MUST reject the plan
- **AND** MUST surface it for manual review

### Requirement: Queue depth visibility

The dashboard SHALL show the current self-loop queue depth and the age of the oldest pending proposal at all times when proposals exist.

#### Scenario: The queue has 7 pending proposals, the oldest is 4 days old

- **WHEN** Jake opens the dashboard
- **THEN** the self-loop section MUST show "7 proposals pending, oldest 4 days"
- **AND** the indicator MUST be visible without expanding the section

### Requirement: Proposal coalescing on missed-review days

When the loop runs and finds existing pending proposals in the queue, it SHALL coalesce overlapping proposals rather than queueing duplicates. Two proposals overlap if they target the same file and produce changes whose diffs intersect.

#### Scenario: Yesterday's run proposed editing skill X; today's run proposes another edit to skill X

- **WHEN** the second proposal is generated
- **THEN** the loop MUST detect the overlap
- **AND** MUST merge the two diffs into one composite proposal (or supersede the older one if the new diff fully subsumes it)
- **AND** the audit log MUST record the coalescing decision

### Requirement: Stale proposal re-evaluation

A proposal that has sat in the queue unreviewed for more than 7 days SHALL be re-evaluated against the current state of the codebase before being shown to Jake again. If the underlying problem the proposal addresses no longer exists, the proposal MUST be retired automatically with an audit-log entry.

#### Scenario: A proposal fixes a typo that's already been fixed elsewhere

- **WHEN** Jake opens the dashboard 9 days after the proposal was generated
- **THEN** the loop MUST verify the typo still exists
- **AND** if it doesn't, the proposal MUST be marked "retired-no-longer-applicable"
- **AND** Jake MUST NOT be asked to review it

### Requirement: Generation pause on prolonged inactivity

If the queue has at least one pending proposal and no review activity (approve, reject, defer) has occurred in 14 consecutive days, the loop SHALL pause new-proposal generation until Jake clears the queue or explicitly resumes.

#### Scenario: Jake takes a 3-week break

- **WHEN** day 15 of inactivity arrives
- **THEN** the loop MUST NOT generate new proposals
- **AND** the dashboard MUST show "self-loop paused — N proposals awaiting review"
- **AND** approving, rejecting, or deferring any pending proposal MUST resume generation on the next scheduled run

### Requirement: Defer mechanism

A "defer N days" control SHALL exist on each proposal. Deferring a proposal moves it out of the active queue for N days, after which it returns to the queue and is subject to the stale-re-evaluation rule.

#### Scenario: Jake defers a proposal for 3 days

- **WHEN** Jake clicks "defer 3 days"
- **THEN** the proposal MUST disappear from the active queue
- **AND** MUST automatically reappear on day 4
- **AND** before reappearing, the loop MUST re-validate the proposal against current state (same as stale-re-evaluation)

## Open implementation details

- The snapshot mechanism (filesystem snapshot vs. git vs. tarball) — chosen during Phase 5.
- The exact loop runner (Cowork scheduled task vs. macOS launchd job) — chosen during Phase 5.
- The "rationale" format for proposals — defined by the loop's prompt design during Phase 5.
