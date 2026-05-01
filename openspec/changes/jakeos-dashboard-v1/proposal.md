# jakeos-dashboard-v1 — Proposal

> Umbrella change. Establishes JakeOS as a real product surface across the macOS Second Brain Helper and the jakehallman.com web property, and locks the cross-cutting design decisions before any module work begins.

## Why

Jake has two existing pieces of software that *imply* a system but don't yet form one:

- **Second Brain Helper** — a native macOS app at `~/Documents/Second-brain-helper-app` (Swift + Rust sidecar, `MACOSX_DEPLOYMENT_TARGET = 26.0`) that captures and organizes notes locally.
- **jakehallman.com** — a live WordPress site at `~/Documents/New_Jakehallman_site`, currently part of the job-search surface.

The notes file at `~/Documents/Obsidian Vault/Second brain/In progress/Second brain dashboard "JakeOS" setup notes.md` (22 bullets, captured 2026-05-01) describes a single coherent product on top of those two pieces: a daily dashboard that shows todos, important emails, calendar, job-application status, and contextual briefings, with an LLM-driven self-improvement loop. The product name is JakeOS.

There's no spec for any of this yet. There's also a real architecture choice that has to be made before code gets written and a real terminology mismatch in the existing project.md that has to be resolved (the helper app is macOS, not iOS — corrected in this change).

This proposal exists to:

1. Capture the v1 scope so the 22 bullets stop being a loose note and become tracked work.
2. Force the URL-vs-standalone-app decision into a real OpenSpec design step rather than letting it drift.
3. Establish the cross-surface contracts (auth, data flow, deploy, identity) that every later change will depend on.

## What

The v1 scope is the **whole dashboard** as captured in the source notes, treated as one change because the modules share auth, layout, data, and a self-improvement loop and won't ship usefully in isolation. Sub-changes (todos, email triage, calendar correlation, employment tracker, briefings, self-loop) will follow this one and will each cite this change as their parent.

### In-scope capabilities (v1)

The dashboard must support, at the spec level:

1. **Todos surface** — show open todos from the source-of-truth (Second Brain Helper or its sync target), checkable / completable from the dashboard, with bidirectional state.
2. **Todo enrichment** — on demand, pull additional context for a todo and (when relevant) propose a calendar event for it.
3. **Daily staleness sweep** — a scheduled pass that flags clearly-stale facts for removal and queues ambiguous ones for Jake's confirmation.
4. **Important email surface** — show recently-arrived emails that look important; learn what counts as important over time per Jake's signals.
5. **Employment section** — list outstanding job applications with status (pulled from email + tracker), drop rejected ones, highlight items needing follow-up. Cross-references `~/.claude/skills/job-applier/state/APPLICATION_TRACKER.md`.
6. **Calendar surface** — current day prominent, upcoming days condensed; pull additional context for events; correlate emails with events.
7. **Email-to-calendar prompt** — when an email implies a calendar event, prompt Jake to add it.
8. **Cowork input** — a persistent input at the bottom of the dashboard for adding todos, capturing ideas, or asking questions. Routes to Cowork.
9. **Contextual briefings** — when an email or event references a topic in the second brain, offer a briefing on that topic.
10. **Self-improvement loop** — once daily, JakeOS reviews the prior day's lessons, proposes refinements to its own skills/configs, and (under a still-to-define safety boundary) reinstalls a newer version of itself.
11. **RAW-folder ingest watcher** — periodically check the second-brain wiki RAW folder; if an ingest cycle is needed, run it per the rules in `~/Documents/Obsidian Vault/Second brain/AGENTS.md`.
12. **Auto-reply option** — for selected email categories, offer an auto-reply path (gated on Jake's approval per category, never blanket).
13. **Dashboard surface** — password-protected web UI; auto-updates as new emails / events / signals arrive.
14. **File-to-markdown capture** — a native macOS drag-and-drop surface (the repurposed Helper.app Swift UI) that accepts dropped files (PDFs, .docx, .eml, images, screenshots) and pasted URLs, converts them to .md with source-metadata frontmatter, and writes them into the wiki's `RAW/` folder for the existing ingest pipeline to pick up. Bridges the gap between "interesting thing I just found" and "captured in the second brain."

### Cross-cutting requirements

- **Token / context efficiency** — every read path must be cheap; design.md establishes the budget.
- **No monolith** — orchestrator skill plus narrowly-scoped subskills, not one large skill. Enforced as testable requirements in `specs/orchestration/spec.md` (size budget, single responsibility, depth limit, weekly drift audit), not just stated as intent.
- **Scripts over LLM calls** when scripts can do the job cheaper.
- **Two surfaces stay in sync** — the macOS helper and the web dashboard must agree on todos, ideas, and ingest state via a single contract defined in design.md.

### Out of scope (explicitly)

- **iOS** — there is no iOS app today and none is committed in v1. (Source notes called the helper app "macbook"; the existing repo confirms macOS, deployment target 26.0.)
- **Public-facing rebrand of `/jakeos`** — the route name is locked to `/jakeos` for v1; rebrand can be a later change.
- **Multi-user / shared access** — JakeOS v1 is single-user (Jake only).
- **Mobile-responsive web UI** — desktop-first; mobile is a follow-up if/when needed.
- **Native iOS / iPadOS clients** — explicitly deferred.

## Open questions (resolved by design.md before /opsx:apply)

These are the foundational calls. design.md will lay out options for each without picking; Jake decides before tasks.md is executed.

1. **Surface architecture** — is JakeOS a WordPress page at `/jakeos`, a standalone web app embedded behind the `/jakeos` route, or a macOS-native dashboard riding the existing Second Brain Helper? (Source-note bullet 20 explicitly asks this.)
2. **Shared backend** — do the two surfaces share a backend, and if so, where does it live (helper-app-as-server, WordPress-as-server, third service, or no shared backend at all)?
3. **Auth model** — how does the dashboard authenticate Jake? WordPress login, separate password, OS-level (Touch ID / Keychain) on the macOS surface, or something else?
4. **Self-improvement-loop safety boundary** — what's the user-confirmation rule for the loop "reinstalling a newer, better version of itself"? Diff + approve, automatic, sandbox-and-test-first, or something else?
5. **Ingest-cycle trigger** — does the RAW-folder watcher run from the macOS helper, from a server-side cron, or from a Cowork scheduled task? (Affects what "context-efficient" means in practice.)

## Affected surfaces

This change spans both child repos:

- `~/Documents/Second-brain-helper-app` (macOS app)
- `~/Documents/New_Jakehallman_site` (WordPress site, `/jakeos` route)

Per the convention in `openspec/project.md`, implementation commits in those repos will reference `jakeos-dashboard-v1`.

## Success criteria for this change

- design.md exists and presents 2–3 architectures side-by-side for each open question, with tradeoffs.
- tasks.md exists and breaks v1 into ordered implementation steps, gated on the architecture call.
- Jake makes the architecture call; the chosen options are recorded in design.md before `/opsx:apply` runs.
- After `/opsx:apply`, no implementation task starts until its prerequisite architecture decisions are checked off.
