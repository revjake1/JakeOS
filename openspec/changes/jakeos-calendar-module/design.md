## Context

Phase 3.1 left calendar at a stub: `GET /calendar/upcoming` on the sidecar returns `{ items: [], oauth_wired: false }` regardless of caller, and `renderCalendar` in `jakeos-web` renders a flat empty `<ul>` with a muted "OAuth not wired" hint. The contract for the real surface already exists:

- **auth/spec.md** mandates a single Google OAuth grant carrying `https://www.googleapis.com/auth/calendar.readonly` (configured in oauth2-proxy).
- **dashboard/spec.md** "Sectioned layout" lists "calendar (today + condensed upcoming)" as one of the required sections, but doesn't yet define what *today* and *condensed upcoming* mean as testable requirements. This change adds that requirement.
- **data-contract/spec.md** "API surface" lists "upcoming calendar" as a required read endpoint and requires auth enforcement per `auth/spec.md`.
- **`jakeos-web/src/sidecar.js`** already forwards the user's access token as `X-Google-Access-Token` on every request (`headers['x-google-access-token'] = accessToken` at sidecar.js:35).
- **`jakeos-web/src/server.js`** already pulls `id.accessToken` from the authenticated identity and passes it into `renderCalendar` at server.js:58.
- **`Second-brain-helper-app/sidecar/src/api/calendar.rs`** is the only file in the sidecar that needs to change for reads; ~120 lines, the `upcoming()` handler is 7 lines.

The dashboard's calendar card polls `/sections/calendar` every 60s (per the cadence locked in `jakeos-dashboard-v1` Phase 3.1.4). Google Calendar's free quota is 1,000,000 queries/day per project and 60 queries/user/100s — neither is at risk, but per-poll calls are wasteful when the data changes much less often than that.

This change is the calendar analog of `jakeos-todos-module`: small, scoped, single-section, with one new requirement in `dashboard/spec.md`. No new endpoints, no new env vars, no schema changes.

## Goals / Non-Goals

**Goals:**

1. Real Google Calendar reads from the sidecar's `/calendar/upcoming` endpoint, gated on the `X-Google-Access-Token` header forwarded from oauth2-proxy through jakeos-web.
2. Today's events render prominently on the dashboard's calendar card; the next 7 days render condensed under day headings.
3. Read-only: no event creation, no "add to calendar" UI in this change. (The existing `POST /calendar/from-email` audit-queue path is unaffected.)
4. Graceful behavior on missing token, expired token, scope rejection, and Google API errors: dashboard always renders something coherent; offline cache still applies.
5. Costless polling: a 10s in-memory TTL on the sidecar means the 60s dashboard cadence costs the user one Google API call per minute, not six.

**Non-Goals:**

