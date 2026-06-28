# Dawn-ops: inert shipping + guarded reset — Design

**Date:** 2026-06-28
**Repo:** Dawn / Zogezeept (operated from `ops`)
**Status:** Approved design, pending spec review → implementation plan
**Revises:** the dawn-ops model in `.claude/skills/_dawn-ops-lib/conventions.md` and the
`dawn-harvest` / `dawn-promote` skills. Adds a new `dawn-ship` skill, a classifier in the lib,
and a workflow guide.

> Context: this design came out of rolling out the EU withdrawal form, where two limits of the
> current flow surfaced: (1) shop-global state (a page→template binding) cannot be tested on a
> non-published theme, and (2) force-pushing bot-linked branches fights Shopify's bidirectional
> GitHub sync (config churn).

## 1. Problem

The current model is "develop on `staging`, then **reset** `current := staging`." It works for
theme code but breaks on two fronts:

1. **Shop-global state is not testable on an unpublished theme.** A new page template
   (`page.withdrawal.json`) cannot be bound to a page until it exists in the **published** theme,
   so the real `/herroeping` URL cannot be exercised before going live.
2. **Force-pushing bot-linked branches fights the Shopify bidirectional GitHub sync.** Rewriting
   `staging` (harvest, reset) collides with the bot re-pushing the theme editor's config state,
   producing repeated churn (we hit it many times in one session).

We need to **ship "inert" building blocks (dormant code) to the published theme ahead of
activation**, safely and churn-free, while keeping the authoritative reset for tested releases.

## 2. Core concepts

### 2.1 Inert vs active (render-graph reachability)

A change is **inert** if and only if publishing it does not alter the rendered output of any URL a
visitor can currently reach. This is a property of the **render graph**, not of the L1/L2 layer.

- **Roots** (rendered for some live request): `layout/*.liquid`, the section groups it pulls in
  (`header-group.json`, `footer-group.json`), and every template a reachable resource routes to or
  is bound to (`index`, `cart`, `search`, `404`, `gift_card`, `password`, `page.json`,
  `product.json` + used suffixes, `collection.json` + used suffixes, blog/article, etc.).
- **Edges** (references): template → its sections (by type); section → snippets (`render`), assets
  (`asset_url`), locale keys (`t`); section groups → sections; layout → snippets/assets/groups.
- **Inert** = the change touches only **orphans** (files not reachable from any root) and adds no
  new root and no new edge from a root:
  - new section / snippet / asset not referenced by any reachable file;
  - additive-only new **locale keys** (no changed existing values);
  - a new **template** (`page.*`, `product.*`) with **no resource bound/assigned to it**.
- **Active** = anything else: edits to a reachable file (`layout`, groups, bound/routed templates,
  an existing section/snippet/asset), render-affecting `settings_data.json` changes, or **wiring**
  an orphan in (placing a section in a rendered template, binding a page, adding a nav link).
- **Shop-global gap:** whether a new template is bound is **admin state, not in git**. The
  classifier cannot know it, so new-template changes resolve to **NEEDS_JUDGMENT** (human confirms
  "no page/product is assigned this template").

### 2.2 Bot-free vs bot-linked branches

- **`customizations`** is **not linked to any theme** → the Shopify bot never writes to it → its
  history can be rewritten freely (rebase, split, reword).
- **`staging`, `current`** are **linked to real themes** (preview, live) → the bot writes config
  churn to them via the GitHub integration → treat them **append-only**: never force-push them
  **except** the one deliberate, guarded reset.

This is the root-cause fix for the churn: do all history surgery on `customizations`; only append
to bot-linked branches.

## 3. The two promote modes

### 3.1 `dawn-ship` — cherry-pick, incremental, append-only (NEW)

Cherry-picks a **classified code commit from `customizations`** onto `current` (append /
fast-forward, no force, no config files). Used to ship inert pieces early (to unblock shop-global
activation like a page binding) and tested-active pieces as they land.

- The commit is classified by `dawn::classify_changes`:
  - **inert** → **light gate**: report "no live render change", proceed on a single confirm.
  - **active** → **full gate**: live confirm + smoke-test prompt + a pre-ship rollback tag.
  - **NEEDS_JUDGMENT** (new template) → STOP, ask the human to confirm the template is unbound.
- Churn-free because it touches **code only**, disjoint from the bot's config churn.
- **Only cherry-picks from `customizations`**, never from `staging`. So a messy `staging` is
  irrelevant to shipping inert pieces.
- **Mandatory pre-ship review (the human safety net).** Before anything is appended to `current`,
  `dawn-ship` prints the **exact set of files and the full diff** that will be shipped, plus the
  classifier report (per-path inert/active and any NEEDS_JUDGMENT). The operator must explicitly
  confirm. This review is what covers the shop-global gap: if a "new" template is in fact bound to
  a page, the operator sees exactly what is going live and can abort. No Admin-API binding check is
  needed; the reviewable shipment is the safeguard. The operator can also **select** which
  commit(s) to ship, so nothing reaches `current` without being named and seen.

### 3.2 `dawn-promote` — reset, authoritative, release (REVISED)

`current := staging` (force-push), publishing the **fully rebuilt, tested `staging`** (code *and*
config), guaranteeing `current == staging`.

- **Guarded**: may only run from a **freshly-rebuilt clean `staging`** — verified as
  `customizations` + clean L2 enrichments + a config snapshot mirrored from `current`, with **no
  stray dev/debug commits**. Backflow-then-reset, the existing mechanism, now gated by a
  cleanliness check.
- The reset **reconciles** any divergence created by interim `dawn-ship` cherry-picks and bot
  commits: after it, `current` again equals the authoritative tested `staging`.

So you get **incremental shipping between releases** and a clean **`current == staging`** snapshot
**at each release**.

