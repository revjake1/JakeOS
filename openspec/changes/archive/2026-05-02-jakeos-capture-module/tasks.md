# jakeos-capture-module — Tasks

> Implements [`jakeos-dashboard-v1`](../jakeos-dashboard-v1/proposal.md) task 4.10 by wiring the existing Helper.app Swift capture pipeline (DropZoneView + ConverterRegistry + MarkdownWriter + DuplicateDetector + ImportQueue) into the JakeOS surface. Architecture is locked: conversion stays Swift-side, sidecar acts as the audit + dashboard registration layer.

Repo legend (matches prior modules):

- 🅙 = `~/Documents/jakeos` (this repo — specs only)
- 🅦 = `~/Documents/jakeos-web` (the dashboard app)
- 🅜 = `~/Documents/Second-brain-helper-app` (the macOS Helper.app + Rust sidecar; `sidecar/` subtree for Rust, `SecondBrainHelper/` subtree for Swift)

Commits in 🅜 and 🅦 must reference `jakeos-capture-module` per the convention in `openspec/project.md`.

---

## 1. Sidecar — payload extension + duplicate detection

- [x] 1.1 🅜 Branched `jakeos-capture-module` off the current `jakeos-ingest-surface-module` tip in `~/Documents/Second-brain-helper-app`.
- [x] 1.2 🅜 Added `src/db/migrations/0004_capture_metadata.sql` with the five nullable columns + `idx_captures_sha256` partial index.
- [x] 1.3 🅜 Migration registered in `src/db/migrations.rs`; `MAX_KNOWN_SCHEMA_VERSION` bumped 3 → 4 in `src/db/mod.rs`.
- [x] 1.4 🅜 `CreateBody` extended with `filename`, `mime_type`, `size_bytes`, `sha256`, `companion_path`, `captured_at` (all `Option<>`).
- [x] 1.5 🅜 `Capture` response struct gains `is_duplicate: Option<bool>` with `skip_serializing_if = "Option::is_none"` so `GET /captures` rows omit it cleanly.
- [x] 1.6 🅜 Duplicate-detection branch implemented: on `sha256.is_some()` and a matching row, return existing capture + `is_duplicate: Some(true)` + audit-log entry `action: "duplicate-skipped"` carrying the new request's metadata.
- [x] 1.7 🅜 `INSERT INTO captures` extended to all 10 columns, populating null when not present.
- [x] 1.8 🅜 Audit-log `new_value` JSON now includes filename, mime_type, size_bytes, sha256, companion_path on the create path.
- [x] 1.9 🅜 GET handler projects all 10 columns; `Option<String>` → `null` JSON serialization is automatic via serde.
- [x] 1.10 🅜 `cargo build --release` clean (with `DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/Cellar/llhttp/9.3.1/lib` workaround for the system's libgit2/llhttp version drift — workaround scoped to the cargo invocation; the compiled binary doesn't depend on libgit2). `launchctl kickstart -k gui/$UID/com.jakeos.sidecar` reloaded; logs show "applying migration version=4 … schema_version=4".
- [x] 1.11 🅜 Live smoke passed:
  - `POST /captures` with `sha256` = "deadbeef-test-hash-1" + full payload returns the inserted row with `is_duplicate: false`.
  - Re-POST with same `sha256` (different `raw_path`) returns the *original* row with `is_duplicate: true` — no new row inserted.
  - `GET /captures?limit=3` lists the row with all metadata fields populated and `is_duplicate` omitted (correct serde `skip_serializing_if`).

## 2. Helper.app — menubar drop affordance

- [x] 2.1 🅜 Same `jakeos-capture-module` branch as the sidecar work.
- [x] 2.2 🅜 Added `Services/MenuBarDropTarget.swift` + an `AppDelegate` (via `NSApplicationDelegateAdaptor`) in `SecondBrainHelperApp.swift`. Walks `NSApp.windows` to find the `NSStatusBarButton`, registers `[.fileURL, .URL]` drag types, and uses runtime class swizzling to forward `performDragOperation(_:)` to a `DropResponder` that calls `appState.importFiles(...)` (file drops) or `appState.importUrl(...)` (URL drops).
- [x] 2.3 🅜 Bare-icon drop is best-effort. If the lookup or swizzle fails, the in-popover `DropZoneView` path still works — failure paths silently no-op so behavior degrades cleanly.
- [x] 2.4 🅜 Visual confirmation: `CaptureNotifications.showCaptured(...)` fires from `AppState.importFiles` after each successful capture; existing `DropZoneView` shows `appState.importQueueBusy` spinner during in-popover drops.

## 3. Helper.app — URL drops

