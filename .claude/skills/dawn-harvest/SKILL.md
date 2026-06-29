---
name: dawn-harvest
description: Lift a generic, reusable change from staging up into the customizations (L1) layer. Use when the user says harvest, this should be generic, move to customizations, or make this upstreamable.
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
source .claude/skills/_dawn-ops-lib/dawn-ops.sh
dawn::harvest_candidates
```

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

For each proposed group:
1. Apply the **stranger test** to confirm or override the `l1l2-hint`: L1 = a stranger could drop
   this onto any Dawn fork unchanged; L2 = store-specific (branding, metafields, app IDs, copy).
   When in doubt → L2.
2. Draft a commit message: `L1: <description>` or `L2: <description>`.
3. Set the `Inert:` trailer based on the classifier verdict for the group's files (`inert` →
   `Inert: yes`; `active` → `Inert: no`; `needs_judgment` → `Inert: needs_judgment`). If files
   within a group have mixed verdicts, use the most conservative: `active` beats `inert`;
   `needs_judgment` beats both.

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

Options: **Approve** / **Change to L1** / **Change to L2** / **Skip** / **Edit message**

Process **all answers** before executing any commits. If "Edit message" is chosen, ask a
follow-up open-text question for the replacement message.

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
