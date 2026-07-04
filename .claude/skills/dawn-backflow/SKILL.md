---
name: dawn-backflow
description: Pull live Shopify admin/config edits from the current branch back into staging. Use when the user says backflow, capture admin changes, sync config from live, or before a promote.
---

## Overview

The `dawn-backflow` skill compares config settings across **three sources** — your local `staging`
branch, the live published theme (`origin/current`), and the preview theme (`origin/staging`) — and
asks the operator to choose the target value for every setting where the three sources do not all
agree. Nothing folds automatically; every divergence surfaces as an explicit decision.

## Prerequisites

- Be checked out on the `ops` branch (never on `current`).
- Conventions reference: `.claude/skills/_dawn-ops-lib/conventions.md`

## Running

```bash
bash .claude/skills/dawn-backflow/backflow.sh
```

This is **plan mode** (the default) — fetches both remotes, scans for divergences, prints a
per-key report, then stops for decisions and approval. No lasting commit is made until you re-run
with `--apply --decisions`.

### Exit 0 — nothing to reconcile, or apply completed

Either all three sources agree on every key (nothing to do), or you ran with `--apply` and the
config snapshot at the tip of `staging` now holds the reconciled result.

### Exit 10 — guard triggered

Report the guard message from stderr. Common causes:

- **Dirty working tree** — commit or stash local changes first.
- **Staging tip is not the config snapshot** — fix branch ordering first.
- **`origin/staging` conflicts with local staging** in a non-config file — resolve by hand and
  re-run.
- **`--apply` called without decisions** when divergences exist — run plan mode first.

### Exit 21 — classification needed

`origin/current` has non-config file changes (rare). Classify each per the table:

| Classification | Action |
|---|---|
| **Enrichment** (L2 store-specific logic) | Create its own L2 commit on `staging` |
| **Generic L1 improvement** | Use the `dawn-harvest` skill |
| **Churn / noise** | Ignore |

### Exit 22 — plan ready: per-key decisions needed, then approval

The plan report lists every divergent config key:

```
  <file>  <path-json>
    staging=<val>  origin/current=<val>  origin/staging=<val>
```

**Step 1 — Per-key decisions**

For each key in the report, ask a single `AskUserQuestion` with `multiSelect: false`:

- **Keep staging** `<staging-val>` — no change to staging
- **Take origin/current** `<cur-val>` *(skip if same as another option)*
- **Take origin/staging** `<sr-val>` *(skip if same as another option)*
- **Enter a custom value** — follow-up open-text prompt

If two options have the same value, collapse them into one label (e.g. "Keep staging /
origin/current agree on `<val>`"). Build the decisions TSV at `/tmp/backflow-decisions.tsv`:

```
<file>\t<path-json>\t<staging|current|staging_remote|value:JSON>
```

**Step 2 — Approval gate**

Relay the plan report to the user and ask one `AskUserQuestion` (Approve / Abort). On approval:

```bash
bash .claude/skills/dawn-backflow/backflow.sh --apply --decisions /tmp/backflow-decisions.tsv
```

On abort, stop — nothing was written; `staging` is exactly as it was.
