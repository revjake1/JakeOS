# Project: JakeOS

## What this is

JakeOS is the combined product surface of two existing codebases:

- **Second Brain Helper** — a native macOS app (Swift, Xcode project, `SDKROOT = macosx`, deployment target 26.0) that lives at `~/Documents/Second-brain-helper-app`. Includes a Rust sidecar binary. Built around capturing and organizing thoughts/notes on the desktop.
- **JakeOS dashboard** — a standalone Node.js + HTMX web app living at `https://jakeos.jakehallman.com`, deployed on Jake's UnRAID home server in a Docker stack (Caddy + oauth2-proxy + cloudflared + the app). Public reachability via Cloudflare Tunnel. Tailscale connects UnRAID to the Mac sidecar. The app code lives in a NEW repo (TBD) — **not** in the existing WordPress repo at `~/Documents/New_Jakehallman_site`.

This umbrella repo (`~/Documents/jakeos`) owns the specs that govern how those two surfaces work and how they interoperate. Code lives in the child repos; specs and design decisions live here.

## Owner

Jake Hallman — jake.hallman@gmail.com

## Status

Greenfield as of 2026-05-01. No specs written yet. OpenSpec 1.3.1 + Semble installed, scaffold in place.

## Constraints worth knowing

- **Legacy repo: New_Jakehallman_site** is a working copy of the WordPress install that powers `jakehallman.com`, hosted at Lithium Hosting. The apex domain stays on Lithium and is **not** in JakeOS's scope. Subdomain `jakeos.jakehallman.com` lives entirely on UnRAID.
- **Child repo: Second-brain-helper-app** is a macOS Xcode project with a Rust sidecar; build/test runs through Xcode, not from CI yet.
- This is a personal product, not a team product. Process should optimize for one person moving fast, not for coordination.

## Conventions

- Spec names and change names are **kebab-case**.
- Changes that span both child repos should call out which surface(s) they touch in `proposal.md`.
- Implementation commits in child repos should reference the change name (e.g. `feat(brain-app): notes-sync-protocol — see jakeos change notes-sync-protocol`).

## How to find things

- Specs (long-lived): `openspec/specs/`
- Active changes: `openspec/changes/`
- Archived changes: `openspec/changes/archive/`
- Cross-repo code search: `semble search "<query>" ~/Documents/Second-brain-helper-app` or `~/Documents/New_Jakehallman_site`

## Open questions

- ~~Naming for the public-facing dashboard route — sticking with `/jakeos` or rebranding?~~ → Resolved 2026-05-01: subdomain `jakeos.jakehallman.com` (not a path under apex). Keeps WordPress hosting (Lithium) and JakeOS hosting (UnRAID) fully separated.
- Whether the iOS app and the web dashboard share a backend (and if so, where it lives) — undecided.
- Auth model between app and dashboard — undecided.

These belong in the first round of spec work.
