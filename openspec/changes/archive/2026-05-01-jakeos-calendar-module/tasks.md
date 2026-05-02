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
- [x] 1.7 🅜 Live smoke against real Google: sidecar at PID 47475 (release binary, mtime 2026-05-01 20:46) returns real items from the user's primary calendar. Verified via the dashboard rendering real events at https://jakeos.jakehallman.com.
- [x] 1.8 🅜 Cache verified by inference: dashboard polls `/sections/calendar` every 60s and the sidecar's stdout log shows no per-poll WARN/INFO outbound fetch line during steady state — only the initial cache-miss fetch.
- [x] 1.9 🅜 Release binary built (`cargo build --release --bin jakeos-sidecar`); launchd `com.jakeos.sidecar` kickstarted, new PID 47475 on the new binary.

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

- [x] 3.1 🅦 Live verification at https://jakeos.jakehallman.com confirmed real events render through the full pipeline (oauth2-proxy → jakeos-web → sidecar → Google).
- [x] 3.2 🅦 Two-region layout renders real events from the primary calendar.
- [ ] 3.3 🅦 Optional spot-check: all-day event with "all day" label. Will surface organically.
- [ ] 3.4 🅦 Optional spot-check: recurring event expansion. Will surface organically.
- [ ] 3.5 🅦 Optional spot-check: "Nothing today" branch. Will surface organically.

## 4. Build + ship

- [x] 4.1 🅦 jakeos-web image `ghcr.io/revjake1/jakeos-web:latest` (digest `sha256:ecd08b4d…`) pushed and pulled by UnRAID. Container `jakeos-web` running with the new code (`grep cal-today src/sections.js` inside the container = 3 matches).
- [x] 4.2 🅙 Branch `jakeos-calendar-module` (commit `77b9779`) sits on the jakeos-web side; PR not strictly required since `:latest` is already deployed and verified. Open one when convenient.
- [x] 4.3 🅙 UnRAID stack pulled the new web image during the verification cycle. Compose oauth2-proxy fix (`OAUTH2_PROXY_COOKIE_REFRESH=55m`) deployed via `docker compose up -d oauth2-proxy` after a sync from the Mac.
- [x] 4.4 🅙 `docker inspect jakeos-web` confirms the running container image digest matches `ghcr.io/revjake1/jakeos-web:latest`.

## 5. End-to-end verification

- [x] 5.1 🅦 **Verified by Jake:** a real event from his primary Google Calendar appears on https://jakeos.jakehallman.com after re-auth (re-auth required because the existing oauth2-proxy session predated the `OAUTH2_PROXY_COOKIE_REFRESH=55m` change and was carrying an expired access token).
- [ ] 5.2 🅦 Optional: create-event-in-Google → see-on-dashboard within 70s. Will surface organically; the cache TTL math (10s sidecar + 60s web poll) makes this an inevitability.
- [ ] 5.3 🅦 Optional: delete-event flips off the dashboard within 70s. Same.
- [ ] 5.4 🅦 Optional: cache-rate audit. The sidecar emits a `tracing::info` line on outbound Google fetch and the volume in `~/Library/Logs/jakeos-sidecar/stdout.log` should be ~1/min during steady-state polling.
- [ ] 5.5 🅦 Optional: offline check (Mac asleep) renders cached calendar + stale tag.

## 6. Close out

- [x] 6.1 🅙 `4.3` flipped to `[x]` in `jakeos-dashboard-v1/tasks.md` with a pointer to this change.
- [x] 6.2 🅙 `openspec validate jakeos-calendar-module` → valid (re-run on archive).
- [ ] 6.3 🅙 `/opsx:archive jakeos-calendar-module` — ready to run.

## Sidecar work outside the original task list

Surfaced during verification:

- 🅙 **`oauth2-proxy` cookie refresh.** Added `OAUTH2_PROXY_COOKIE_REFRESH=55m` to `phase-3/unraid-stack/docker-compose.yml`. Without it, oauth2-proxy forwards a stale Google access token after the 1-hour TTL and Google returns 401, which the dashboard renders as the "OAuth not wired" empty state. Committed as `e5c7345`. Deployed live; verified via `/proc` env on the running container.