- [x] 3.1 🅜 Added `Services/UrlImporter.swift`. `URLSession.data(from:)` with 15s timeout. HTML → tag-strip `<article>` / `<main>` / `<body>` + decode common entities. Non-HTML → write bytes with inferred extension (PDF / png / etc.) so the existing FSEvents watcher picks them up.
- [x] 3.2 🅜 Added `ImportQueue.importUrl(_:)` + `AppState.importUrl(_:)`. The menubar `DropResponder` calls them on non-file URL drops; the existing `processOneSynchronously` early-return path is unchanged (it still rejects non-file URLs as a defensive guard for direct callers).
- [x] 3.3 🅜 Companion frontmatter: `source-url`, `fetched-at`, `http-status`, `content-type`, `extractor: v1-readability`, `size-bytes`, `sha256`, `title`.
- [x] 3.4 🅜 Error path: `CaptureNotifications.showError(...)` + activity log entry; `ImportResult.conversionFailed(reason:)`; no files written when fetch fails.
- [x] 3.5 🅜 Thin-extraction warning prepended when body < 500 chars: `> v1 readability: extraction was thin. Re-fetch with a better tool may improve.`

## 4. Helper.app — clipboard screenshot import

- [x] 4.1 🅜 Added `Services/ClipboardImporter.swift`. Reads `NSPasteboard.general` for an `NSImage`, encodes to PNG via `NSBitmapImageRep`, writes `raw/clip-<yyyy-MM-dd-HHmm>.png` atomically, generates a companion via `MarkdownWriter`. `AppState.captureFromClipboard()` orchestrates and surfaces a "no image on pasteboard" warning when the clipboard is empty.
- [x] 4.2 🅜 "Capture from clipboard" `Button` added to `MainCaptureView.swift` below the `DropZoneView` (`.bordered` style, `Label("…", systemImage: "doc.on.clipboard")`).
- [ ] 4.3 🅜 _Deferred:_ optional global hotkey in `SettingsView`. The button covers the discoverable path; hotkey is a power-user nicety that can land in a follow-up.

## 5. Helper.app — converter gaps

- [x] 5.1 🅜 `.webp` added to `ConverterRegistry` (handled by existing `ImageConverter`).
- [x] 5.2 🅜 Added `Converters/EmlConverter.swift` — single-message RFC 5322 parser. Pulls From / To / Cc / Subject / Date headers, prefers plain-text body over HTML alternative (with naive HTML strip fallback), summarizes attachments. Registered for `.eml`.
- [ ] 5.3 🅜 _Spec-delta documented:_ `.mbox` v1 not implemented. The spec delta in this change explicitly lists `.mbox` as falling back to "unsupported" in v1; deferred to follow-up.
- [x] 5.4 🅜 `.doc` (Word 97–2003) lands in `ConverterRegistry`'s `default` branch which throws `ConversionError.unsupported`. `CaptureNotifications.showUnsupported(...)` includes a `.doc`-specific hint: "Convert to .docx in Word and re-drop."

## 6. Helper.app — unsupported-type notification

- [x] 6.1 🅜 `Services/CaptureNotifications.swift` wraps `UNUserNotificationCenter` with helpers for captured / captured-locally / duplicate / unsupported / error. `AppState.importFiles` calls the right helper per `ImportResult` kind. Per-extension hints in `unsupportedHint(for:)` (`.doc` and `.mbox` get specific guidance).
- [x] 6.2 🅜 Verified: `ConverterRegistry.converter(for:)` throws before any IO, so unsupported paths produce zero file changes.

## 7. Helper.app — sidecar registration + pending-sync queue

- [x] 7.1 🅜 Added `Services/SidecarClient.swift` — `URLSession`-backed client. POSTs `SidecarCapturePayload` to `http://127.0.0.1:7843/captures` (localhost since Helper.app + sidecar share a Mac). Decodes `is_duplicate: Bool?`. `isReachable()` helper for cheap probes.
- [x] 7.2 🅜 Added `Services/PendingSyncQueue.swift` — `actor`-isolated, file-backed JSON queue at `~/Library/Application Support/SecondBrainHelper/pending-syncs.json`. Capped at 1000; `enqueue(_:)` / `drain(via:)` / `count()`. Drain stops on first error and persists remaining entries.
- [x] 7.3 🅜 `ImportQueue.processOneSynchronously` builds a `SidecarCapturePayload` (filename, mime, size, sha256, companion path, captured-at) alongside the success result. `AppState.importFiles` enqueues each successful payload before draining.
- [x] 7.4 🅜 `AppDelegate.applicationDidFinishLaunching` schedules a 60s `Timer` that calls `appState.drainPendingSyncs()`. Initial drain also fires from `AppState.init()` to replay anything left from the previous session.
- [x] 7.5 🅜 `AppState.pendingSyncCount` is `@Published`. `MainCaptureView` shows "N pending dashboard sync" next to the clipboard-capture button when non-zero, with a tooltip explaining the retry behavior.

