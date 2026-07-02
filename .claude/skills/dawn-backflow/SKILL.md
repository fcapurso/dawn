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

Backflow now performs a **direction-aware 3-way reconcile** of the config files (see
`docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md`):

- **staging-ahead** settings (you changed them in staging's preview theme) are **kept** and will
  promote to `current`.
- **current-ahead** settings (edited in the live theme editor) are **folded** into staging's
  snapshot.
- **collisions** (both sides changed the same setting differently) stop for your decision.

### Exit 0 — reconciled (or nothing to do)

The config snapshot at the tip of `staging` was amended with the merged result (or left unchanged
if only staging-ahead values existed). Confirm with the user which settings were folded.

### Exit 10 — guard triggered

Report the guard message from stderr. Common causes:

- **Dirty working tree** — commit or stash local changes first, then re-run.
- **Staging tip is not the config snapshot** — the commit ordering is wrong; the config snapshot must be at the tip of `staging` before backflow can amend it. Fix the branch ordering first.

### Exit 21 — decisions or classification needed

Two possible causes:

1. **Config collisions.** The script prints each colliding `file → path` with its base / staging /
   current values. For each, ask the operator via `AskUserQuestion`:

   | Option | Meaning |
   |---|---|
   | **Keep staging** | staging's value wins (promotes to current) |
   | **Take current** | fold the live edit into staging |
   | **Enter a value** | supply a replacement (follow-up open-text; parsed as JSON when valid) |

   Write the answers to a decisions TSV — one line per collision:
   `<file>\t<path-json>\t<staging|current|value:JSON>` — then re-run:

   ```bash
   bash .claude/skills/dawn-backflow/backflow.sh --decisions /tmp/decisions.tsv
   ```

2. **Current-ahead non-config files.** Classify each per the table below (enrichment → own L2
   commit; generic → `dawn-harvest`; churn → ignore), then re-run.

| Classification | Action |
|---|---|
| **Enrichment** (L2 store-specific logic or content) | Create its own L2 commit on `staging` per conventions §4 Case B |
| **Generic L1 improvement** (something all Dawn stores would want) | Use the `dawn-harvest` skill to pull it into the `customizations` layer |
| **Churn / noise** (reverted, irrelevant, or already present) | Ignore — no action needed |
