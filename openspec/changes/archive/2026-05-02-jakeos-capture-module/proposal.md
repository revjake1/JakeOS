## Why

Phase 4.10 of [`jakeos-dashboard-v1`](../jakeos-dashboard-v1/proposal.md) — "File-to-markdown capture" — has been the longest-standing un-shipped module. The long-lived spec at [`capture/spec.md`](../../specs/capture/spec.md) was written 2026-05-01 and the Helper.app's Swift side already contains the bulk of an implementation: a `DropZoneView`, a `ConverterRegistry` routing PDF / image / markdown / plain-text / RTF/HTML / `.docx` / `.odt` / `.pptx` / `.xlsx` / `.epub` / `.ipynb` to native Swift converters, a `MarkdownWriter` that writes atomically to `raw/` with YAML frontmatter, a `DuplicateDetector` for content-hash idempotency, and an `ImportQueue` for serialized processing. ~870 lines of working Swift code. What's missing is the wiring: the menubar drop affordance, URL drops, unsupported-type rejection notification, and — most importantly — the integration that makes captures visible from the dashboard. Today the Helper.app's `RecentActivityStore` is local to the app process; the sidecar's `captures` table sees zero entries; the dashboard's "Recent captures" section consequently renders empty.

This change wires the existing Swift pipeline into the JakeOS surface. Companion to [`jakeos-todos-module`](../archive/2026-05-01-jakeos-todos-module/proposal.md), [`jakeos-raw-inbox-module`](../archive/2026-05-02-jakeos-raw-inbox-module/proposal.md), and [`jakeos-ingest-surface-module`](../archive/2026-05-02-jakeos-ingest-surface-module/proposal.md) — same pattern: the work is on the integration seam, not the conversion logic.

The architecture call for this change is locked: **conversion stays in Swift**. The 7 existing Swift converters work well for the local-file path, including the formats the sidecar would otherwise need brand-new Rust crates for (`.docx`, `.epub`, `.ipynb`). Building a parallel Rust pipeline would duplicate ~500 lines of working code with no user-visible benefit. The sidecar's role in this change is the audit + dashboard registration point: every Helper.app capture POSTs metadata to `/captures` so the central audit log and the dashboard see the event. URL drops and clipboard screenshots are added on the Swift side using `URLSession` + `NSPasteboard`.

## What Changes

### Helper.app — Second-brain-helper-app (Swift)

- **Menubar drop affordance.** The existing `MenuBarExtra` in `SecondBrainHelperApp.swift` opens a window that contains the `DropZoneView` — but it does not itself accept drops. Add a drop-target wrapper around the menubar icon (or wire the popover to accept drops without first opening) so a drag-and-drop onto the menubar starts capture without first requiring a click. Per [`capture/spec.md`](../../specs/capture/spec.md) "Drop target on the macOS surface": `MUST` start within 200ms of the drop event, no modal dialog for the common case.
- **URL drops.** `ImportQueue` currently bails on `!url.isFileURL`. Extend it (or add a sibling `UrlImportQueue`) that on a non-file-URL drop performs `URLSession.fetch + readability extraction + companion .md write` per `capture/spec.md` "Supported source types (v1)" and "Idempotency on duplicate drops". Network errors surface as the spec-mandated error notification with no partial files written.
- **Clipboard screenshot import.** Add a hotkey-bound action (or a "Capture from clipboard" menubar button) that reads `NSPasteboard.general.image`, writes it to `raw/` as a timestamped `.png`, generates a `.companion.md` via the existing `ImageConverter`, and registers it.
- **Unsupported-type rejection notification.** `ConverterRegistry.converter(for:)` already throws `ConversionError.unsupported(extension:)`. The current `ImportQueue.processOne` returns this as an `ImportResult.failure` consumed by `RecentActivityStore`, but no user-facing notification fires. Add a `UNUserNotificationCenter` notification (or an in-app toast in the menubar window) per `capture/spec.md`'s "An unsupported file type is dropped" scenario.
- **Sync each capture to the sidecar.** After every successful `MarkdownWriter.write(...)`, call the sidecar's `POST /captures` with the enriched payload (see "Sidecar" below). Failure to reach the sidecar MUST NOT prevent the local capture from succeeding — the file is on disk, the local-only fallback per `capture/spec.md` "Local-only credentials" still applies; the registration is best-effort, retried on next Helper.app launch via a small "pending sync" queue persisted in `UserDefaults` or the existing `state/` directory.
- **Spec-gap formats.** The existing registry covers all spec-listed types except `.eml`/`.mbox`, `.webp`, `.doc` (Word 97-2003), and screenshot-from-clipboard. v1 scope:
  - `.eml`/`.mbox`: add a small Swift parser (or use `Mail.framework` if available); fall back to "unsupported" notification if not.
  - `.webp`: add to `ImageConverter`'s extension list (NSImage handles `.webp` on macOS 13+).
  - `.doc`: defer to a follow-up change. Surface as "unsupported" with a hint to convert to .docx.
  - Screenshot: covered by the clipboard-import path above.

