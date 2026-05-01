# Project: JakeOS

## What this is

JakeOS is the combined product surface of two existing codebases:

- **Second Brain Helper** — a Swift/iOS app that lives at `~/Documents/Second-brain-helper-app`. Native iOS, Xcode project. Built around capturing and organizing thoughts/notes.
- **JakeOS dashboard** — a web dashboard living at `jakehallman.com/jakeos`, implemented in the WordPress repo at `~/Documents/New_Jakehallman_site`.

This umbrella repo (`~/Documents/jakeos`) owns the specs that govern how those two surfaces work and how they interoperate. Code lives in the child repos; specs and design decisions live here.

## Owner

Jake Hallman — jake.hallman@gmail.com

## Status

Greenfield as of 2026-05-01. No specs written yet. OpenSpec 1.3.1 + Semble installed, scaffold in place.

## Constraints worth knowing

- **Child repo: New_Jakehallman_site** is a live WordPress install behind jakehallman.com. The site is part of Jake's job-search surface, so anything that touches public pages needs to ship cleanly.
- **Child repo: Second-brain-helper-app** is an Xcode project; build/test runs through Xcode, not from CI yet.
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

- Naming for the public-facing dashboard route — sticking with `/jakeos` or rebranding?
- Whether the iOS app and the web dashboard share a backend (and if so, where it lives) — undecided.
- Auth model between app and dashboard — undecided.

These belong in the first round of spec work.
