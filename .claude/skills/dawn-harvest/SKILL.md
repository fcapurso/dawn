---
name: dawn-harvest
description: Harvest changes from staging into customizations — classifying each as L1 (generic structure), L2 (store-shaped structure), or Config (content only, leave in snapshot). Use when the user says harvest, promote to customizations, classify these changes, or split staging commits.
---

## Overview

`dawn-harvest` analyses changes between `staging` and `customizations`, groups related files into
proposed feature commits, classifies each as L1 (generic) or L2 (store-specific), confirms with
the operator via `AskUserQuestion`, then commits each group atomically into `customizations` and
rebases `staging`.

`customizations` holds **both L1 and L2 commits** distinguished by their prefix (`L1:` / `L2:`)
and `Inert:` trailer. See `../_dawn-ops-lib/conventions.md` for the full layer model.

## Prerequisites

- Run from the `ops` branch (or any branch that is not `current`) with a clean working tree.
- `staging` and `customizations` must exist locally.

## Step 1 — Run analysis

```bash
bash --noprofile --norc -c '
source .claude/skills/_dawn-ops-lib/dawn-ops.sh
dawn::harvest_candidates
'
```

> Always invoke `dawn::*` functions through an explicit `bash -c` wrapper, never a bare
> `source` in the ambient shell — see `../_dawn-ops-lib/conventions.md` §3c.

If output is empty: report "nothing to harvest — staging and customizations are in sync" and stop.

## Step 2 — Group files into proposed commits

Using the candidate list from Step 1, group files by semantic relationship:

- **Locale grouping:** a section file (e.g. `sections/withdrawal.liquid`) groups with locale keys
  whose top-level namespace matches the section handle — detected by scanning locale JSON files in
  the candidate list for top-level keys prefixed with the section handle (e.g. `withdrawal`).
- **Asset grouping:** a section file groups with assets it directly references via
  `{{ '...' | asset_url }}` — detected by scanning the section's content on `staging`.
- **Template grouping:** a suffix template (e.g. `templates/product.soap.json`) groups with
  snippets or sections it exclusively references that also appear in the candidate list.
- **Independent files:** any file with no detected relationship to others is proposed as its own
  single-file commit.

**Do not use staging commit history for grouping.** The diff is the net effect of all staging work.

For each proposed group, apply the **structure-vs-content** test:

**The core question:** does this change define how the site works (structure), or what it currently
says and shows (content)?

- **Structure with no store-specific data → L1.** A stranger could drop this onto any Dawn fork
  unchanged. Draft message: `L1: <description>`.
- **Structure shaped for this store → L2.** The shape has reuse value within this store (a
  template applies to many resources, a section appears on many pages) but contains store-specific
  data (app UUIDs, metafield handles, domain references, GTM IDs). Draft message: `L2: <description>`.
- **Content only → Config.** The change is text values, colour tokens, section ordering on a
  default template, or theme settings — no new structure. Belongs in the config-snapshot commit,
  not in `customizations`. Mark as Config in the confirmation step; do not harvest.

**When in doubt → L2.** Never L1 unless certain.

### Template JSON candidates — mechanical structure-vs-content split

For any candidate under `templates/*.json`, **do not eyeball the diff** — the boundary is
decidable. A template's **structure** is everything outside the `settings` objects; its
**content** is the values inside `settings` (both section-level and block-level, since `blocks`
is a sibling of `settings`). Run:

```bash
bash --noprofile --norc -c 'source .claude/skills/_dawn-ops-lib/dawn-ops.sh && dawn::classify_template_json <templates/….json>'   # prints "config" or "l2"
```

- **`config`** — only in-`settings` values differ (heading/intro/copy, colours, paddings, block
  setting values). This is theme-editor content mirrored from live; it belongs in the config
  snapshot. Mark as **Config (content only)** in Step 4 and do not harvest.
- **`l2`** — the skeleton differs (section add/remove/reorder, section `type`, `disabled`,
  `name`, or block add/remove/reorder/`type`), or the template is new/removed on one side. This
  is store-shaped structure → harvest as **L2**. A structural template change is never L1.

If a live template mixes a real structural change **with** incidental settings drift, harvest
only the skeleton as L2 and leave the settings values as config: write the desired template
(skeleton change applied, drifted setting values reset to the `customizations` baseline) to a
temp file and pass it via `--l1-content <path>:<tmp>` to `harvest-commit.sh` (the flag copies
arbitrary content into the commit despite its L1 name).

> Note: for **suffix templates**, these `settings` values are now actively reconciled by
> `dawn-backflow` (3-way merge), not merely left inert — see
> `docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md`. The skeleton still
> harvests as L2 here.

For each group that is L1 or L2:
1. Draft a commit message: `L1: <description>` or `L2: <description>`.
2. Set the `Inert:` trailer from the classifier verdict (`inert` → `Inert: yes`; `active` →
   `Inert: no`; `needs_judgment` → `Inert: needs_judgment`). Mixed verdicts: use the most
   conservative (`needs_judgment` > `active` > `inert`).

## Step 3 — Detect and plan hunk splits

For any file where the diff contains **both** generic (L1) and store-specific (L2) content:

- If the hunks are cleanly separated (non-interleaved): propose splitting the file into two
  commits — an L1 commit with the generic portion, an L2 commit with the remainder. Write the
  L1-only content to a temp file and pass it via `--l1-content` to `harvest-commit.sh`.
- If the hunks interleave: flag the file as requiring manual separation and **skip it**, reporting
  exactly which lines need to be disentangled before it can be harvested.

## Step 4 — Confirm via AskUserQuestion

Call `AskUserQuestion` once per proposed commit (in dependency order: if a section is L1 and
its template is L2, the section comes first). Each question must show:

- Proposed commit message (including `Inert:` trailer)
- File list with per-file classifier verdict
- L1 or L2 classification with one-sentence reasoning

Options:

| Option | Meaning |
|---|---|
| **Approve** | Harvest as proposed |
| **Change to L1** | Harvest as generic (no store-specific data) |
| **Change to L2** | Harvest as store-specific |
| **Config (content only)** | This is content, not structure — leave in config snapshot, do not harvest |
| **Skip** | Don't harvest now, decide later |
| **Edit message** | Keep classification, change the commit message |

Process **all answers** before executing any commits. If "Edit message" is chosen, ask a
follow-up open-text question for the replacement message. Groups marked **Config (content only)**
are silently dropped — no commit, no action needed.

## Step 5 — Execute in order

For each approved group, call:

```bash
bash .claude/skills/dawn-harvest/harvest-commit.sh \
  --message "<full commit message with Inert: trailer>" \
  --files <file1> [file2 ...] \
  [--l1-content <file>:<tmppath>]
```

After all groups: show the final `git log --oneline customizations` and confirm `staging`'s tip is
still the config-snapshot commit.

## Exit codes

| Code | Meaning | Agent action |
|------|---------|--------------|
| 0 (`DAWN_OK`) | Success | Confirm commit landed on `customizations` and `staging` tip is config snapshot. |
| 10 (`DAWN_GUARD`) | Guard tripped | Report the reason (config file; dirty tree; wrong branch). Do not retry without resolving. |
| 21 (`DAWN_STOP_JUDGMENT`) | Needs human judgment | A rebase conflict occurred. You are left on `staging` with a rebase in progress. Resolve with the user, then `git rebase --continue`, or `git rebase --abort` to back out. |