### Sidecar — Second-brain-helper-app/sidecar (Rust)

- **Extend `POST /captures` payload + schema.** The existing endpoint at [`src/api/captures.rs`](Documents/Second-brain-helper-app/sidecar/src/api/captures.rs) accepts only `{ raw_path, original_kind, source }`. Extend the JSON body to also accept `{ filename, mime_type, size_bytes, sha256, companion_path?, captured_at? }` so the audit log and the dashboard have meaningful per-capture detail. Backward-compatible: missing fields stay nullable.
- **Migration `0003_capture_metadata.sql`** adds nullable columns to the existing `captures` table: `filename TEXT`, `mime_type TEXT`, `size_bytes INTEGER`, `sha256 TEXT`, `companion_path TEXT`. Index `idx_captures_sha256` for the duplicate-detection scenario.
- **Duplicate detection on the sidecar side.** When `POST /captures` receives a request with a `sha256` that already exists in `captures`, return a `200` with the existing capture's id and an `is_duplicate: true` flag rather than creating a new row. This complements (does not replace) the Helper.app's `DuplicateDetector` — both layers perform the check to keep the system honest if a future surface bypasses the Swift detector.
- **No new conversion code in the sidecar.** Per the architecture decision in design.md, the sidecar does not convert files. The existing JSON `POST /captures` is the only write surface; multipart upload is not added.

### Web — jakeos-web (Node.js + HTMX)

- **Enrich [`renderCaptures`](Documents/jakeos-web/src/sections.js:424).** The existing renderer already polls `GET /captures?limit=8` and shows filename + kind + date. Extend the row to surface the new fields when present: human-readable mime, file size (e.g., "PDF · 2.3 MB · 14:22 today"), and a link to the companion `.md` in the wiki (using the existing wiki-path convention).
- **No new poll cadence.** The existing `every 15s` trigger on `#card-captures .card-body` is sufficient.

### Spec deltas

- **`capture/spec.md`:** scope reduction — defer `.doc` (Word 97–2003) to a follow-up change. The existing requirement enumerates "PDF, .docx, .doc, .rtf, .txt, .md, .eml/.mbox, .html, .png, .jpg/.jpeg, .heic, .webp, screenshots, URLs"; this change explicitly notes `.doc` is out of scope for v1 and adds a note in the supported-types requirement.
- **`dashboard/spec.md`:** modify `Recent captures surface` to specify the per-row content (filename, mime, size, captured_at, companion link) so the dashboard renderer is testable. Also add a scenario for the duplicate case so the surface clearly distinguishes it.
- **`data-contract/spec.md`:** modify `API surface` to enumerate the enriched `POST /captures` body and the duplicate-detection response shape. The captures table schema additions are documented as the v1 contract; future fields are additive only.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `capture`: scope reduction on `.doc` (defer to follow-up); no other requirement changes.
- `dashboard`: enrich `Recent captures surface` with per-row content fields and a duplicate-case scenario.
- `data-contract`: enrich the `POST /captures` API surface with the new metadata fields and the duplicate-detection response.

## Impact

- **Code:**
  - Helper.app (`~/Documents/Second-brain-helper-app/SecondBrainHelper`): touch `SecondBrainHelperApp.swift` (menubar drop wiring), `Services/ImportQueue.swift` (URL handling, sidecar sync), `Services/MarkdownWriter.swift` (record sha256 alongside write), `Converters/ImageConverter.swift` (add `.webp`), new `Services/SidecarClient.swift` (POST /captures helper), new `Converters/EmlConverter.swift`, new `Services/PendingSyncQueue.swift`, new `Services/ClipboardImporter.swift`, new `Services/UrlImporter.swift` (or extension on ImportQueue).
  - Sidecar (`~/Documents/Second-brain-helper-app/sidecar`): touch `src/api/captures.rs` (enriched body, duplicate response, audit-log payload), new `src/db/migrations/0002_capture_metadata.sql` (note: 0002 is taken by raw-inbox; this becomes `0003_capture_metadata.sql` per the existing numbering — verify in apply).
  - Web (`~/Documents/jakeos-web/src/sections.js`): touch `renderCaptures` for the enriched row.
- **APIs:** `POST /captures` body extended (backward-compatible); `GET /captures?limit=N` response extended (additive). No new endpoints.
- **Dependencies:** Swift side may add a small readability-extraction lib (or hand-roll a minimal `<article>`/`<main>` tag-stripper for v1). No new Rust crates expected.
- **Systems:** UnRAID stack picks up a refreshed jakeos-web image. Sidecar binary rebuilds + relaunches via `cargo build --release` + `launchctl kickstart`. Helper.app rebuilds via Xcode + manual relaunch (the LaunchAgent is for the sidecar, not the helper).
- **Tasks:** marks task **4.10** `[x]` in `jakeos-dashboard-v1/tasks.md` once verified end-to-end.
