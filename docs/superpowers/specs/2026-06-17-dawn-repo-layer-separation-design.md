# Dawn theme repo: layer separation & clean update workflow

**Date:** 2026-06-17
**Repo:** `fcapurso/dawn` (fork of `Shopify/dawn`)
**Status:** Design approved in brainstorming; pending spec review before planning.

## Problem

`current` (the live, Shopify-linked theme branch) has accumulated 117 commits on top of
vanilla Dawn v15.1.0. Those commits entangle three distinct layers plus noise, making it
impossible to tell what is vanilla Dawn, what is a generic customization, and what is
store-specific configuration. This blocks confident Dawn upgrades and any reuse/upstreaming
of the generic work.

## Goals (in the user's priority order)

1. **(Primary) Restructured branch topology** to adopt going forward for updates and testing.
2. **(Means) A replayable customization layer** — generic edits isolated so they rebase onto
   any fresh Dawn version, structured cleanly enough that they *could* be upstreamed
   (no actual PRs planned).
3. **(Means) Inventory & understanding** — a documented map of every divergence, plus an app
   audit flagging likely-unused apps (confirmed by the user in admin).

## Hard constraints / invariants

- **Upstream Dawn commits are immutable.** Never rewrite, rebase, or alter any commit
  authored upstream (Shopify Dawn). They are the shared lineage that makes future merges work.
  Only the user's own commits and "Update from Shopify" auto-sync commits may be rewritten.
- **`current` stays the live, Shopify-GitHub-linked branch.** The user keeps working exactly
  as today: editing in code *and* in the Shopify admin UI, with admin edits auto-committing to
  `current`. No workflow change is acceptable.
- **App audit is code+config inference only.** Flag "likely unused"; user confirms in admin.
  No automated app uninstalling.
- **Lossless restructure.** The new lineage must reproduce today's `current` tree byte-for-byte.

## The three layers

- **L0 — Vanilla Dawn** at a pinned upstream release tag. Start: v15.1.0.
- **L1 — Generic customizations** (potentially upstreamable): edits to `.liquid`
  sections/snippets, `base.css`, `global.js`, assets — excluding anything app-injected or
  store-specific. ~24 candidate files; concentrated in ~28 authored commits.
- **L2 — Store config** (never upstreamable): `config/settings_data.json`,
  `config/settings_schema.json`, store JSON templates (`product.workshop`,
  `product.geurblokje`, `product.soap`, `product.badzout`, `product.facialmask`,
  `product.3rd-party-product`, edited stock templates), section-group JSON
  (`header-group`, `footer-group`), pages, and any app-injected files.

### What is actually on `current` (117 commits since v15.1.0)

| Kind | Count | Fate |
|---|---|---|
| Shopify admin auto-sync ("Update from Shopify") | 62 | becomes the L2 layer |
| Translation-bot commits | 8 | dropped — locales follow upstream |
| Merged upstream Dawn fixes (PR-numbered, incl. stray post-15.1.0) | ~19 | immutable; not the user's |
| User's genuine local work | ~28 | split into L1 vs L2 by the inventory |

**Caveat the inventory must handle:** `current` already contains ~19 cherry-picked
post-15.1.0 upstream fixes (via "Update main with v15.2.0"). Vanilla underneath is therefore
"15.1.0 + some stray 15.2 fixes," not clean 15.1.0. The inventory must recognize these so an
upstream fix is never misfiled as a user customization. The byte-for-byte acceptance test
protects correctness regardless.

## Target topology (Approach A, inside the existing fork)

| Branch | Contents | Linked theme | Role |
|---|---|---|---|
| `dawn-vanilla` | pristine Dawn @ release tag (start v15.1.0) | — | L0 reference; only fast-forwarded to new release tags |
| `customizations` | `dawn-vanilla` + L1, as curated commits grouped by feature | — | the replayable, upstream-shaped layer |
| `staging` | `customizations` + L2 | **non-live preview theme** | integration & test before going live; permanent |
| `current` | live store | **live theme** | Shopify-linked; receives admin auto-syncs |

`main`, `update-to-*`, and feature branches are triaged in a later cleanup step
(archive-as-tag or delete) — not load-bearing in the new model.

## Rejected approaches

- **B — Two branches + `.patch` series:** L1 as maintained patch files instead of a branch.
  Rejected: patches are more manual to replay and weaker for upstream-shaped structure.
- **C — Separate fork repo with real PRs:** Rejected as overkill; user wants
  upstream-*shaped* structure, not actual PRs. Two repos to sync isn't worth it.

## Ongoing workflow (the promote/backflow cycle)

```
①  current ──(backflow: capture live admin edits)──▶ staging
②  staging:  do the work (ff dawn-vanilla, rebase customizations, test in preview theme)
③  staging ──(promote: reset/force)──▶ current   ⟹ live theme updates
```

- **Backflow (①)** is a normal merge: `current`'s new commits since last sync are admin
  auto-syncs (pure L2), which merge into `staging` cleanly and join the L2 layer.
- **Promote (③)** is a reset of `current` to `staging`'s tree + force-push (allowed: current's
  own commits are rewritable). The Shopify integration then updates the live theme.
- **Non-negotiable invariant:** never promote (③) without a fresh backflow (①) first.
  Otherwise the force-reset destroys admin-UI config changes made on the live theme since the
  last sync. The backflow is what makes the reset lossless.

### Dawn version update (special case of the cycle)

1. Fast-forward `dawn-vanilla` to the new upstream release tag.
2. Rebase `customizations` onto it — resolve conflicts once, in clean L1 space.
3. Rebuild `staging` (= new `customizations` + L2); test in the preview theme.
4. Backflow then promote to `current`.

### Harvest habit

When a generic edit lands bundled on `current` (or `staging`'s L2 area) that really belongs in
L1, lift it onto `customizations` so the layer stays complete. The runbook gives the exact
`git` recipe.

## Deliverables

1. **Inventory document** (`docs/.../inventory.md`): every file in `v15.1.0..current`
   classified L1 / L2 / locale-churn / upstream-fix / app-residue, with reasoning + confidence,
   per-hunk notes where a file mixes layers. Includes the app audit (each app's footprint or
   absence; "likely unused" flags). **User approves/corrects before any branch is built.**
2. **`dawn-vanilla`** pinned at v15.1.0.
3. **`customizations`** branch: approved L1 applied as clean, feature-grouped commits.
4. **`staging`** branch: `customizations` + L2, linked by the user to a preview theme.
5. **Runbook** in the repo: the promote/backflow cycle, the Dawn-update procedure, the harvest
   recipe, and the branch-triage decisions.

## Acceptance test

`customizations` + L2 reproduces today's `current` tree **byte-for-byte**: a `git diff`
between the rebuilt `staging` tree and today's `current` tree returns empty. This proves the
restructure lost nothing. Today's `current` is left untouched until the user has reviewed the
rebuilt lineage and chosen the cutover.

## Out of scope (YAGNI)

- No second fork repo; no actual upstream PRs.
- No rewriting of upstream commits, ever.
- No automated app uninstalling — report only.
- Branch-zoo triage is planned but executed as a clearly separated step.

## App audit — early signal

`snippets/pagefly-main-css.liquid` appears in history but is **not currently tracked** →
PageFly was installed and its theme footprint later removed. No app-injected files match common
app-name patterns in the current tree, suggesting the theme code is currently clean of app
injection. To be verified properly during the inventory.