## 4. Components

| Path | Change | Responsibility |
|---|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | add | `dawn::classify_changes`, `dawn::assert_staging_clean`, reachability helpers |
| `.claude/skills/dawn-ship/` (SKILL.md + ship.sh) | new | cherry-pick a classified commit from `customizations` → `current` |
| `.claude/skills/dawn-promote/` | revise | add the `assert_staging_clean` guard before reset |
| `.claude/skills/dawn-harvest/` | revise | produce **atomic** commits, each purely inert or active; split mixed (reuse `--hunks`); record a classification trailer |
| `.claude/skills/_dawn-ops-lib/conventions.md` | revise | inert/active, branch roles, append-only rule, the two promote modes |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | new | the workflow guide (§6) |

### 4.1 `dawn::classify_changes`
- **Input:** a commit ref, or a `base..target` range.
- **Output:** per-path label (`inert` / `active`), plus an overall verdict
  `ALL_INERT` / `HAS_ACTIVE` / `NEEDS_JUDGMENT`, and a human-readable report (which paths and why).
- **Static reachability:** parse theme files for references to build the reachable set; classify
  each changed path against §2.1. **Git-only by design; querying the Admin API for live bindings is
  explicitly out of scope.** The shop-global gap is handled by NEEDS_JUDGMENT plus the mandatory
  pre-ship review (§3.1), not by automation.
- **Conservative default:** anything not provably inert is **active**; a new template is
  **NEEDS_JUDGMENT**. Never silently call something inert.
- The classifier verdict on the **actual diff** is always authoritative; the harvest commit-trailer
  label (§5) is only a hint, re-verified at ship time.

## 5. Harvest revision

- Produce **atomic commits**, each **purely inert or purely active**, so `dawn-ship` has clean
  units to cherry-pick.
- Record a classification **trailer** in the commit message (e.g. `Inert: yes|no`) as a hint;
  authority remains the classifier on the diff.
- A change that mixes inert and active **must be split**: file-level where possible, hunk-level
  (existing `--hunks` path) for a single file mixing inert and active lines. Splitting is a
  STOP_JUDGMENT moment guided by the classifier's per-path report.

## 6. Workflow guide (deliverable)

`docs/superpowers/runbook/dawn-dev-and-release.md` describes, for a fresh operator, what each skill
is for and the order to use them. Outline:

1. **Branch roles:** `dawn-vanilla` (L0) → `customizations` (L1+L2 code, bot-free, rewritable) →
   `staging` (bot-linked preview, append-only) ⇄ `current` (bot-linked live, append-only).
2. **Develop:** on a scratch branch off `staging` (or `staging`); preview on the linked theme.
3. **Harvest** finished pieces into `customizations` as **atomic, classified** commits
   (`dawn-harvest`), splitting any mixed change.
4. **Ship inert pieces early** with `dawn-ship` when you need them on the live theme to unblock
   shop-global activation (e.g. a page→template binding). Optional, anytime, churn-free.
5. **Activate shop-global state in admin** once the inert building blocks are live (bind the page,
   create metafields). Test the bound page on the preview theme (now possible, because the template
   name resolves on both themes).
6. **Release:** `dawn-backflow` to mirror current's config into `staging`, rebuild `staging` clean,
   test, then `dawn-promote` (reset, guarded).
7. **Rules:** never force-push a bot-linked branch except the guarded reset; all history surgery on
   `customizations`; classify before shipping.

Include a one-screen **decision tree**: "want a dormant piece live now? → `dawn-ship` (inert). Want
to publish a tested release? → rebuild staging → `dawn-promote`. Captured live admin edits? →
`dawn-backflow`. New Dawn version? → `dawn-upgrade`."

## 7. Error handling and gates

- Reuse exit codes `DAWN_OK` (0), `DAWN_GUARD` (10), `DAWN_STOP_LIVE` (20), `DAWN_STOP_JUDGMENT`
  (21), `DAWN_VERIFY` (30).
- `dawn-ship` inert → light live confirm (`DAWN_STOP_LIVE` until `--confirm-live`, with the
  classifier report shown). Active → same gate plus a printed smoke-test checklist and a rollback
  tag. New template → `DAWN_STOP_JUDGMENT`.
- `dawn-promote` from a non-clean `staging` → `DAWN_GUARD` (run rebuild/backflow first).
- Every live-touching op archives a rollback tag of `current` first (existing promote behavior),
  extended to `dawn-ship`.

## 8. Testing

Follow the existing dependency-free fixture harness (`tests/harness.sh`, `tests/fixture.sh`,
`tests/run-all.sh`):
- `test_classify.sh`: a fixture theme with reachable files + orphans; assert `inert` for orphan
  additions, `active` for reachable edits/wiring, `NEEDS_JUDGMENT` for a new template.
- `test_ship.sh`: assert a fast-forward append to `current`, the gate behavior, and the rollback tag.
- `test_promote.sh` (extend): assert the cleanliness guard rejects a dirty `staging` and accepts a
  rebuilt one.
- `test_harvest.sh` (extend): assert atomic/classified output and the split path for a mixed change.

## 9. Success criteria

- An inert orphan (e.g. a new unbound template plus its section/asset) can be shipped to `current`
  with **no churn** and **no live render change**, verified by the classifier and a clean diff.
- Active changes are **gated** (full confirm + smoke test + rollback).
- Before anything reaches `current`, the operator sees the **exact files and full diff** to be
  shipped and must confirm; nothing is shipped that was not named and reviewed.
- `dawn-promote` (reset) runs **only** from a clean rebuilt `staging` and yields `current == staging`.
- **No force-push to a bot-linked branch** except the deliberate guarded reset.
- A fresh operator can read the runbook and know **which skill to run, when, and in what order**.
