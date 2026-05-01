# orchestration — spec delta

> Codifies source-note bullet 13 as testable requirements: "DO NOT BUILD ONE HUGE MONOLITHIC SKILL. Delegate to subagents when appropriate, and have one overarching orchestrator skill that uses many smaller subskills." Every requirement here is meant to be enforceable by audit, not by good intentions.

## ADDED Requirements

### Requirement: Single orchestrator entry point

JakeOS SHALL have exactly one orchestrator skill that serves as the entry point for dashboard-driven work. The orchestrator's job is routing: it identifies which subskill (or sub-agent) should handle a request and delegates. The orchestrator itself MUST NOT contain capability-specific logic (no email parsing, no calendar reasoning, no todo CRUD) beyond what's needed to route.

#### Scenario: A new capability is added

- **WHEN** a new capability lands (e.g., a new module from `tasks.md` Phase 4)
- **THEN** the orchestrator MUST be updated only to add a route to the new subskill
- **AND** the capability's logic MUST live in its own subskill, not in the orchestrator

#### Scenario: The orchestrator gains domain logic

- **WHEN** the orchestrator's source contains code or prompt text that performs a capability's work directly (not routing)
- **THEN** an audit MUST flag it as a monolith violation
- **AND** the work MUST be migrated into a subskill before the next change archives

### Requirement: Per-skill size budget

Each subskill SHALL stay under a defined maximum size. The v1 budget is **300 lines of SKILL.md content** (excluding YAML frontmatter and code-fenced reference blocks longer than 20 lines, which count separately). Skills that exceed the budget MUST be split.

#### Scenario: A subskill grows past 300 lines

- **WHEN** an audit measures a subskill at 301+ content lines
- **THEN** the audit MUST flag the skill for decomposition
- **AND** the next change touching that skill MUST split it before adding new behavior

#### Scenario: A reference block exceeds 20 lines

- **WHEN** a skill embeds a long reference (e.g., a schema, a long example)
- **THEN** the reference SHALL be moved to a sibling file under the skill's directory and linked from SKILL.md
- **AND** SKILL.md remains under the line budget

### Requirement: Single responsibility per subskill

Each subskill SHALL handle exactly one capability. The capability MUST be expressible in a single sentence of the form "When <trigger>, this skill <does one thing>." Skills that need a compound description ("does X and also Y") MUST be split.

#### Scenario: A skill description contains "and"

- **WHEN** a skill's `description:` frontmatter joins two unrelated triggers with "and" / "also" / "as well as"
- **THEN** the skill MUST be reviewed for splitting
- **AND** if the two triggers genuinely cover different capabilities, the skill MUST be split

### Requirement: Discriminating descriptions

Each subskill's `description:` field SHALL be specific enough that an LLM picking among JakeOS skills can choose the correct one without guessing. Generic descriptions ("handles email things", "does dashboard work") are not acceptable.

#### Scenario: Two skills could plausibly fire on the same request

- **WHEN** an audit identifies overlapping trigger conditions across two skills
- **THEN** at least one of the descriptions MUST be revised so the boundary is unambiguous
- **AND** the revision MUST be verified by an eval that hands ambiguous prompts to the skill picker and confirms the right skill fires

### Requirement: Bounded delegation depth

A subskill SHALL NOT call more than 3 other JakeOS skills synchronously in a single invocation. Deeper chains MUST be implemented as separate orchestrator turns or as sub-agents (not as nested skill calls inside one execution).

#### Scenario: A subskill chains four skills

- **WHEN** a subskill's body invokes four or more sibling skills in one run
- **THEN** the chain MUST be refactored to delegate the tail of the chain to a sub-agent or to return control to the orchestrator

### Requirement: Sub-agent delegation when appropriate

Long-running work, work that needs an isolated context, or work that calls many skills SHALL be delegated to a sub-agent rather than executed inline. The dividing line is: if the work would consume more than ~30% of the orchestrator's available context budget OR more than 3 chained skill calls, it goes to a sub-agent.

#### Scenario: An ingest cycle runs

- **WHEN** the orchestrator handles a RAW-folder ingest trigger (per `ingest/spec.md`)
- **THEN** the actual ingest work MUST run in a sub-agent
- **AND** the orchestrator MUST receive only a summary back, not the full transcript

### Requirement: Drift audit

A scheduled audit SHALL run at least weekly and MUST report: per-skill line counts, descriptions with overlap risk, skills exceeding the depth limit, and any new capability code that landed inside the orchestrator. The audit's output is captured in the dashboard and feeds the self-improvement loop's review queue.

#### Scenario: The weekly audit finds a violation

- **WHEN** the audit detects any of the conditions above
- **THEN** the violation MUST appear in the dashboard's "skill health" surface
- **AND** the next loop run (per `self-loop/spec.md`) MUST queue it for resolution

### Requirement: No orchestrator self-modification by the loop

The self-improvement loop (per `self-loop/spec.md`) SHALL NOT modify the orchestrator skill or this spec's enforcement code without manual review. This prevents the loop from quietly absorbing capability logic back into the orchestrator.

#### Scenario: The loop proposes an orchestrator change

- **WHEN** a loop run's plan includes a write to the orchestrator skill
- **THEN** the runner MUST reject auto-apply regardless of the chosen Q4 boundary
- **AND** the change MUST be surfaced for explicit Jake approval

## TBD pending design.md decisions

- Where the orchestrator lives (Cowork skill folder vs. inside the macOS Helper vs. server-side) — depends on Q1
- Where the drift audit runs (Cowork scheduled task vs. macOS launchd vs. server cron) — depends on Q5's mechanism choice
- Whether the line-count budget needs adjustment after the first round of subskills lands; v1 budget is 300 lines and will be re-measured at Phase 6.2
