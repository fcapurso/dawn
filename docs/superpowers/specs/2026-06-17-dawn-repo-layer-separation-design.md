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

Just **two** layers that matter, divided by one question: *is this upstreamable?*

- **L0 — Vanilla Dawn** at a pinned upstream release tag. Start: v15.1.0.
- **L1 — Generic customizations** (upstream-shaped): code that passes the **strict L1 test**
  (below). Rebases onto each new Dawn release. Kept lean and proud. *Tiny in practice* — for this
  store it's essentially `pickup-availability.liquid`, the inventory-status + product-logos
  mechanism in `main-product.liquid`, and `component-product-logos.css`.
- **L2 — Store-specific** (everything not upstreamable): custom templates, custom pages,
  app-injected tracking, `settings_data.json`, section-group/template JSON, store copy. Lives on
  `staging` on top of L1.

We **deliberately collapsed the earlier "L2a/L2b" sub-split.** It was never a separate branch —
both lived on `staging` — so it was only ever a question of *how to chunk commits*. That is
handled by commit hygiene (below), not by a layer taxonomy.

### Commit hygiene within L2 (replaces the L2a/L2b distinction)

The one real, *physical* distinction is **discrete files vs the single serialized blob**, and it
drives how we commit — not what layer something is in:

- **Discrete store files** (custom `product.*.json` templates, `page.store_finder.liquid`,
  `theme.liquid` tracking hunks, etc.) → committed as **their own logical commits** so each stays
  recognizable in history (e.g. "Add workshop product template"). This satisfies the original
  requirement that a new template/page not drown in config churn.
- **The config blob** — `settings_data.json` (and the layout JSON it co-evolves with:
  section-group JSON, stock-template JSON) → committed as **one "store config snapshot" commit**,
  because it has only a *current value*, not a cherry-pickable history.

**Hard rule:** never fold the discrete store files *into* the config-snapshot commit. Keeping them
separate is the entire value, and it's free because they are already separate files.

### The strict L1 test (the only dividing rule)

A file is **L1** only if: *"A stranger could drop this file into a vanilla Dawn store and have
it work, with zero edits and no hardcoded references to your products, brand, or copy."*
If it names a specific product/handle, custom metafield, app-instance UUID, your branding, or
store-specific copy → **L2**. On the fence → **L2**.

*Worked examples (verified against the code):* the `custom-product-logos` block + its CSS are
settings-driven with no hardcoded store data → **L1**. The custom `product.*.json` templates
reference store-only metafields (`product.metafields.my_fields.ingredients`, …) and a specific
Judge.me app-instance UUID → **L2**. `theme.liquid`'s GTM ID and UnlimitedFonts metafield → **L2**.

**The user decides every file's layer.** The inventory proposes L0/L1/L2 for each changed file
with reasoning; the user approves or overrides each one. No file is filed without a ruling.

### One honest boundary (Shopify data-model limit)

Some deliberate work (e.g. "change homepage/footer layout") is stored as section/block placement
*inside* `settings_data.json` + section-group JSON, not as a file — so it rides in the config
snapshot, not as a discrete commit. New *templates* and *pages* are discrete; *layout-of-existing-pages*
is not. Also: a page's body *content* lives in the Shopify admin database, never in the repo —
git only sees the page *template*.

### What is actually on `current` (verified net delta after app cleanup)

The honest baseline is `git diff $(git merge-base upstream/main origin/current)..origin/current`:
everything after the latest shared upstream commit is **purely the user's + shopify[bot]'s** work
(0 upstream commits). After the app-uninstall cleanup this is ~60 files: ~22 non-locale + ~38
locale (a mix of real custom strings and serialization churn).

| Kind | Fate |
|---|---|
| Generic code (pickup, inventory-status, product-logos) | **L1** |
| Custom templates/pages, tracking, store config | **L2** (discrete-file commits + one config-snapshot commit) |
| `templates/password.json` | **drop** — pure churn, revert to vanilla (documented) |
| `settings_schema.json`, most locales, `translation.yml`, `release-notes.md` | **upstream-reconcile** — auto-recovered when `dawn-vanilla` ffs to 15.2.0 |
| Custom translation keys for L1 features (e.g. `pick_up_unavailable`) | ride with **L1** so the feature works |

