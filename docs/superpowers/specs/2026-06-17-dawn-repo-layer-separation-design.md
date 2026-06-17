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

## The layers

L2 is **not** one undifferentiated blob. It splits in two along a *physical* line —
how Shopify stores the thing — which determines whether a change is cherry-pickable at all.

- **L0 — Vanilla Dawn** at a pinned upstream release tag. Start: v15.1.0.
- **L1 — Generic customizations** (upstream-shaped): edits to `.liquid` sections/snippets,
  `base.css`, `global.js`, assets that pass the **strict L1 test** (below). Rebases onto each
  new Dawn release. Kept lean and proud.
- **L2a — Authored store assets** (store-specific, but discrete files): custom JSON templates
  (`product.workshop`, `geurblokje`, `soap`, `badzout`, `facialmask`, `3rd-party-product`),
  custom page templates, store-specific section/snippet `.liquid`. **Cherry-pickable**,
  recognizable, curated into feature-grouped commits. Sits on top of L1.
- **L2b — Config state / churn** (store-specific, serialized snapshot): `config/settings_data.json`,
  `config/settings_schema.json`, section-group JSON block placements (`header-group`,
  `footer-group`), app install/uninstall residue, theme-setting toggles. **Not cherry-pickable** —
  it has only a *current value*, not a meaningful history. Carried as essentially **one evolving
  "store config snapshot" commit**, not the 62 incremental auto-syncs.

### The strict L1 test (the L1 vs L2a dividing rule)

A file is **L1** only if: *"A stranger could drop this file into a vanilla Dawn store and have
it work, with zero edits and no hardcoded references to your products, brand, or copy."*
If it names a specific product/handle, your branding, or store-specific copy → **L2a**.
**On the fence → L2a** (the tiebreaker). Rationale: L1 is re-merged on every Dawn upgrade and is
meant to be upstream-shaped, so it must stay clean; promoting L2a→L1 later is trivial, scrubbing
store-specifics out of a thrice-rebased L1 file is not.

**The user decides every file's layer.** The inventory proposes L0/L1/L2a/L2b for each changed
file with reasoning + confidence; the user approves or overrides each one. This per-file
proposal-and-decision is the inventory's core contract — no file is filed without a ruling.

### Two honest cherry-pickability boundaries (Shopify data-model limits)

1. **Some authored work lives *inside* L2b and cannot be lifted out as a file.** E.g. "change
   homepage/footer layout" is deliberate, but it is stored as section/block placement inside
   `settings_data.json` + section-group JSON, not as a file. New *templates* and *pages* are
   cherry-pickable; *layout-of-existing-pages* is not. Shopify limitation, not a choice.
2. **Page *content* is not in the repo at all.** A page's body text lives in the Shopify admin
   database; git only sees the page *template*. "Recognizable page" means its template file is
   recognizable; the content itself is never version-controlled by the theme.

### What is actually on `current` (117 commits since v15.1.0)

| Kind | Count | Fate |
|---|---|---|
| Shopify admin auto-sync ("Update from Shopify") | 62 | collapse into the L2b snapshot |
| Translation-bot commits | 8 | dropped — locales follow upstream |
| Merged upstream Dawn fixes (PR-numbered, incl. stray post-15.1.0) | ~19 | immutable; not the user's |
| User's genuine local work | ~28 | split into L1 / L2a / L2b by the inventory |

**Caveat the inventory must handle:** `current` already contains ~19 cherry-picked
post-15.1.0 upstream fixes (via "Update main with v15.2.0"). Vanilla underneath is therefore
"15.1.0 + some stray 15.2 fixes," not clean 15.1.0. The inventory must recognize these so an
upstream fix is never misfiled as a user customization. The byte-for-byte acceptance test
protects correctness regardless.

## Target topology (Approach A, inside the existing fork)

| Branch | Contents | Linked theme | Role |
|---|---|---|---|
| `dawn-vanilla` | pristine Dawn @ release tag (start v15.1.0) | — | L0 reference; only fast-forwarded to new release tags |
| `customizations` | `dawn-vanilla` + L1, curated feature-grouped commits | — | the replayable, upstream-shaped layer |
| `staging` | `customizations` + L2a (curated) + L2b (config snapshot) | **non-live preview theme** | integration & test before going live; permanent |
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

