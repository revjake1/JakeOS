## MODIFIED Requirements

### Requirement: Supported source types (v1)

Capture SHALL accept the following at v1: PDF, .docx, .rtf, .txt, .md, .eml, .html, .png, .jpg / .jpeg, .heic, .webp, screenshots from macOS clipboard, and dropped URLs (which are fetched and converted to markdown via a readability-style extractor). The Helper.app's existing `ConverterRegistry` ALSO covers `.markdown`, `.csv`, `.json`, `.xml`, `.htm`, `.tiff`, `.odt`, `.pptx`, `.xlsx`, `.xls`, `.epub`, and `.ipynb` — these remain supported.

The following types listed in the original v1 spec are deferred to a follow-up change:

- **`.doc`** (Word 97–2003 binary format): no native Swift parser without a third-party dependency. A drop of `.doc` MUST surface as an unsupported-type notification with a hint to convert to `.docx`.
- **`.mbox`** (multi-message mail archive): if the v1 single-message `.eml` parser cannot parse it cleanly, `.mbox` MUST surface as unsupported. v1 ships at minimum single-message `.eml` support.

Capture MAY accept additional types in follow-up changes; refusing an unsupported type MUST follow the "unsupported file type" scenario in the "Drop target on the macOS surface" requirement.

#### Scenario: A URL is pasted onto the target

- **WHEN** Jake drops a URL string onto the target (or pastes via a hotkey-bound action)
- **THEN** the sidecar OR Helper.app (per the implementation's choice) MUST fetch the URL, run readability extraction, and produce a `.companion.md` containing the extracted article text + metadata
- **AND** the original URL MUST be preserved in the frontmatter
- **AND** if the fetch fails (network error, paywall, 4xx/5xx), an error notification MUST surface and no partial files MUST be written

#### Scenario: A `.doc` (Word 97–2003) is dropped

- **WHEN** a `.doc` file is dropped onto the target
- **THEN** the target MUST surface a notification: "Unsupported in v1. Convert to .docx in Word and re-drop."
- **AND** the file MUST NOT be moved, copied, or modified

#### Scenario: A `.webp` image is dropped

- **WHEN** a `.webp` image is dropped onto the target
- **THEN** the original `.webp` MUST be copied to `raw/` byte-identical
- **AND** a `.companion.md` MUST be generated using the same extractor path as `.png`/`.jpg`

#### Scenario: A clipboard screenshot is captured via the menubar

- **WHEN** Jake invokes the "Capture from clipboard" action with an image on the macOS pasteboard
- **THEN** the image bytes MUST be written to `raw/clip-<yyyy-mm-dd-HHmm>.png` (or `.jpg`/`.heic` matching the pasteboard image's representation)
- **AND** a `.companion.md` MUST be generated via the existing image converter
- **AND** the user MUST receive a "captured" notification within 200ms

#### Scenario: A `.mbox` is dropped and the parser cannot handle it

- **WHEN** a `.mbox` file is dropped and the v1 single-message parser declines it
- **THEN** the target MUST surface an "Unsupported in v1" notification
- **AND** no files MUST be written
- **AND** the deferred-to-follow-up status MUST be reflected in the audit-log entry's outcome field

### Requirement: Capture audit log

Every capture event SHALL be recorded in the audit log defined in [data-contract](../data-contract/spec.md) with: timestamp, source filename, source hash, mime type, target path in `raw/`, and outcome (`captured` / `duplicate-skipped` / `unsupported` / `errored`). The Helper.app SHALL also call the sidecar's `POST /captures` (per [data-contract](../data-contract/spec.md)'s "API surface") on every successful capture so the central audit log AND the dashboard's "Recent captures" surface receive the event.

When the sidecar is unreachable at the moment of capture, the Helper.app MUST persist the registration to a pending-sync queue and replay it when the sidecar is next reachable. Local capture MUST succeed regardless of the sidecar's reachability — the registration is best-effort, eventually-consistent.

#### Scenario: A capture errors mid-conversion

- **WHEN** conversion fails (corrupt PDF, OCR failure, etc.)
- **THEN** the audit log MUST record the error with stack/cause
- **AND** any partial output files MUST be cleaned up before the audit entry is written
- **AND** the error MUST surface in the dashboard's recent-activity feed per [dashboard](../dashboard/spec.md)

#### Scenario: Sidecar is unreachable at the moment of capture

- **WHEN** Jake drops a file and the local conversion + write succeeds, but the sidecar is unreachable
- **THEN** the file MUST exist in `raw/` with its `.companion.md`
- **AND** the registration MUST be persisted to the pending-sync queue
- **AND** the user MUST receive a "captured locally; pending sync" notification rather than a generic "captured" success
- **AND** when the sidecar becomes reachable, the queued registration MUST replay automatically and the dashboard's "Recent captures" MUST show the entry within one sync cycle of the replay
