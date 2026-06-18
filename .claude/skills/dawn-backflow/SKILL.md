---
name: dawn-backflow
description: Pull live Shopify admin/config edits from the current branch back into staging. Use when the user says backflow, capture admin changes, sync config from live, or before a promote.
---

## Overview

The `dawn-backflow` skill folds live admin/config edits made on `current` back into `staging`'s config-snapshot commit (Case A). If non-config changes are detected, it stops and asks the human to classify each file.

## Prerequisites

- Be checked out on the `ops` branch (never on `current`).
- Conventions reference: `.claude/skills/_dawn-ops-lib/conventions.md`

## Running

```bash
bash .claude/skills/dawn-backflow/backflow.sh
```

## Exit codes and responses

### Exit 0 — success (Case A: config-only)

The config-snapshot commit at the tip of `staging` was amended in place. Commit count is unchanged. Confirm with the user:

> Backflow complete. The config snapshot at the tip of `staging` was amended — still exactly one config commit, now containing the live admin settings.

### Exit 10 — guard triggered

Report the guard message from stderr. Common causes:

- **Dirty working tree** — commit or stash local changes first, then re-run.
- **Staging tip is not the config snapshot** — the commit ordering is wrong; the config snapshot must be at the tip of `staging` before backflow can amend it. Fix the branch ordering first.

### Exit 21 — STOP: non-config changes need classification

The script found files on `current` that are not tracked config paths. **Stop and work through each file with the user before re-running.**

For each listed file, decide:

| Classification | Action |
|---|---|
| **Enrichment** (L2 store-specific logic or content) | Create its own L2 commit on `staging` per conventions §4 Case B |
| **Generic L1 improvement** (something all Dawn stores would want) | Use the `dawn-harvest` skill to pull it into the `customizations` layer |
| **Churn / noise** (reverted, irrelevant, or already present) | Ignore — no action needed |

Once all non-config files are resolved (either committed or confirmed as ignorable), re-run `backflow.sh`. It will proceed with the config amend only if the remaining diff is config-only.
