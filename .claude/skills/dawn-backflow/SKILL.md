---
name: dawn-backflow
description: Pull live Shopify admin/config edits from the current branch back into staging. Use when the user says backflow, capture admin changes, sync config from live, or before a promote.
---

## Overview

The `dawn-backflow` skill folds live admin/config edits into `staging`'s config-snapshot commit
from **two** bot-linked sources: the published theme (`current`) and the staging preview theme
itself (`origin/staging` — Shopify's GitHub integration writes live-editor commits there directly,
same as it does for `current`). It fetches both automatically on every run. If non-config changes
are detected, it stops and asks the human to classify each file. Before committing anything, it
prints a plan report and waits for explicit approval.

## Prerequisites

- Be checked out on the `ops` branch (never on `current`).
- Conventions reference: `.claude/skills/_dawn-ops-lib/conventions.md`

## Running

```bash
bash .claude/skills/dawn-backflow/backflow.sh
```

This is **plan mode** (the default) — it fetches, reconciles, and computes everything, but does not
leave a lasting commit unless you re-run with `--apply`. Backflow performs a **direction-aware
3-way reconcile** (see `docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md` and
`docs/superpowers/specs/2026-07-03-dawn-backflow-staging-drift-and-plan-gate-design.md`) against
both `current` and `origin/staging`:

- **staging-ahead** settings (you changed them in staging's preview theme) are **kept** and will
  promote to `current`.
- **current-ahead** / **origin/staging-ahead** settings (edited live) are **folded** into staging's
  snapshot.
- **collisions** (both sides changed the same setting differently) stop for your decision.
- Non-config drift from `origin/staging` (in practice, locale files) folds via a plain 3-way text
  merge; a genuine conflict there is a guard, not a decision prompt (no per-key UI exists for it).

### Exit 0 — nothing to reconcile, or apply completed

Either there was nothing to fold from any live source (report with the user which case), or you
ran with `--apply` and the config snapshot at the tip of `staging` now holds the reconciled result.

### Exit 10 — guard triggered

Report the guard message from stderr. Common causes:

- **Dirty working tree** — commit or stash local changes first, then re-run.
- **Staging tip is not the config snapshot** — the commit ordering is wrong; fix the branch
  ordering first.
- **`origin/staging` conflicts with local staging** in a non-config file (in practice, a locale
  file edited on the same line both live and locally) — no automated resolution exists for this;
  resolve by hand (e.g. `git merge origin/staging` on a scratch branch) and re-run.

### Exit 21 — decisions or classification needed

Three possible causes, checked in this order — resolve one, re-run, and you'll hit the next if it
also applies:

1. **`origin/staging` config collisions.** Same shape as (3) below, but the "other side" is the
   staging preview theme's live editor instead of the published theme. Ask via `AskUserQuestion`
   with **Keep staging** / **Take origin/staging** / **Enter a value**, write to the same decisions
   TSV, re-run with `--decisions`.
2. **Current-ahead non-config files.** Classify each per the table below (enrichment → own L2
   commit; generic → `dawn-harvest`; churn → ignore), then re-run.

   | Classification | Action |
   |---|---|
   | **Enrichment** (L2 store-specific logic or content) | Create its own L2 commit on `staging` per conventions §4 Case B |
   | **Generic L1 improvement** (something all Dawn stores would want) | Use the `dawn-harvest` skill to pull it into the `customizations` layer |
   | **Churn / noise** (reverted, irrelevant, or already present) | Ignore — no action needed |

3. **Config collisions** (current vs. staging). The script prints each colliding `file → path` with
   its base / staging / current values. For each, ask the operator via `AskUserQuestion`:

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

   > **Note:** `staging` is also accepted for other-ahead (`current_ahead`) keys in the decisions
   > file — this pins the key to staging's value instead of taking the live edit. The plan report
   > (exit 22) lists all other-ahead keys with their per-key values to make it easy to identify which
   > paths to pin.

### Exit 22 — plan ready, needs approval

Every collision and classification above is resolved. The script printed a plan report to stdout
listing what it will fold from `origin/staging` and from `current`, including **per-key detail
lines** in the form:

```
    <file>  <path>  staging=<val> → <remote>=<val>
```

Handle exit 22 in two steps:

**Step 1 — Per-key rejection (only if other-ahead keys exist in the plan output)**

Scan the plan output for per-key detail lines. If any are present, ask a single `AskUserQuestion`
with `multiSelect: true`:

- **Question:** "Which of these live edits do you want to REJECT (keep staging's value instead of folding)?"
- **Options:** one per key — label = the path (e.g. `["col"]`), description = `<file>  staging=<val> → <val>`
- Unchecked = fold normally (default). Checked = pin that key to staging's value.

For each checked key, write one TSV line to `/tmp/backflow-decisions.tsv`:

```
<file>\t<path-json>\tstaging
```

If a `--decisions` file was already in use (from a prior collision-resolution run), append to it
rather than creating a new file. If no keys are checked, skip this step entirely.

If the plan output contains no per-key detail lines (all changes were already handled as
collisions), skip this step entirely.

**Step 2 — Approval gate**

Relay the plan report to the user and ask one `AskUserQuestion` (Approve / Abort).

On approval, re-run with `--apply`:

```bash
bash .claude/skills/dawn-backflow/backflow.sh --apply [--decisions /tmp/backflow-decisions.tsv]
```

Include `--decisions` only if rejection choices were written (or a prior `--decisions` was in use).
On abort, stop — nothing was written; `staging` is exactly as it was before you ran the command.
