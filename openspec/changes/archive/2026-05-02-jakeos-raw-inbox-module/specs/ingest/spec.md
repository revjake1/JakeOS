## ADDED Requirements

### Requirement: Raw-inbox scanner hooks into the trigger

After every debounced FSEvents cycle that this spec already governs, the sidecar SHALL invoke a raw-inbox scanner that walks `~/Documents/Obsidian Vault/Second brain/raw/**/*.md`, detects `- [ ]` / `- [x]` task lines, and reconciles them with the `raw_inbox` table per [data-contract](../data-contract/spec.md)'s "Raw inbox is mirrored, never authoritative" requirement.

The scanner SHALL also run on a periodic 10-minute interval as a belt-and-suspenders fallback for FSEvents events that may be dropped under load, during macOS sleep transitions, or by third-party sync clients.

The scanner SHALL be idempotent — repeated runs over an unchanged `raw/` MUST be no-ops at the data layer (no spurious state transitions and no spurious audit-log entries).

The scanner SHALL NOT modify any file in `raw/` under any circumstance, in keeping with the rule from `AGENTS.md` that the wiki ingest pipeline already honors.

#### Scenario: A new task line appears in `raw/` between sidecar restarts

- **WHEN** the sidecar starts and the resume-from-checkpoint scan runs
- **AND** a markdown file in `raw/` contains a `- [ ]` line that wasn't seen before
- **THEN** the raw-inbox scanner MUST be invoked as part of (or immediately after) the resume scan
- **AND** the new task line MUST become a `state=open` row in `raw_inbox`

#### Scenario: FSEvents fires after a debounced edit to a daily note

- **WHEN** the FSEvents watcher's debounced batch completes for a `.md` file in `raw/`
- **THEN** the raw-inbox scanner MUST run before the watcher returns to its idle state
- **AND** any added, removed, or text-edited task lines in the file MUST be reflected in `raw_inbox` per the identity scheme

#### Scenario: The 10-minute periodic poll fires with no changes

- **WHEN** the periodic poll runs and the manifest of `raw/` is unchanged from the previous scan
- **THEN** the scanner MUST complete without transitioning any inbox row's state
- **AND** the scanner MUST NOT emit any audit-log entries

#### Scenario: The scanner encounters a non-markdown file or hidden file

- **WHEN** the scanner walks a file that is not `.md`, is hidden (starts with `.`), or is inside a hidden directory (e.g., `.obsidian/`, `.trash/`)
- **THEN** the scanner MUST skip the file silently
- **AND** the file MUST NOT contribute to retire-detection
