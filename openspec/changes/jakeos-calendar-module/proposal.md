## Why

Phase 3.1 of [`jakeos-dashboard-v1`](../jakeos-dashboard-v1/proposal.md) shipped the dashboard frame and the todos round-trip ([`jakeos-todos-module`](../archive/2026-05-01-jakeos-todos-module/proposal.md), Phase 4.1). Calendar is the next module on the list (Phase 4.3). Today the calendar card calls the sidecar's `/calendar/upcoming` stub, which always returns an empty list with `oauth_wired: false` — the dashboard renders "No upcoming events" with a muted "OAuth not wired" hint, and that's the entire surface.

The plumbing for a real fetch is already there. `auth/spec.md` requires the dashboard's OAuth grant to carry the Calendar read scope, and oauth2-proxy is configured with `https://www.googleapis.com/auth/calendar.readonly`. `jakeos-web/src/sidecar.js` already forwards the user's Google access token as `X-Google-Access-Token` on every request. The Rust sidecar's `api/calendar.rs` is a single ~120-line file that ignores that header and returns an empty stub. What's missing is: (a) the sidecar reading the header and calling the Google Calendar API for real, and (b) the dashboard rendering today + condensed upcoming as the spec describes. This change closes both ends and ships task 4.3 of `jakeos-dashboard-v1` end-to-end, mirroring the shape of `jakeos-todos-module` — a small scoped follow-up plus a tiny dashboard-spec delta that records what "calendar surface" actually means.

## What Changes

- **Second-brain-helper-app sidecar** `api/calendar.rs` — `GET /calendar/upcoming` reads the `X-Google-Access-Token` header, calls Google Calendar `events.list` against the primary calendar with `timeMin = now`, `timeMax = now + 7 days`, `singleEvents = true`, `orderBy = startTime`. Returns the same `UpcomingResponse` shape (`items`, `oauth_wired`) but with real items and `oauth_wired: true`. Falls back to `oauth_wired: false` + empty list when the header is missing (dashboard not yet authed) or scope is rejected by Google.
- **Second-brain-helper-app sidecar** ten-second in-memory cache per `(access-token-hash, day)` so the dashboard's 60s polling cadence doesn't fan out into one Google API call per poll, and so quick dashboard reloads don't blow Google's per-user quota.
- **Second-brain-helper-app sidecar** the existing audit log entry shape stays put; reads aren't audited, only the existing `POST /calendar/from-email` write path. No schema changes.
- **jakeos-web** `renderCalendar` in `src/sections.js` switches from a flat `<ul>` to a two-region layout: **Today** (prominent, full-width rows showing time + title + location) followed by **Next 7 days** (condensed, one line per event grouped under a date heading). Read-only — no controls in v1.
- **jakeos-web** event time rendering uses Jake's local timezone (America/New_York) since the server is UTC; render with the event's own timezone offset from the Google Calendar response, fall back to UTC display with explicit `Z` suffix when timezone data is absent.
- **jakeos-web** all-day events render distinctly (no time prefix, "all day" label).
- **jakeos-web** offline behavior preserved per existing `sidecar.getCached` pattern: stale cache renders with the existing `staleTag`; section reuses the offline banner for any write controls (none in v1, so this is a no-op for now).
- **dashboard spec** gains one new requirement: "Calendar surface — today and next 7 days" — the dashboard MUST render today's events prominently and the next 7 days condensed, sourced from the user's primary Google Calendar via the sidecar.
- No new sidecar endpoints. No new dashboard routes. No new env vars beyond what's already wired.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `dashboard`: add a "Calendar surface — today and next 7 days" requirement. Refines the existing "Sectioned layout" requirement's calendar mention to specify *what* the calendar section shows. No breaking changes.

## Impact

- **Code**:
  - `~/Documents/Second-brain-helper-app/sidecar/src/api/calendar.rs` — `upcoming()` becomes a real Google Calendar caller; gain a small `google.rs` helper or inline `reqwest` call to `https://www.googleapis.com/calendar/v3/calendars/primary/events`.
  - `~/Documents/Second-brain-helper-app/sidecar/Cargo.toml` — `reqwest` and `serde_json` are likely already pulled in (used by audit / db); confirm during implementation, add only if missing.
  - `~/Documents/jakeos-web/src/sections.js` — `renderCalendar` rewrite for two-region layout.
  - `~/Documents/jakeos-web/src/layout.js` — small CSS additions for today vs upcoming visual hierarchy.
- **APIs**: Sidecar `GET /calendar/upcoming` response shape unchanged (still `{ items, oauth_wired }`); items now populated from Google. No new endpoints.
- **Dependencies**: None expected to be added on jakeos-web. Sidecar may need `reqwest` features bumped for `json` if not already enabled.
- **Systems**: UnRAID stack image updates on next push to `ghcr.io/revjake1/jakeos-web:latest`. Sidecar binary rebuilds and redeploys on the Mac.
- **Tasks completed**: marks `4.3` `[x]` in `jakeos-dashboard-v1/tasks.md` once verified end-to-end. The "add this email as event prompt path stubbed" subclause of 4.3 is already covered by the existing `POST /calendar/from-email` audit-queue path and is not modified by this change.