- **Backflow (①)** captures `current`'s new commits since last sync — admin auto-syncs that are
  almost entirely L2b config churn. **Deferred phase (see below):** these get *squashed* into the
  single L2b "store config snapshot" commit on `staging` rather than accumulating as N commits, so
  the 62-commit sea never re-forms. (Any incoming change that's actually a new file = L2a, or a
  generic edit = L1, is harvested to its proper layer instead.)
- **Promote (③)** is a reset of `current` to `staging`'s tree + force-push (allowed: current's
  own commits are rewritable). The Shopify integration then updates the live theme.
- **Non-negotiable invariant:** never promote (③) without a fresh backflow (①) first.
  Otherwise the force-reset destroys admin-UI config changes made on the live theme since the
  last sync. The backflow is what makes the reset lossless.

### What lives only on `current` in the TO-BE (steady state)

After a promote, `current` and `staging` are identical trees. The *only* commits that ever
become unique to `current` thereafter are **live admin-UI edits since the last sync** — always
pure L2b config, never L0/L1/L2a. They are transient: the next backflow absorbs them, the next
promote resets `current` again. So `current` is a disposable "live config sink" downstream of
`staging`; everything durable lives upstream of it. This is why force-resetting `current` on
promote is safe — given the backflow-first invariant.

### Deferred phase — controlling live-commit churn

The exact recipe for squashing/absorbing backflowed auto-sync commits into the L2b snapshot
(keeping durable history clean going forward) is intentionally deferred to a later phase, per
user request. The design already supports it via the squash-on-backflow hook above; only the
mechanics remain to be specified.

### Dawn version update (special case of the cycle)

1. Fast-forward `dawn-vanilla` to the new upstream release tag.
2. Rebase `customizations` onto it — resolve conflicts once, in clean L1 space.
3. Rebuild `staging` (= new `customizations` + L2); test in the preview theme.
4. Backflow then promote to `current`.

### Harvest habit

When a generic edit lands bundled on `current` (or `staging`'s L2 area) that really belongs in
L1 (or a new file that belongs in L2a), lift it onto the right layer so each layer stays
complete and the config snapshot stays pure config. The runbook gives the exact `git` recipe.

## Deliverables

1. **Inventory document** (`docs/.../inventory.md`): every changed file in `v15.1.0..current`
   classified **L0 / L1 / L2a / L2b / locale-churn / upstream-fix / app-residue**, with reasoning
   + confidence, per-hunk notes where a file mixes layers, applying the strict L1 test (L2a as
   tiebreaker). **The user rules on every file** — proposal-and-decision is the core contract;
   nothing is filed without approval. Includes the app audit (each app's footprint or absence;
   "likely unused" flags). Built before any branch.
2. **`dawn-vanilla`** pinned at v15.1.0.
3. **`customizations`** branch: approved L1 applied as clean, feature-grouped commits.
4. **`staging`** branch: `customizations` + curated L2a feature commits + a single L2b config
   snapshot commit; linked by the user to a preview theme.
5. **Runbook** in the repo: the promote/backflow cycle, the Dawn-update procedure, the harvest
   recipe, and the branch-triage decisions.

## Acceptance test

`customizations` + L2a + L2b reproduces today's `current` tree **byte-for-byte**: a `git diff`
between the rebuilt `staging` tree and today's `current` tree returns empty. This proves the
restructure lost nothing. Today's `current` is left untouched until the user has reviewed the
rebuilt lineage and chosen the cutover.

## Out of scope (YAGNI) / deferred

- No second fork repo; no actual upstream PRs.
- No rewriting of upstream commits, ever.
- No automated app uninstalling — report only.
- Branch-zoo triage is planned but executed as a clearly separated step.
- Live-commit churn-control mechanics (squash-on-backflow recipe) are deferred to a later
  phase; the design reserves the hook for it.

## App audit — early signal

`snippets/pagefly-main-css.liquid` appears in history but is **not currently tracked** →
PageFly was installed and its theme footprint later removed. No app-injected files match common
app-name patterns in the current tree, suggesting the theme code is currently clean of app
injection. To be verified properly during the inventory.