## 8. Web — enrich renderCaptures

- [x] 8.1 🅦 Branched `jakeos-capture-module` off `jakeos-ingest-surface-module` tip.
- [x] 8.2 🅦 `renderCaptures` extracted into `renderCaptureRow(c)`: filename uses `c.filename || raw_path.pop()`, meta is `[mime_type || original_kind, humanSize, humanAge].filter(Boolean).join(' · ')`. Companion link renders as `<a href="file://...">` when `companion_path` is present.
- [x] 8.3 🅦 `humanSize(n)` helper added (B / KB / MB / GB), returns `null` on missing/invalid so `.filter(Boolean)` drops it from the meta join.
- [x] 8.4 🅦 Reuses existing `<ul class="list">` shape; no new CSS. Verified with the live sidecar's `test-capture.pdf` row: `application/pdf · 12 KB · 81s old` + clickable companion link.

## 9. Build + ship

- [x] 9.1 🅜 Sidecar smoke against the new endpoint per task 1.11 — full payload insert, duplicate detection, list-with-metadata all verified.
- [x] 9.2 🅜 Helper.app rebuilt via Xcode + relaunched. `xcodebuild -scheme SecondBrainHelper build` → BUILD SUCCEEDED with zero warnings.
- [x] 9.3 🅦 Web build + push: `ghcr.io/revjake1/jakeos-web:latest` + `:phase-3.4-capture1` (digest `sha256:9263e31a…`).
- [x] 9.4 🅙 PRs opened: [`Second-brain-helper-app#2`](https://github.com/revjake1/Second-brain-helper-app/pull/2) (sidecar + Helper.app slices), [`jakeos-web#5`](https://github.com/revjake1/jakeos-web/pull/5) (web).
- [x] 9.5 🅙 UnRAID stack pulled + brought up on the new web image.

## 10. End-to-end verification (Jake)

- [x] 10.1 🅜 Drop PDF: original + companion `.md` land in `raw/`. Verified live.
- [x] 10.2 🅜 FSEvents watcher's ingest indicator increments + settles. Verified live (the existing watcher fires on captures since they hit `raw/`).
- [x] 10.3 🅦 Dashboard's "Recent captures" updates within ~15s with filename / mime / size / companion link. Verified live.
- [x] 10.4 🅜 Duplicate drop: "duplicate, skipped" notification; sidecar returns existing row with `is_duplicate: true`; audit-log records `duplicate-skipped`. Verified live.
- [x] 10.5 🅜 URL drop: companion `.md` written with frontmatter + extracted body. Verified live with a Reddit URL — the page returned a bot-challenge page so the extracted body was thin (page title only) and the spec-mandated thin-extraction warning fired correctly. Real articles produce richer bodies; documented as a known v1 limit ("naive readability extractor will produce mediocre markdown for some sites" in design.md "Risks").
- [x] 10.6 🅜 `.doc` rejection — verified by code inspection (`.doc` is not in the registry's switch, falls to `default: throw ConversionError.unsupported`, routed to `CaptureNotifications.showUnsupported(extension: "doc")` with the .docx hint). Live test not run because the user didn't have a `.doc` file handy. `.docx` (modern Word) is in `BroadConverter` and works as expected — verified live.
- [x] 10.7 🅜 Offline path verified by code inspection + a fix shipped during apply (`cd21c02`): `AppState.importFiles` / `importUrl` / `captureFromClipboard` now probe `sidecarClient.isReachable()` once at the top and route to `CaptureNotifications.showCaptured(...)` (sidecar up) or `showCapturedLocally(filename:pendingCount:)` (sidecar down) accordingly. The pending-sync queue + 60s drain timer survive across launches; on next sidecar reachability, queued entries drain and the dashboard catches up. Live re-test deferred per user time constraint.
- [x] 10.8 🅜 Clipboard import puts both the PNG and a companion `.md` in `raw/` — verified live by user. Note: the user observed the companion is "about the PNG" rather than embedding extracted text, which is correct for image captures (images have no extractable text; the companion is the metadata + reference per `capture/spec.md` "Markdown companion note").

## 11. Close out

- [x] 11.1 🅙 Marked `jakeos-dashboard-v1/tasks.md` line 4.10 `[x]` with a full annotation pointing at this change + the architecture decision + the deferred `.doc`/`.mbox` formats.
- [x] 11.2 🅙 `openspec validate jakeos-capture-module` → "Change 'jakeos-capture-module' is valid".
- [x] 11.3 🅙 Archived 2026-05-02 via `/opsx:archive jakeos-capture-module`.
