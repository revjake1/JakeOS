# jakeos-calendar-module — Tasks

> Follow-up to `jakeos-dashboard-v1`. Implements task 4.3 of that change end-to-end. Code work spans the Rust sidecar (`Second-brain-helper-app`) and the dashboard (`jakeos-web`).

Repo legend (matches `jakeos-dashboard-v1`):
- 🅙 = `~/Documents/jakeos` (this repo — specs only)
- 🅦 = `~/Documents/jakeos-web` (the dashboard app)
- 🅜 = `~/Documents/Second-brain-helper-app` (Rust sidecar)

Commits in 🅦 and 🅜 must reference `jakeos-calendar-module` per the convention in `openspec/project.md`.

---

## 1. Sidecar — read the access token and call Google

- [x] 1.1 🅜 Branched `jakeos-calendar-module` off main in `~/Documents/Second-brain-helper-app`.
- [x] 1.2 🅜 Added `reqwest = { version = "0.12", default-features = false, features = ["json", "rustls-tls"] }` to `sidecar/Cargo.toml`. `Cargo.lock` will be bumped on first build.
- [x] 1.3 🅜 10s TTL cache implemented inline in `api/calendar.rs` via a `OnceLock<RwLock<HashMap<[u8;8], (Instant, UpcomingResponse)>>>`. Key is the first 8 bytes of `blake3(access_token)`. Opportunistic eviction on every write keeps the map bounded.
- [x] 1.4 🅜 `api/calendar.rs::upcoming(State, HeaderMap)` reads `x-google-access-token`, falls back to the empty stub on missing header, checks the cache, calls `https://www.googleapis.com/calendar/v3/calendars/primary/events` with the documented query (`timeMin`, `timeMax=now+7d`, `singleEvents`, `orderBy`, `maxResults=50`) using `bearer_auth`, parses items into `CalendarEvent { id, summary, start, end, location, html_link, time_zone, all_day }`, returns the empty stub on 401/403/other failure, stores fresh responses in the cache. (Added `time_zone` and `all_day` to the response shape so the dashboard can format times in the event's own timezone and label all-day events; this is additive — old fields unchanged.)
- [x] 1.5 🅜 `POST /calendar/from-email` left intact; `cargo build` confirms it compiles.
- [x] 1.6 🅜 `cargo build --bin jakeos-sidecar` succeeds (5m 21s, no warnings related to the new code).
- [ ] 1.7 🅜 **Jake-side:** local smoke against real Google. Start the sidecar, supply a fresh access token, run:
  ```
  curl -s -H "X-Google-Access-Token: <token>" http://127.0.0.1:7843/calendar/upcoming | jq '.items[0:3]'
  ```
  Confirm a real event from Jake's calendar comes back. (Cannot run from this session — needs an in-band Google access token.)
- [ ] 1.8 🅜 **Jake-side:** rerun the curl twice in < 10s; the second call should be sub-millisecond and produce no `tracing::info` line for an outbound Google fetch.
- [ ] 1.9 🅜 **Jake-side:** push the sidecar branch + restart the running sidecar binary on the Mac so UnRAID's web app starts seeing real items. Sidecar branch already committed: `9f0c9b7` on `jakeos-calendar-module`.

## 2. jakeos-web — render today + next 7 days

- [x] 2.1 🅦 Branched `jakeos-calendar-module` off `phase-3.1-scaffold` in `~/Documents/jakeos-web` (after fast-forwarding local `phase-3.1-scaffold` to origin so the todos-module merge is part of the base).
- [x] 2.2 🅦 `renderCalendar` rewritten in `src/sections.js`: existing `sidecar.getCached('/calendar/upcoming', { accessToken })` call + sidecar-unreachable error path preserved; empty branch keeps the "OAuth not wired" hint when `oauth_wired === false`; non-empty path partitions into Today + Next 7 days regions.
- [x] 2.3 🅦 `localDay(date)` and `eventDay(ev)` helpers use `Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' })` to compute YYYY-MM-DD in local-NY for both `now` and each event's start.
- [x] 2.4 🅦 `formatTime(ev)` renders `event.start.dateTime` in `ev.time_zone` (the offset Google returned), falling back to `America/New_York` if Google omitted it. All-day events render the literal "all day" label via `<span class="cal-allday">`.
- [x] 2.5 🅦 "Next 7 days" rows grouped by event-day; each day gets `<h4 class="cal-day">` heading + `<ul class="cal-list cal-list-upcoming">` with `<li class="cal-event-condensed">` rows.
- [x] 2.6 🅦 Empty-state branches implemented exactly per spec.
- [x] 2.7 🅦 CSS for `.cal-today`, `.cal-list-today`, `.cal-event`, `.cal-upcoming`, `.cal-day`, `.cal-event-condensed`, `.cal-allday` added to `src/layout.js` `BASE_CSS`. Matches the dashboard's existing color tokens (`--accent`, `--muted`, `--border`, `--fg`).
- [x] 2.8 🅦 `staleTag(stale)` is rendered as the first node in every non-error branch of `renderCalendar` (empty + non-empty), so `stale === true` continues to surface a stale tag.

## 3. jakeos-web — local smoke

These items need a live sidecar with an in-band Google access token and a browser. Code already smoke-loads (`node --check` on `sections.js`, `layout.js`, `server.js` is clean; `import('./src/sections.js')` resolves and exposes `renderCalendar`).

- [ ] 3.1 🅦 **Jake-side:** with the real sidecar reachable over Tailscale and oauth2-proxy in front, hit `https://jakeos.jakehallman.com/sections/calendar` (or run jakeos-web locally pointing at the prod sidecar with a hand-supplied `X-Forwarded-Access-Token`).
- [ ] 3.2 🅦 **Jake-side:** confirm the two-region layout renders with at least one real event from Jake's calendar.
- [ ] 3.3 🅦 **Jake-side:** confirm an all-day event renders with the "all day" label.
- [ ] 3.4 🅦 **Jake-side:** spot-check a recurring event: it should appear once per occurrence in the 7-day window.
- [ ] 3.5 🅦 **Jake-side:** spot-check the "no events today" branch (test on a quiet morning); the "Nothing today" empty state should render with the upcoming list still populated.

## 4. Build + ship

These items need Docker + ghcr login + UnRAID `unraid.sh` (only runs from the Mac).

- [ ] 4.1 🅦 **Jake-side:** build + push image with `scripts/push-image.sh`. Capture the resulting digest in the commit message / PR.
- [ ] 4.2 🅙 **Jake-side:** open a PR in `revjake1/jakeos-web` against `phase-3.1-scaffold`, citing `jakeos-calendar-module`. Local branch already contains the implementation commit `77b9779`.
- [ ] 4.3 🅙 **Jake-side:** `./unraid.sh up` from the Mac to pull the new image and bring the stack up.
- [ ] 4.4 🅙 **Jake-side:** confirm the running container is on `:latest` with the expected digest.

## 5. End-to-end verification

- [ ] 5.1 🅦 **Jake-side:** open `https://jakeos.jakehallman.com`. Confirm a real event from the primary Google Calendar appears in the calendar card's "Today" region (or "Next 7 days" if today is empty).
- [ ] 5.2 🅦 **Jake-side:** create a new event in Google Calendar today; wait up to 70s; confirm it appears on the dashboard without any reload of credentials.
- [ ] 5.3 🅦 **Jake-side:** delete that test event in Google Calendar; wait up to 70s; confirm it disappears from the dashboard.
- [ ] 5.4 🅦 **Jake-side:** confirm sidecar logs (Mac) show one Google call per polling cycle, not six (cache working).
- [ ] 5.5 🅦 **Jake-side:** offline check: put the Mac to sleep (or stop the sidecar). Confirm the dashboard renders the cached calendar with the offline banner active and `staleTag` showing on the calendar section.

## 6. Close out

- [x] 6.1 🅙 Marked `4.3` in `jakeos-dashboard-v1/tasks.md` with a pointer to this change. (Final `[x]` flip stays gated on the Jake-side e2e checks 5.1–5.5; the line now reads "implementation in change `jakeos-calendar-module`; e2e verification pending Jake".)
- [x] 6.2 🅙 `openspec validate jakeos-calendar-module` → "Change 'jakeos-calendar-module' is valid".
- [ ] 6.3 🅙 **After e2e verification:** `/opsx:archive jakeos-calendar-module`.
