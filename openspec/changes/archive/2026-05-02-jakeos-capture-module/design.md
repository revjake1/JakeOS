## Context

The Helper.app's Swift capture pipeline is the largest piece of pre-existing implementation in JakeOS. It was built before JakeOS-the-product existed and is genuinely sophisticated:

- **`Views/DropZoneView.swift`** — `onDrop(of: [.fileURL])` rendered with affordance state.
- **`Converters/ConverterRegistry.swift`** — switch on `pathExtension`, routes to: `MarkdownConverter` (`.md`/`.markdown`), `PlainTextConverter` (`.txt`/`.csv`/`.json`/`.xml` with optional fenced code block), `RichTextConverter` (`.rtf`/`.html`/`.htm`), `PDFConverter` (`.pdf`), `ImageConverter` (`.png`/`.jpg`/`.jpeg`/`.heic`/`.tiff`), `BroadConverter` (`.docx`/`.odt`/`.pptx`/`.xlsx`/`.xls`/`.epub`/`.ipynb`).
- **`Services/MarkdownWriter.swift`** — `replaceItemAt` atomic write through a `.<UUID>.tmp.md` staging name. Slug generation, frontmatter generation, file-naming rules.
- **`Services/DuplicateDetector.swift`** — content-hash check.
- **`Services/ImportQueue.swift`** — `actor`-style async serialization, security-scoped bookmark handling for `raw/`, validates file size against a configurable limit.
- **`Services/RecentActivityStore.swift`** — local-process activity log shown in `MainCaptureView`.

What it lacks against [`capture/spec.md`](../../specs/capture/spec.md):

1. Menubar drop affordance — currently a click-then-drop interaction (the `MenuBarExtra` opens a window containing the `DropZoneView`).
2. URL drops — `ImportQueue.processOneSynchronously` returns failure on `!url.isFileURL`.
3. Clipboard screenshot import — no path.
4. Unsupported-type *user-facing* notification — the failure flows into `RecentActivityStore` but no `UNUserNotification` fires.
5. Sidecar audit log + dashboard visibility — `MarkdownWriter.write(...)` returns the new filename and the result lands in the Helper.app's local `RecentActivityStore`, but no `POST /captures` is sent. The sidecar's `captures` table sees zero rows from real captures.
6. Three spec-listed formats not in the registry: `.eml`/`.mbox`, `.webp`, `.doc`.

The sidecar side is small:

- **`src/api/captures.rs`** — `GET /captures` (list) + `POST /captures` (create with `{ raw_path, original_kind, source }`). The POST inserts a row in `captures` and writes one `audit_log` entry.
- **`src/db/migrations/`** — schema is at version 3 (`0001_initial`, `0002_raw_inbox`, `0003_inbox_currently_checked`). The next migration is `0004_capture_metadata`.

The web side is mostly there: [`renderCaptures`](../../../jakeos-web/src/sections.js) renders one row per capture with filename + kind + date.

## Goals / Non-Goals

**Goals:**

1. Make the existing Swift capture pipeline visible from the dashboard. After this change, every Helper.app capture appears in the dashboard's "Recent captures" section within one sync cycle and creates a sidecar audit-log entry.
2. Close the gaps in the spec coverage: menubar drop, URL drops, clipboard screenshots, unsupported-type notification, `.eml`/`.mbox` / `.webp` formats.
3. Preserve the local-only-capability fallback. Even if the sidecar is unreachable, captures land on disk; the sidecar registration retries on next launch via a small persisted queue.
4. Stay inside the architecture decision: no Rust converters, no multipart upload, no parallel pipeline. The sidecar is the audit + dashboard registration layer, not the conversion engine.
5. Keep the spec scope honest. `.doc` (Word 97-2003 binary) is hard to parse natively in Swift without a third-party lib; defer to a follow-up.

**Non-Goals:**

- Rust-side conversion pipeline. Resolved by AskUserQuestion in proposal phase: option B chosen.
- Multipart `POST /capture` accepting file bytes. Out of scope; the file is already on disk in `raw/` before the sidecar hears about it.
- Real-time progress streaming for long captures. The Swift `MainCaptureView` already shows `appState.importQueueBusy`; no need for SSE / WebSocket plumbing.
- Re-architecting the Helper.app's local `RecentActivityStore`. It stays as the in-app activity log; the sidecar's `captures` table is the cross-surface authoritative log.
- Replacing the existing wiki-ingest pipeline. Capture writes to `raw/`; ingest pulls from `raw/` to `wiki/` (per [`ingest/spec.md`](../../specs/ingest/spec.md)). Captures hitting `raw/` will be picked up by the FSEvents watcher exactly like any other file appearing there.
- macOS Continuity Camera as a third input. Listed in the existing `capture/spec.md` "Open implementation details" as deferred.