## Target topology (Approach A, inside the existing fork)

| Branch | Contents | Linked theme | Role |
|---|---|---|---|
| `dawn-vanilla` | pristine Dawn @ release tag (start v15.1.0) | — | L0 reference; only fast-forwarded to new release tags |
| `customizations` | `dawn-vanilla` + L1, curated feature-grouped commits | — | the replayable, upstream-shaped layer |
| `staging` | `customizations` + L2 (discrete-file commits + one config-snapshot commit) | **non-live preview theme** | integration & test before going live; permanent |
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
  almost entirely L2 config churn. **Deferred phase (see below):** these get *squashed* into the
  single "store config snapshot" commit on `staging` rather than accumulating as N commits, so
  the 62-commit sea never re-forms. (Any incoming change that's actually a new discrete file, or a
  generic edit = L1, is harvested to its proper place instead — see commit hygiene.)
- **Promote (③)** is a reset of `current` to `staging`'s tree + force-push (allowed: current's
  own commits are rewritable). The Shopify integration then updates the live theme.
- **Non-negotiable invariant:** never promote (③) without a fresh backflow (①) first.
  Otherwise the force-reset destroys admin-UI config changes made on the live theme since the
  last sync. The backflow is what makes the reset lossless.

### What lives only on `current` in the TO-BE (steady state)

After a promote, `current` and `staging` are identical trees. The *only* commits that ever
become unique to `current` thereafter are **live admin-UI edits since the last sync** — always
pure L2 config, never L0/L1. They are transient: the next backflow absorbs them, the next
promote resets `current` again. So `current` is a disposable "live config sink" downstream of
`staging`; everything durable lives upstream of it. This is why force-resetting `current` on
promote is safe — given the backflow-first invariant.

### Deferred phase — controlling live-commit churn

The exact recipe for squashing/absorbing backflowed auto-sync commits into the config-snapshot
commit (keeping durable history clean going forward) is intentionally deferred to a later phase,
per user request. The design already supports it via the squash-on-backflow hook above; only the
mechanics remain to be specified.

### Dawn version update (special case of the cycle)

1. Fast-forward `dawn-vanilla` to the new upstream release tag.
2. Rebase `customizations` onto it — resolve conflicts once, in clean L1 space.
3. Rebuild `staging` (= new `customizations` + L2); test in the preview theme.
4. Backflow then promote to `current`.

### Harvest habit

When a generic edit lands bundled on `current` that really belongs in L1 (or a new discrete file),
lift it onto the right place so L1 stays complete and the config snapshot stays pure config. The
runbook gives the exact `git` recipe.

## Deliverables

1. **Inventory document** (`docs/.../inventory.md`): every file in the verified net delta
   classified **L0 / L1 / L2 / drop / upstream-reconcile**, with reasoning, per-hunk notes where a
   file mixes layers, applying the strict L1 test (L2 as tiebreaker). **The user rules on every
   file** — proposal-and-decision is the core contract; nothing is filed without approval.
   Includes the app audit. Built before any branch.
2. **`dawn-vanilla`** pinned at v15.1.0.
3. **`customizations`** branch: approved L1 applied as clean, feature-grouped commits.
4. **`staging`** branch: `customizations` + L2 — discrete store files as their own logical commits
   + one config-snapshot commit (commit hygiene above); linked by the user to a preview theme.
5. **Runbook** in the repo: the promote/backflow cycle, the Dawn-update procedure, the harvest
   recipe, and the branch-triage decisions.

## Acceptance test

`customizations` + L2 reproduces today's `current` tree **byte-for-byte**: a `git diff` between
the rebuilt `staging` tree and today's `current` tree returns empty. This proves the restructure
lost nothing. Today's `current` is left untouched until the user has reviewed the rebuilt lineage
and chosen the cutover.

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