- No event creation, editing, or deletion UI. The "add this email as event prompt path stubbed" subclause of task 4.3 is already covered by the existing audit-queue path (`POST /calendar/from-email`) and is not changed here.
- No support for multiple calendars in v1 — primary calendar only. (Most of Jake's events live there. Multi-calendar can be a follow-up if needed.)
- No recurring-event expansion logic in jakeos-web — `singleEvents=true` on the Google API side means each occurrence comes back as its own item, so the dashboard renders them flat.
- No timezone selector. Events render in the timezone Google Calendar returns; the dashboard's "today" boundary uses Jake's local timezone (`America/New_York`) since the server is UTC.
- No iCalendar export, no external sharing, no read-from-cache-only mode for testing. v1 ships against the real API.
- No telemetry on Google API latency, cache hit rate, etc. If we want it later, it goes through the audit log or `tracing`.

## Decisions

### Decision 1: Google call lives in the sidecar, not the web app

**Choice:** The Rust sidecar makes the outbound HTTPS call to `https://www.googleapis.com/calendar/v3/calendars/primary/events`. The web app forwards the access token, the sidecar uses it, and the dashboard sees the same `{ items, oauth_wired }` shape it already renders against.

**Why:** `data-contract/spec.md` makes the sidecar the source of truth for cached email/calendar state. Putting the Google call there keeps the rule consistent: anywhere the dashboard reads "JakeOS data" it reads from the sidecar. It also gives the sidecar a place to apply the per-user/per-day cache (Decision 4) without the web app needing its own state. And it means the audit log can capture failures consistently with everything else.

**Alternatives considered:**

- *Call Google from `jakeos-web` directly.* Rejected: splits the source-of-truth rule (web reads Google directly for calendar but reads the sidecar for everything else), and pushes caching/rate-limiting into a process that's already supposed to be a thin renderer. Also makes the offline story worse — when the sidecar is unreachable, the dashboard could still show calendar data and silently diverge from todos/captures, which is exactly the inconsistency the offline banner is meant to prevent.
- *Have a dedicated calendar microservice.* Rejected: overbuilt for v1. The sidecar already exists and already owns the contract.

### Decision 2: `X-Google-Access-Token` is request-scoped, not stored

**Choice:** The sidecar reads the access token from the inbound `X-Google-Access-Token` header on each request, uses it for the outbound Google call, and never persists it. No keychain write, no DB column, no log line containing the token.

**Why:** `auth/spec.md` "Secret storage" requires server-side secrets to live in secure storage and never appear in repo files, logs, or browser state. The simplest way to honor that is to not store it at all on the sidecar side — the token is already in oauth2-proxy's session cookie (encrypted) and is forwarded per-request. The sidecar treats it as a bearer credential it borrows for the duration of one request.

**Implications:** When the dashboard is offline (no caller), the sidecar can't refresh calendar data on its own. That's fine — the sidecar's job is to serve the dashboard; if no dashboard is talking to it, there's nothing to render. The 10s sidecar cache (Decision 4) still serves whatever the most recent caller fetched, which means a quick reload by Jake gets cache-warm data without a Google round-trip.

**Alternatives considered:**

- *Store the access token in the sidecar's keychain so calendar reads can run on a sidecar-internal schedule.* Rejected: violates the "request-scoped trust" model that oauth2-proxy already establishes and adds a token-refresh problem we don't have. Also conflicts with `auth/spec.md`'s "Reuse OAuth grant" requirement, which scopes the grant to the dashboard session, not to the sidecar.

### Decision 3: Time window = `now` to `now + 7 days`, expanded recurring events

**Choice:** Call `events.list` with `timeMin = now (RFC3339)`, `timeMax = now + 7 days`, `singleEvents = true`, `orderBy = startTime`, `maxResults = 50`. Primary calendar (`calendars/primary/events`).

**Why:** Matches the proposal: "Read primary calendar, today + 7 days." `singleEvents=true` expands recurring events into instances so the dashboard renders flat rows without recurrence logic. `orderBy=startTime` is required when `singleEvents=true`. `maxResults=50` is plenty — a normal week has < 30 events; capping prevents pathological calendars from blowing the response.

**Alternatives considered:**

- *`timeMin = start-of-today` instead of `now`.* Rejected: events earlier today that already happened aren't useful on a "what's coming" surface. If Jake's reading the dashboard at 3pm, he doesn't need the 9am standup. The dashboard's "today" partition is computed below using `start-of-today`, but the *fetch* window is from now forward.
- *Two windows: today + 7 days = two API calls.* Rejected: Google's free-tier quota is generous, but two calls per cache miss for no benefit. One call returns everything; the dashboard splits it into two regions client-side.

### Decision 4: 10-second in-memory TTL cache on the sidecar, keyed by token-hash

**Choice:** Wrap the Google call in a tokio `RwLock<HashMap<TokenHash, (Instant, UpcomingResponse)>>`. Cache key is `blake3(access_token)` (8-byte prefix is enough for our single user). TTL is 10s. On cache hit, return immediately. On cache miss, call Google, store the result, return.

**Why:** Dashboard polls `/sections/calendar` every 60s. Without a sidecar-side cache, every poll is a Google round-trip even though the data hasn't changed. With a 10s TTL, normal use is ~1 Google call/minute, and a quick reload by Jake (e.g. F5 twice) coalesces into a single Google call. The cache is intentionally lossy on sidecar restart and small (a few entries — one per active token).

**Why blake3 of the token, not the token itself:** keeping the raw token in memory longer than the request is exactly what Decision 2 is trying to avoid. The hash is enough to key the cache, leaks no useful data if memory is dumped, and is fast.

**Why 10s and not 60s:** the dashboard's cadence is 60s, so a 10s TTL means the next poll is always a fresh fetch in steady state. The cache only helps with rapid reloads / multiple section refreshes, which is the shape we want. A 60s TTL would mean Jake can stare at a clearly-stale calendar for nearly a minute after creating an event in Google Calendar; 10s feels live enough.

**Alternatives considered:**

- *No cache.* Rejected: wastes Google quota and adds latency to every poll.
- *Push invalidation via Google Calendar push notifications.* Rejected: requires a public webhook endpoint, channel renewal logic, and is overbuilt for v1's polling frequency.
- *Persist cache to SQLite.* Rejected: 10s TTL means restart-survival is meaningless. In-memory is right.

### Decision 5: Token-missing / scope-rejected → `oauth_wired: false` empty response, no error

**Choice:** Three failure modes, all return `200 OK` with `{ items: [], oauth_wired: false }`:

1. **No `X-Google-Access-Token` header** (e.g. local sidecar testing without oauth2-proxy in front, or a misconfigured deploy). Sidecar logs a `tracing::warn!` and returns the empty stub. Same shape as today.
2. **Google returns 401/403** (token expired, scope revoked, scope insufficient). Sidecar logs a `tracing::warn!` with the status code, returns the empty stub. The dashboard renders "No upcoming events" + the muted "OAuth not wired" hint exactly as it does today, which is honest — the calendar isn't actually wired for *this request*.
3. **Google returns any other 4xx/5xx**, or the call times out. Sidecar logs `tracing::error!` and returns the empty stub. Same surface to the dashboard.

**Why:** The dashboard's existing render path handles `oauth_wired: false` cleanly. Returning an error response from the sidecar would surface a red "Sidecar unreachable" banner in the calendar card, which is misleading — the sidecar *is* reachable; Google isn't. Dropping back to the existing stub is the least surprising behavior.

**Why not propagate Google's error code to the dashboard:** v1 doesn't have a UI for "your token expired, please re-auth" — re-auth happens automatically via oauth2-proxy on the next page load. Showing a transient error in the calendar card adds noise.

**Implications:** A user who has revoked the calendar scope in Google's permissions page sees "No upcoming events" forever. That's fine for v1 — Jake controls his own Google account and won't revoke; if it ever bites him, the sidecar logs make it obvious.

**Alternatives considered:**

- *Return 401 from the sidecar and have the dashboard force a re-auth redirect.* Rejected: oauth2-proxy already handles session refresh; the dashboard shouldn't second-guess it. Adding a re-auth path here introduces a loop risk if Google is genuinely down.
- *Add an `error` field to `UpcomingResponse` and render it in the card.* Rejected: needs a UI for it, which is non-goal in this change.

### Decision 6: Dashboard layout — Today section + grouped Next 7 days, server-rendered HTML

**Choice:** `renderCalendar` produces two `<section>` blocks inside the card body:

```html
<section class="cal-today">
  <h3>Today</h3>
  <ul class="cal-list cal-list-today">
    <li class="cal-event">
      <span class="cal-time">10:00 AM</span>
      <span class="cal-title">…</span>
      <span class="cal-loc">…</span>   <!-- only if location is set -->
    </li>
    …
  </ul>
</section>
<section class="cal-upcoming">
  <h3>Next 7 days</h3>
  <h4 class="cal-day">Tue, May 5</h4>
  <ul class="cal-list cal-list-upcoming">
    <li class="cal-event-condensed">
      <span class="cal-time">2:00 PM</span>
      <span class="cal-title">…</span>
    </li>
    …
  </ul>
  <h4 class="cal-day">Wed, May 6</h4>
  …
</section>
```

The two regions are visually distinct: today gets larger type, full info; next-7 gets one-line rows under date headings.

**Why server-rendered:** matches the rest of jakeos-web. No JS state to debug, HTMX swaps the section body whole on each 60s poll.

**Why split today vs next-7 client-side and not on the sidecar:** the sidecar returns the raw window; the dashboard knows the user's "today" boundary (computed from the system clock at render time), and we don't want the sidecar to bake "today" into its response shape. Keeps the API generic.

**All-day events** render with `<span class="cal-allday">all day</span>` in place of `<span class="cal-time">…</span>`.

**Empty cases:**

- No events at all: render `<p class="empty">No events in the next 7 days.</p>` (mirrors the current empty-state copy, just expanded). If `oauth_wired: false`, append the muted "Google Calendar OAuth not wired in sidecar yet." line — same behavior as today.
- No events today but events later this week: render the "Today" header with `<p class="empty">Nothing today.</p>` followed by the upcoming list. (Affords the user a clear "you have nothing now, but…")
- Events today but nothing more this week: render the today section and omit the upcoming section entirely.

**Alternatives considered:**

- *One unified list with day-separators.* Rejected: doesn't give "today" the prominence the spec requires. The two-region split is what makes today *prominent*.
- *Collapse upcoming days behind a "show more" toggle.* Rejected: the entire 7-day span is supposed to be visible at a glance per the dashboard spec.

### Decision 7: Timezone handling — render in event's own TZ, partition "today" by Jake's local TZ

**Choice:** Google returns event start/end as RFC3339 with timezone offset. The dashboard renders the time in *that* offset (so a 10am Eastern meeting reads `10:00 AM` even if the user is traveling). For the today vs upcoming partition, use Jake's local timezone (`America/New_York`) — events whose start falls within `[start-of-today-NY, end-of-today-NY)` are "today."

**Why:** Matches how Google Calendar's UI behaves and matches user intuition. The server is UTC, so we either hardcode Jake's TZ or carry a tz parameter — `America/New_York` hardcoded is fine for v1 since this is a single-user system. Document the gotcha for future Jake-on-the-road.

**All-day events:** render under the date Google returns (`event.start.date`). Always today if their date matches local-NY today.

**Alternatives considered:**

- *Render every time in NY, even for events scheduled in other zones.* Rejected: misleading when traveling. Google's UI doesn't do this.
- *Take user TZ from a query param or header.* Rejected: overengineered for one user.

### Decision 8: HTMX behavior unchanged — section endpoint returns full body, 60s poll

**Choice:** `GET /sections/calendar` continues to return the full rendered card body. HTMX swap shape is `innerHTML` of `#card-calendar .card-body`, identical to other sections. No new routes, no new triggers, no row-level swaps.

**Why:** Read-only section. No writes means no reason to deviate from the standard pattern. The rest of jakeos-web (todos, emails, captures, etc.) works this way; staying consistent simplifies offline behavior, focus management, and the polling contract.

## Risks / Trade-offs

- **Token leak in sidecar logs** → Mitigation: never log the token, never log full request headers. The blake3-prefix cache key is logged only when needed (cache miss/hit debug). `tracing` filters in deployed sidecar use `info` level by default; `debug` is dev-only.
- **Google API outage** → Mitigation: sidecar returns `oauth_wired: false` empty stub on any non-200; dashboard renders the same friendly empty state. Stale-cache via `sidecar.getCached` on the web side handles the case where the *sidecar itself* is unreachable.
- **Recurring-event explosion** → `singleEvents=true` + `maxResults=50` caps the response. A pathological calendar with > 50 events in 7 days would silently truncate; v1 accepts this (Jake's calendar isn't that dense). If it ever becomes real, we add `pageToken` handling.
- **Timezone drift while traveling** → Decision 7 documents the trade-off: events render in their own TZ, but the today-partition is local-NY. Acceptable for v1; revisit when Jake actually travels and notices.
- **Cache poisoning across users** → Not a risk in v1 — single-user system. The blake3-of-token key would isolate users if multi-user ever happened, so the design doesn't need rework later.
- **Dashboard polls when Mac is asleep** → Already handled: `getCached` returns stale + offline banner. Calendar card behaves like the others.
- **Google quota** → 60s dashboard poll + 10s sidecar TTL = ~1 call/minute = 1,440 calls/day. Free quota is 1,000,000 calls/day/project and 60/user/100s. Three orders of magnitude of headroom.

## Migration Plan

1. **Sidecar branch + impl:** branch off main in `Second-brain-helper-app`. Update `api/calendar.rs::upcoming()` to take the access-token header, call Google, cache 10s. Add `reqwest = { version = "0.12", features = ["json", "rustls-tls"], default-features = false }` to `Cargo.toml` if not already present. Cargo build + test on the Mac.
2. **Local smoke against real Google:** start the sidecar locally with a hand-curl-supplied access token (paste from a fresh oauth2-proxy session) — confirm a real event from Jake's calendar comes back from `curl -H "X-Google-Access-Token: …" http://127.0.0.1:7843/calendar/upcoming`. Confirm the 10s cache works.
3. **Sidecar deploy:** restart the sidecar on the Mac; jakeos-web on UnRAID immediately starts seeing real items.
4. **jakeos-web branch + impl:** branch `jakeos-calendar-module` off `phase-3.1-scaffold` in `~/Documents/jakeos-web`. Rewrite `renderCalendar`, add CSS, no new routes.
5. **Local jakeos-web smoke:** point at the now-real sidecar over Tailscale; load `/sections/calendar`; confirm two-region layout renders.
6. **Build + push image:** `scripts/push-image.sh` produces `ghcr.io/revjake1/jakeos-web:latest` and a `:phase-3.x` tag.
7. **UnRAID stack pull:** `./unraid.sh up` from the Mac.
8. **Verify in browser:** open `https://jakeos.jakehallman.com`, confirm a real event from Jake's calendar appears in the today section.
9. **Mark `4.3 [x]`** in `jakeos-dashboard-v1/tasks.md` and archive this change.

**Rollback:**

- *Sidecar regression:* `git revert` the sidecar commit and rebuild. Dashboard reverts to the empty-stub behavior, which is exactly what shipped before this change.
- *Web regression:* `docker tag` the previous `:phase-3.x` digest as `:latest` and `./unraid.sh up`. Sidecar contract didn't change shape, so old-web still renders against new-sidecar.

## Open Questions

- *Should "today" partitioning move to the sidecar later?* Probably not. Keeping it in the renderer means we don't have to teach the sidecar about user timezone. Revisit only if multiple surfaces (helper.app, mobile) start needing the same partition.
- *Should we audit calendar reads?* `data-contract/spec.md` requires the audit log for *writes*, not reads. Reads stay un-audited, consistent with todos, emails, etc.
- *Multiple calendars (work + personal + shared)?* Out of scope. If/when needed, add a `calendarIds: [...]` field to the response and a small UI grouping. Sidecar would call `events.list` per calendar in parallel.