## Decisions

### Decision 1: Menubar drop wiring

**Choice:** Replace the current `MenuBarExtra` body with a small wrapper view that has its own `onDrop(of: [.fileURL, .url, .image])` modifier *outside* the normal popover flow. Drag-over the menubar icon expands a tiny drop overlay (system-managed via `NSStatusItem`'s drag-monitoring); release fires the import without first opening the popover window.

**Why:** Spec requires "no modal dialog for the common case" and "starts within 200ms". The current click-then-drop flow forces a window to open first. SwiftUI's `MenuBarExtra` doesn't natively expose drop registration on the icon, but the underlying `NSStatusItem` accepts `registerForDraggedTypes(...)` via an `NSObject` subclass attached as a window controller. Implementation: a small `MenuBarDropTarget` `NSObject` is created in `SecondBrainHelperApp.applicationDidFinishLaunching` (via an `NSApplicationDelegateAdaptor`), registers the drag types, and forwards drops to `appState.importQueue.process(urls:)`.

**Alternatives considered:**

- *Keep click-then-drop.* Rejected: violates "no modal dialog for the common case".
- *Use a dock icon drop target instead of menubar.* Rejected: the user's prompt explicitly listed menubar; the dock icon is also less reliable since the app isn't always in the dock.

### Decision 2: URL drops — Swift-side fetch + minimal readability extraction

**Choice:** A new `Services/UrlImporter.swift` (or extension on `ImportQueue` for non-file-URL drops) does:

1. `URLSession.data(from:)` with a 15s timeout. Follow redirects.
2. On success: detect `Content-Type`. If `text/html`, run a minimal extraction: `<title>` → frontmatter title; tag-strip `<article>`, fall back to `<main>`, fall back to `<body>`; collapse whitespace; render as paragraphs. Companion `.md` is `<host>-<slugified-title>--<short-hash>.companion.md`.
3. On non-HTML: write the response bytes to `raw/<host>-<short-hash>.<inferred-ext>` and let the existing `ConverterRegistry` handle conversion (PDF served from a URL, image from a URL, etc.).
4. On `4xx`/`5xx` or network error: surface a `UNUserNotification` per spec, no files written.

**Why:** A full readability port (Mozilla's Readability.js heuristic) is a serious lift in Swift. For v1, a `<title>` + `<article>`/`<main>`/`<body>` strip is 90% of the value at 5% of the cost. We can swap in a real readability lib (e.g., `swift-readability` if/when one exists) in a follow-up.

**Alternatives considered:**

- *Use the sidecar for URL fetching (option C from the propose phase).* Rejected: AskUserQuestion answered "B — wire existing Swift" which keeps everything Swift-side. Adding a sidecar URL endpoint just for this one path splits the architecture across two seams.
- *Use a third-party Swift readability lib.* Deferred: vet libs in a follow-up. The naive extractor is good enough to ship.

### Decision 3: Clipboard screenshot import — hotkey-bound action

**Choice:** A new `Services/ClipboardImporter.swift` reads `NSPasteboard.general.image()`. If non-nil: write the image bytes to `raw/clip-<yyyy-mm-dd-HHmm>.png`, run the existing `ImageConverter` to make a companion, register with the sidecar. Invocation: a "Capture from clipboard" button in the menubar window, plus an optional global hotkey wired in `SettingsView`.

**Why:** The spec lists "screenshots from macOS clipboard" as a v1 input but is silent on the trigger. A button + a settings-configurable hotkey covers both the discoverable and the power-user path without needing a system-wide keyboard listener at launch.

**Alternatives considered:**

- *Auto-watch the pasteboard.* Rejected: noisy (every screenshot would import even when not desired) and battery-hostile.
- *Drag-from-Preview into the drop zone.* Already supported by the existing drop target — no extra work needed; the clipboard path is for cases where the screenshot is on the pasteboard but not yet a file.

### Decision 4: Sidecar `POST /captures` payload — additive, backward-compatible

**Choice:** Extend `CreateBody` in [`src/api/captures.rs`](Documents/Second-brain-helper-app/sidecar/src/api/captures.rs):

```rust
pub struct CreateBody {
    pub raw_path: String,
    pub original_kind: String,
    pub source: Option<String>,
    // New, optional, additive:
    pub filename: Option<String>,
    pub mime_type: Option<String>,
    pub size_bytes: Option<i64>,
    pub sha256: Option<String>,
    pub companion_path: Option<String>,
    pub captured_at: Option<String>, // RFC 3339; defaults to server now()
}
```

Response shape gains `is_duplicate: bool`. When the request's `sha256` matches an existing row, the handler returns `200` with the existing capture and `is_duplicate: true` rather than inserting.

**Why:** Additive fields preserve any existing client (notably the local-smoke-test path the test suite already uses). Duplicate detection on the sidecar side mirrors the Helper.app's `DuplicateDetector` so a future surface (e.g., the dashboard's Cowork input writing to captures, or a CLI capture tool) can't accidentally produce duplicates.

**Alternatives considered:**

- *New endpoint `POST /captures/v2` instead of extending.* Rejected: no breaking change, additive fields are fine.
- *Compute `sha256` server-side from `raw_path`.* Rejected: requires a file read per request, races with FSEvents, and Helper.app already has the hash from `MarkdownWriter`'s pre-write step. Send it with the registration.

### Decision 5: Helper.app pending-sync queue — file-backed JSON

**Choice:** A new `Services/PendingSyncQueue.swift` keeps a small JSON file at `~/Library/Application Support/SecondBrainHelper/pending-syncs.json`. Each entry: `{ raw_path, original_kind, filename, mime_type, size_bytes, sha256, companion_path, captured_at }`. On every successful local capture, the entry is appended. The Helper.app drains the queue via `POST /captures` whenever the sidecar is reachable, removing entries on `200`. On launch, the queue is replayed.

**Why:** Captures must succeed locally even when the sidecar is unreachable (per `capture/spec.md` "Local-only credentials"). The queue makes the registration eventually-consistent without putting it in the user's hot path. Bounded growth: at v1 the queue caps at 1000 entries; older entries spill to disk-only with a one-line "captured locally; not yet visible on dashboard" annotation in the local `RecentActivityStore`.

**Alternatives considered:**

- *Skip the queue, retry on next launch only.* Rejected: a Mac that's online but the sidecar is briefly down (during `cargo build --release`) would lose the registration until the user manually relaunches.
- *Persist in `UserDefaults`.* Rejected: `UserDefaults` is fine for tiny config but not the right tool for an unbounded-ish queue. JSON file is simpler to reason about.
- *Persist in the existing sidecar database via direct sqlite.* Rejected: that'd put two writers on the sidecar's SQLite (Rust process + Swift process) which violates the data-contract's "sidecar is source of truth" model.

### Decision 6: Sidecar duplicate detection — hash-only, not path

**Choice:** When `POST /captures` arrives with a `sha256` that already exists in the `captures` table, treat it as a duplicate regardless of `raw_path`. Return the existing capture id + `is_duplicate: true`. The audit log records a `duplicate-skipped` action with the *new* request's metadata so the trail is preserved.

**Why:** The spec's "duplicate, skipped" scenario is clear about content equality, not path equality. If Jake drops the same PDF twice with two different filenames (e.g., renamed in Finder before the second drop), both should still be recognized as duplicates. The path-disambiguation rule (`<stem>--<short-hash>.<ext>`) is for the *different content, same filename* case — the inverse — and is handled Swift-side in `MarkdownWriter.uniqueFilename`.

**Alternatives considered:**

- *Match on filename + hash.* Rejected: changes the meaning of "duplicate" from content-equal to identity-equal, conflicts with the spec.
- *Skip server-side detection entirely; trust Swift.* Rejected: the sidecar must remain the source of truth for the `captures` audit log even if a non-Swift surface posts in the future.

### Decision 7: Web row enrichment — graceful degradation when fields are null

**Choice:** [`renderCaptures`](Documents/jakeos-web/src/sections.js:424) renders the new fields only when present:

- `filename` falls back to `c.raw_path.split('/').pop()` (current behavior).
- `mime_type` shown next to `original_kind` if both exist; otherwise just `original_kind`.
- `size_bytes` formatted humanly (`human(n)` helper); omitted if null.
- `companion_path` becomes a clickable link to the wiki page if present; otherwise just the text.

**Why:** The migration leaves the columns nullable, so old rows return `null` for the new fields. Graceful degradation lets the dashboard ship before the sidecar binary is rebuilt with the migration applied — and lets the existing `Capture` Rust struct stay backward-compatible.

**Alternatives considered:**

- *Backfill old rows with synthetic values.* Rejected: pre-existing rows are seed/test data; backfilling them adds risk for no value.

## Risks / Trade-offs

- **Menubar drop on the bare `NSStatusItem` is finicky.** SwiftUI's `MenuBarExtra` doesn't expose the underlying status item cleanly. The `NSApplicationDelegateAdaptor` approach is documented but has gotchas (the status item's button view needs to register drag types early enough). *Mitigation:* implement first as a "click to open popover, drop inside" flow if the bare-icon drop is brittle, then improve in a follow-up. Document in tasks.md.

- **Naive readability extractor will produce mediocre markdown for some sites.** Tag-stripping `<article>` / `<main>` works for canonical news/blog pages but bombs on JS-heavy SPAs and pages without semantic landmarks. *Mitigation:* always preserve the source URL in frontmatter so Jake can re-fetch with a better tool later. Companion `.md` opens with a clear "v1 readability — re-fetch may improve" note when extraction was thin (< 500 chars).

- **`.eml`/`.mbox` parsing in pure Swift is non-trivial.** v1 covers the common single-message `.eml` case (RFC 5322 headers + body) by hand-rolling a minimal parser; `.mbox` is multi-message and harder. *Mitigation:* `.eml` ships in this change; `.mbox` is gated on the parser being able to handle it cleanly — if not, surfaces as `unsupported` with a hint.

- **Pending-sync queue can grow unbounded if the sidecar stays down for a long time.** *Mitigation:* cap at 1000 entries (older entries logged-but-not-queued); add a "queue depth" surface to the local `RecentActivityStore` so the user knows.

- **Helper.app must rebuild to land this change.** Sidecar reload is automated (`cargo build --release` + `launchctl kickstart` per the project memory note), but the Helper.app is built via Xcode and signed for the local machine. *Mitigation:* the Helper.app build is the user's responsibility on this Mac; tasks.md flags it as a manual step.

- **Backward-compatible payload extension.** The existing `POST /captures` consumers (a handful of seed test calls in the sidecar's smoke-test scripts, if any) will continue to work because all new fields are `Option<>`. *Mitigation:* none needed; this is a feature, not a risk.

- **Race between Helper.app's `MarkdownWriter` (writes to `raw/`) and the FSEvents watcher (reads from `raw/`).** The watcher already debounces 1500ms and uses content-hash diffing, so a partial write would not trigger a spurious ingest cycle. *Mitigation:* the existing atomic `replaceItemAt` keeps the watcher honest. No new work needed.

## Migration Plan

1. **Sidecar first.** Land `0004_capture_metadata.sql`, the `CreateBody` extension, the duplicate-detection branch, the audit-log payload enrichment. Build with `cargo build --release` and reload via `launchctl kickstart`. Verify with a synthetic POST + `sqlite3` peek that the new columns are populated.
2. **Helper.app second.** Add the menubar drop wrapper, URL importer, clipboard importer, `.eml` and `.webp` converters, pending-sync queue, sidecar client, unsupported-type notification. Build in Xcode, archive, copy to `~/Applications` (or wherever the LaunchAgent points), relaunch.
3. **Web third.** Enrich `renderCaptures` with the new fields. Build + push the multi-arch image; UnRAID stack pull + bring up.
4. End-to-end verification per `tasks.md`: drop a PDF, watch it land in `raw/`, the dashboard's "Recent captures" updates, a `captures` row exists with the new metadata, the FSEvents watcher's ingest indicator increments. Drop the same PDF again — duplicate path. Drop a URL — readability extraction. Drop an unsupported type — notification, no files written.

**Rollback:**

- Sidecar: the migration is additive (nullable columns); rolling back to a binary that doesn't know the columns is fine — they're ignored. The duplicate-detection branch is gated on `sha256.is_some()`; old clients that don't send `sha256` skip the branch.
- Helper.app: previous build copy in Time Machine; manual reinstall. The pending-sync queue file at `~/Library/Application Support/SecondBrainHelper/pending-syncs.json` is harmless if left around.
- Web: re-tag previous `:latest` digest, `./unraid.sh up`. The renderer's graceful-degradation logic means old + new payloads both render.

## Open Questions

- **Bare-icon menubar drop vs. popover drop.** Whichever proves more reliable on macOS 26.0 wins. Decided during apply (Phase 1 of tasks.md).
- **`.mbox` parser scope.** If the v1 hand-rolled parser handles single-message `.mbox` cleanly, ship it; otherwise mark `.mbox` as unsupported v1.
- **Hotkey for clipboard import.** Not configured by default in v1 — user enables in `SettingsView`. The default hotkey, if any, is decided at apply.
- **Companion-link click target on the dashboard.** Today the wiki-path → web-link mapping isn't standardized. v1 renders the path as plaintext if no obvious URL exists; a follow-up change can add the wiki-served-from-jakeos-web path mapping.
- **Should the sidecar push a server-sent event when a capture lands?** Out of scope for v1 (the existing 15s poll catches it). Captured here so it doesn't get lost.
