# JakeOS

Spec home for the combined product: **Second Brain Helper** (macOS app) and the **JakeOS dashboard** (jakehallman.com/jakeos).

This repo holds specs, change proposals, and architecture decisions. Implementation lives in the two child repos:

| Surface | Repo | Path |
|---|---|---|
| macOS app | `Second-brain-helper-app` | `~/Documents/Second-brain-helper-app` |
| Web dashboard | `New_Jakehallman_site` (jakehallman.com/jakeos route) | `~/Documents/New_Jakehallman_site` |

## How specs flow

1. New work starts as an **OpenSpec change proposal** — `/opsx:propose <description>` in this repo.
2. The proposal generates `openspec/changes/<change-name>/` with `proposal.md`, `design.md`, `tasks.md`.
3. When the change is approved, it updates the long-lived specs in `openspec/specs/`.
4. Implementation happens in the child repo(s); commits there reference the change name.
5. When complete, `/opsx:archive <change-name>` moves the change out of active.

## Cross-repo code search

Use Semble for fast semantic search across both child repos:

```bash
semble search "auth flow" ~/Documents/Second-brain-helper-app
semble search "blog routing" ~/Documents/New_Jakehallman_site
```

## Why this lives separate

The product is the *combination*. Neither child repo owns the contract between them, and duplicating cross-cutting specs into both was the alternative we rejected.
