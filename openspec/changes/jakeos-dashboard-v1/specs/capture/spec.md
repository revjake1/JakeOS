# capture — spec delta

> File-to-markdown capture into the second-brain wiki's `raw/` folder. Implemented as a native macOS drag-and-drop surface (the repurposed Swift UI of Helper.app) backed by the Rust sidecar's conversion pipeline. Distinct from `ingest/` (which pulls from `raw/` into `wiki/`); `capture` puts things INTO `raw/`.

## Context (locked elsewhere)

- Surface architecture: web tab consumes; Helper.app's Swift UI is the capture surface (per design.md Q1 = B and Q2 = α).
- The wiki's RAW folder rules are defined in `~/Documents/Obsidian Vault/Second brain/AGENTS.md`. This spec defers to those rules and MUST NOT contradict them.

## ADDED Requirements

### Requirement: Drop target on the macOS surface

The Helper.app SHALL expose a drag-and-drop target reachable without launching a window — at minimum a menubar item or a dock-icon drop affordance. Dropping any supported item onto the target SHALL initiate capture without further user interaction.

#### Scenario: Jake drags a PDF onto the menubar item

- **WHEN** a PDF is dropped on the target
- **THEN** the capture pipeline MUST start within 200ms of the drop event
- **AND** the user MUST receive visual confirmation (icon flash, badge, or notification) that the drop was accepted
- **AND** Jake MUST NOT be required to confirm any modal dialog for the common case

#### Scenario: An unsupported file type is dropped

- **WHEN** a file of unsupported type is dropped
- **THEN** the target MUST surface a brief notification naming the type and refusing the capture
- **AND** the file MUST NOT be moved, copied, or modified

### Requirement: Preserve the original

Originals SHALL be copied unmodified into `raw/`. Capture MUST NEVER alter, rename, or delete the source file at its original location, and MUST NEVER modify the file once placed in `raw/`. This honors the `AGENTS.md` rule: "Never modify or delete an existing source file in `raw/`."

#### Scenario: A dropped PDF is captured

- **WHEN** capture writes the original to `raw/`
- **THEN** the bytes of the captured file MUST be byte-identical to the source
- **AND** any subsequent re-drop of the same file MUST NOT overwrite the existing copy in `raw/`

### Requirement: Markdown companion note

For every captured non-markdown source, capture SHALL produce a markdown companion note in `raw/` that contains: (a) extracted text content, (b) source metadata (filename, mime type, capture timestamp, original location, file size, hash), (c) a stable link to the original file in `raw/`. The companion's filename SHALL be `<source-stem>.companion.md`.

#### Scenario: A .docx is captured

- **WHEN** the conversion pipeline finishes
- **THEN** `raw/<original>.docx` exists with the original bytes
- **AND** `raw/<original>.companion.md` exists containing extracted text + metadata frontmatter
- **AND** the companion MUST NOT contain any content that doesn't appear in the source (no LLM elaboration; this is extraction, not summarization)

#### Scenario: A markdown file is dropped

- **WHEN** the source is already `.md`
- **THEN** no companion is generated
- **AND** the original is placed at `raw/<filename>.md`

### Requirement: Supported source types (v1)

Capture SHALL accept the following at v1: PDF, .docx, .doc, .rtf, .txt, .md, .eml / .mbox, .html, .png, .jpg / .jpeg, .heic, .webp, screenshots from macOS clipboard, and dropped URLs (which are fetched and converted to markdown via a readability-style extractor).

Capture MAY accept additional types in follow-up changes; refusing an unsupported type MUST follow the "unsupported file type" scenario above.

#### Scenario: A URL is pasted onto the target

- **WHEN** Jake drops a URL string onto the target (or pastes via a hotkey-bound action)
- **THEN** the sidecar MUST fetch the URL, run readability extraction, and produce a `.companion.md` containing the extracted article text + metadata
- **AND** the original URL MUST be preserved in the frontmatter
- **AND** if the fetch fails (network error, paywall, 4xx/5xx), an error notification MUST surface and no partial files MUST be written

### Requirement: Idempotency on duplicate drops

Capture SHALL detect when a dropped item is byte-identical to an existing entry in `raw/` and SHALL treat the second drop as a no-op rather than producing a duplicate.

#### Scenario: Jake drops the same PDF twice in one session

- **WHEN** the second drop arrives
- **THEN** the sidecar MUST detect the duplicate via content hash before writing
- **AND** the existing `raw/` entry MUST be left untouched
- **AND** the user MUST receive a "duplicate, skipped" notification rather than a generic success

#### Scenario: A different file with the same filename is dropped

- **WHEN** the second drop has the same name but different bytes
- **THEN** capture MUST NOT overwrite the existing file
- **AND** the new capture MUST be saved under a disambiguated filename (e.g., `<stem>--<short-hash>.<ext>`)
- **AND** both companion notes MUST exist

### Requirement: Atomic writes

Capture writes to `raw/` SHALL be atomic from the wiki's perspective. The ingest watcher (per `ingest/spec.md`) MUST NOT see partial files.

#### Scenario: A large PDF is in the middle of conversion

- **WHEN** the ingest watcher fires while capture is mid-write
- **THEN** the watcher MUST NOT see any in-progress files (use a staging directory + rename, or a hidden filename prefix that the watcher ignores)

### Requirement: Capture audit log

Every capture event SHALL be recorded in the cross-surface audit log defined in `data-contract/spec.md` with: timestamp, source filename, source hash, mime type, target path in `raw/`, and outcome (captured / duplicate-skipped / unsupported / errored).

#### Scenario: A capture errors mid-conversion

- **WHEN** conversion fails (corrupt PDF, OCR failure, etc.)
- **THEN** the audit log MUST record the error with stack/cause
- **AND** any partial output files MUST be cleaned up before the audit entry is written
- **AND** the error MUST surface in the dashboard's recent-activity feed

### Requirement: Local-only credentials

Capture writes MUST NOT require any network credentials beyond what the conversion pipeline already needs (e.g., a URL fetch). Capture MUST work on the local filesystem with the user's macOS account, with no separate JakeOS sign-in.

#### Scenario: Jake drops a file while offline

- **WHEN** the network is unreachable
- **THEN** captures of local files (PDF, .docx, image, etc.) MUST still succeed
- **AND** only URL-fetch captures MUST fail (with the error scenario above)

### Requirement: Discoverable from the web tab

The dashboard SHALL surface a recent-captures view (last N items, configurable) so Jake can verify captures landed correctly without leaving the tab.

#### Scenario: Jake just dropped three files and switches to the dashboard

- **WHEN** the dashboard loads
- **THEN** the recent-captures view MUST list those three captures within one sync cycle
- **AND** each entry MUST link to its companion note in the wiki

## TBD pending design.md decisions

- Whether the URL-fetch path requires Jake-supplied auth (cookies, headers) for paywalled sources — deferred to a follow-up change.
- The exact set of OCR / extractor libraries — chosen during Phase 4.10 implementation.
- Whether the screenshot path uses macOS Continuity Camera as a third input — deferred.
