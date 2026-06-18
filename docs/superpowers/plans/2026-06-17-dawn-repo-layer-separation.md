# Dawn Repo Layer Separation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the `fcapurso/dawn` fork into clean, layered branches (`dawn-vanilla` → `customizations` → `staging` → `current`) so vanilla Dawn, generic customizations, authored store assets, and config churn are cleanly separated and Dawn upgrades become a repeatable rebase.

**Architecture:** Reconstruct today's `current` tree as a stack of layered commits on top of pinned vanilla Dawn (v15.1.0). A human-ruled inventory assigns every changed file to **L0 / L1 / L2 / drop / upstream-reconcile**. Within L2 (store-specific), commit hygiene splits *discrete store files* (their own logical commits) from the *config blob* (`settings_data.json` + layout JSON, one snapshot commit). Branches are built from the approved inventory and validated by a byte-for-byte tree comparison against today's `current`. Nothing is built until the inventory is approved; `current` and the live theme are never touched until a separately-chosen cutover.

**Tech Stack:** git, Shopify GitHub theme integration, Dawn (Liquid theme). No build/test runner — "tests" are git verification commands with expected output; the master check is an empty `git diff` between the rebuilt `staging` tree and today's `current` tree.

---

## Critical invariants (apply to EVERY task)

- **NEVER commit, push, reset, or force-push to `current`.** It is the live shop. Every task begins with the branch guard in Task 0. Work happens on `repo-cleanup`, `dawn-vanilla`, `customizations`, `staging`.
- **Upstream Dawn commits are immutable** — never rebase/rewrite them.
- **No branch is built before the inventory is human-approved** (gate after Task 2).
- **Nothing is pushed** anywhere until the user explicitly authorizes it. All work is local until then.
- Reference: spec at `docs/superpowers/specs/2026-06-17-dawn-repo-layer-separation-design.md`.

## File structure created by this plan

- `docs/superpowers/plans/2026-06-17-dawn-repo-layer-separation.md` — this plan.
- `docs/superpowers/inventory/2026-06-17-divergence-inventory.md` — the per-file classification (Task 2), human-ruled.
- `docs/superpowers/runbook/dawn-update-and-promote.md` — operating runbook (Task 8).
- Branches: `dawn-vanilla`, `customizations`, `staging` (created Tasks 1, 4, 6).
- Tag: `pre-cleanup-backup` on today's `current` tip (Task 0) — immutable safety net.

---

## Task 0: Safety scaffolding

**Files:** none (git refs only)

- [ ] **Step 1: Verify we are NOT on `current`, and define a reusable guard**

Run:
```bash
cd /Users/filippo/Shopify/dawn
test "$(git branch --show-current)" != "current" && echo "OK: not on current" || { echo "ABORT: on current"; exit 1; }
```
Expected: `OK: not on current`

- [ ] **Step 2: Tag today's live state as an immutable backup**

Run:
```bash
git tag -f pre-cleanup-backup origin/current
git rev-parse --short pre-cleanup-backup
```
Expected: a short SHA matching `origin/current` (today: `19de43e2`). This is the rollback anchor; never delete it.

- [ ] **Step 3: Record the base and key SHAs for later verification**

Run:
```bash
echo "BASE (v15.1.0): $(git rev-parse --short v15.1.0)"
echo "CURRENT tip:    $(git rev-parse --short origin/current)"
git rev-list --count v15.1.0..origin/current
```
Expected: base SHA, current tip SHA, and `117` (commit count since base). If the count differs, the live branch advanced — re-baseline before continuing.

- [ ] **Step 4: Commit a note recording these anchors**

```bash
git checkout repo-cleanup
printf '%s\n' "Base v15.1.0 = $(git rev-parse v15.1.0)" "current tip = $(git rev-parse origin/current)" "backup tag = pre-cleanup-backup" > docs/superpowers/inventory/.anchors.txt
git add docs/superpowers/inventory/.anchors.txt
git commit -m "chore: record cleanup anchors (base, current tip, backup tag)"
```

---

## Task 1: Create `dawn-vanilla` (L0)

**Files:** none (branch only)

- [ ] **Step 1: Guard**

Run: `test "$(git branch --show-current)" != "current" && echo OK || exit 1`
Expected: `OK`

- [ ] **Step 2: Create `dawn-vanilla` pinned at the v15.1.0 release tag**

Run:
```bash
git branch dawn-vanilla v15.1.0
git rev-parse --short dawn-vanilla v15.1.0
```
Expected: both SHAs identical.

- [ ] **Step 3: Verify it is pristine vanilla (no divergence from the tag)**

Run: `git diff --stat v15.1.0..dawn-vanilla | tail -1`
Expected: empty output (zero changes).

- [ ] **Step 4: No commit needed** (branch creation is the deliverable). Record in plan checkbox only.

---

## Task 2: Build the divergence inventory (HUMAN-GATED DELIVERABLE)

**Files:**
- Create: `docs/superpowers/inventory/2026-06-17-divergence-inventory.md`

**STATUS: COMPLETED LIVE in the design session (2026-06-17).** The inventory was built, the app
audit drove an app-uninstall cleanup (Pandectes, Booster, YMQ B2B, popup, PageFly all removed from
the theme — see app audit below), the baseline was re-pinned (`clean-baseline` tag), and every file
in the net delta was reviewed with the user. The final agreed classification is recorded below and
in `docs/superpowers/inventory/2026-06-17-divergence-inventory.md`. Task 3 builds the manifests
directly from this.

- [ ] **Step 1: Confirm the net-delta baseline (already done)**

```bash
MB=$(git merge-base upstream/main origin/current)   # = d2612f03 at clean-baseline
git diff --name-only $MB..origin/current | wc -l     # ~60 files, 0 upstream commits after MB
```

- [ ] **Step 2: Final agreed classification (the ruling)**

| File(s) | Layer | Notes |
|---|---|---|
| `sections/pickup-availability.liquid` | **L1** | generic pickup "unavailable" state |
| `sections/main-product.liquid` | **L1** | both hunks: inventory-status options + tag-based product-logos block (settings-driven, no store data) |
| `assets/component-product-logos.css` | **L1** | styling for the product-logos block |
| `layout/theme.liquid` | **L2** (discrete) | per-hunk: GTM tracking ID + UnlimitedFonts metafield (store-specific) |
| `templates/page.store_finder.liquid` | **L2** (discrete) | custom page; Simple Store Finder metafields |
| `templates/product.{workshop,soap,geurblokje,badzout,facialmask,3rd-party-product}.json` | **L2** (discrete) | custom product templates — store metafields + Judge.me app-instance UUID |
| `config/settings_data.json` | **L2** (config snapshot) | master config blob |
| `sections/header-group.json`, `sections/footer-group.json` | **L2** (config snapshot) | real store config (Dutch announcements, footer images) |
| `templates/{index,cart,collection,article,blog,product}.json` | **L2** (config snapshot) | layout config with real settings |
| `templates/password.json` | **drop** | pure churn (banner+escaping+empty settings); revert to vanilla in Task 7b |
| `config/settings_schema.json`, `locales/*` (incl. `*.schema.json`), `translation.yml`, `release-notes.md` | **upstream-reconcile** | recovered when `dawn-vanilla` ffs to 15.2.0 |
| L1-feature keys in locale **and schema-locale** files (Dutch `pick_up_unavailable` in `nl.json`; `availability_type`/`high_stock_threshold`/`low_stock_threshold`/Items/Places in `en.default.schema.json`) | **ride with L1** | added in Task 4 so the L1 features render with proper labels/strings |

> Note: `nl.schema.json` was *not* modified — the Dutch theme editor currently shows fallback
> labels for the inventory-status settings. Pre-existing gap; preserved as-is (not introduced by us).

> **Resolved (2026-06-17):** only **Dutch (`nl`) and English (`en.default`)** are actively
> maintained; expansion possible later. So only those two locale files carry real custom strings;
> the other ~36 are pure upstream churn. All locales remain upstream-reconcile; only the L1-feature
> keys (e.g. `pick_up_unavailable`) ride with L1. Future languages are added when needed, not now.

- [ ] **Step 3: App audit (COMPLETED — all flagged apps were uninstalled & cleaned)**

```markdown
## App audit result (confirmed by user, cleaned via admin)
| App | Prior footprint | Outcome |
|---|---|---|
| Pandectes (cookie consent) | pandectes-*.{png,js,json}, snippet, theme.liquid render | UNINSTALLED — files + injections removed |
| Booster Apps | booster-apps-common.liquid, theme.liquid include | UNINSTALLED — removed |
| YMQ B2B | templates/search.ymq.b2b.liquid | UNINSTALLED — removed |
| Popup (pop_36879859845.js) | orphaned asset, no references | REMOVED |
| PageFly | (already gone) | confirmed uninstalled |
| Judge.me, Shopify Inbox, gdpr-cookie-consent | settings_data app blocks | KEPT (still in use) |
| UnlimitedFonts | theme.liquid metafield render | KEPT (still in use) |
```

- [ ] **Step 4: Inventory committed (done)**

```bash
test "$(git branch --show-current)" = "current" && exit 1
git add docs/superpowers/inventory/2026-06-17-divergence-inventory.md
git commit -m "docs: proposed divergence inventory + app audit for user ruling"
```

- [ ] **Step 5: GATE — user reviews and rules on every file**

STOP. Present the inventory to the user. The user edits the "User ruling" column for every row
(confirm or override the proposed layer; mark per-hunk files). Do not proceed to Task 3 until the
user has ruled on every file. Record their rulings back into the document and re-commit.

---

## Task 3: Derive the per-layer file/hunk manifests from approved rulings

**Files:**
- Create: `docs/superpowers/inventory/manifest-L1.txt`, `manifest-L2-files.txt`, `manifest-L2-config.txt`, `manifest-drop.txt`

- [ ] **Step 1: Guard** — `test "$(git branch --show-current)" != "current" && echo OK || exit 1` → `OK`

- [ ] **Step 2: From the approved inventory, write one manifest file per bucket**

Manually populate newline-separated path lists from the **approved** rulings:
- `manifest-L1.txt` — generic code (or files needing per-hunk L1 extraction) ruled L1.
- `manifest-L2-files.txt` — **discrete** store files (custom `product.*.json` templates,
  `page.store_finder.liquid`, `theme.liquid` tracking, etc.) → each gets its **own logical commit**
  (commit hygiene). These stay recognizable in history.
- `manifest-L2-config.txt` — the **config blob**: `settings_data.json` + the layout JSON it
  co-evolves with (`sections/*-group.json`, stock `templates/*.json`) → **one snapshot commit**.
- `manifest-drop.txt` — files to revert-to-vanilla / remove in Task 7b (e.g. `templates/password.json`
  pure churn); included in staging v1 for the lossless test, then removed with documented justification.

Locale files, `translation.yml`, `release-notes.md`, and `config/settings_schema.json` are
**omitted from all manifests** (upstream-reconcile): pulled from `origin/current` into staging v1
verbatim for the lossless test, and reconciled when `dawn-vanilla` is ff'd to 15.2.0.
**Exception:** any locale *keys* that exist only to support an L1 feature (e.g. `pick_up_unavailable`)
ride with L1 — note these in the inventory and add them in Task 4.

- [ ] **Step 3: Verify the manifests + upstream-reconcile files partition the net delta exactly once**

Run:
```bash
MB=$(git merge-base upstream/main origin/current)
# upstream-reconcile files (no manifest)
{ git diff --name-only $MB..origin/current -- 'locales/*' translation.yml release-notes.md config/settings_schema.json; } | sort -u > /tmp/upstream-reconcile.txt
# all manifests + upstream-reconcile
cat docs/superpowers/inventory/manifest-L1.txt \
    docs/superpowers/inventory/manifest-L2-files.txt \
    docs/superpowers/inventory/manifest-L2-config.txt \
    docs/superpowers/inventory/manifest-drop.txt \
    /tmp/upstream-reconcile.txt \
  | sort -u > /tmp/classified.txt
git diff --name-only $MB..origin/current | sort -u > /tmp/changed.txt
diff /tmp/changed.txt /tmp/classified.txt && echo "OK: every net-delta file is classified exactly once"
```
Expected: `OK: every net-delta file is classified exactly once`. Any diff = a file missed or double-counted; fix the manifests.

- [ ] **Step 4: Commit the manifests**

```bash
git add docs/superpowers/inventory/manifest-*.txt
git commit -m "docs: per-layer manifests derived from approved inventory rulings"
```

---

## Task 4: Build `customizations` (L1) on top of `dawn-vanilla`

**Files:** branch `customizations`; content = approved L1 files/hunks only.

- [ ] **Step 1: Guard + create the branch from vanilla**

Run:
```bash
test "$(git branch --show-current)" != "current" && echo OK || exit 1
git branch customizations dawn-vanilla
git checkout customizations
```
Expected: `OK`, then on branch `customizations`.

- [ ] **Step 2: Apply whole-file L1 changes**

For each file in `manifest-L1.txt` that is L1 *in full*, take `current`'s version:
```bash
while read f; do git checkout origin/current -- "$f"; done < docs/superpowers/inventory/manifest-L1.txt
git status --short
```
Expected: the L1 files staged as modified/added.

- [ ] **Step 3: For per-hunk files, keep ONLY the L1 hunks**

For each file flagged per-hunk (e.g. `layout/theme.liquid`, `sections/main-product.liquid`,
`config/settings_schema.json`), interactively select hunks:
```bash
git checkout origin/current -- <file>        # bring full change in
git reset -q HEAD <file>                       # unstage
git restore --source=dawn-vanilla --worktree <file>  # back to vanilla in worktree, then re-add L1 hunks:
git checkout -p origin/current -- <file>       # choose only the generic (L1) hunks; leave store/app hunks out
```
Expected: only generic hunks present in the worktree copy. Store hunks for these files are
deferred to L2 in later tasks.

- [ ] **Step 4: Commit L1 as feature-grouped commits**

Group related files into meaningful commits (not one giant commit). For this store, L1 is small —
e.g.:
```bash
git add sections/pickup-availability.liquid
git commit -m "L1: pickup availability unavailable-state"
git add sections/main-product.liquid assets/component-product-logos.css
git commit -m "L1: inventory-status options + tag-based product-logos block"
# + add any L1-feature locale keys (e.g. pick_up_unavailable) per the inventory
```

- [ ] **Step 5: Verify `customizations` carries NO L2/drop files**

Run:
```bash
git diff --name-only dawn-vanilla..customizations | grep -Ef <(sed 's/[.[]/\\&/g' docs/superpowers/inventory/manifest-L2-files.txt docs/superpowers/inventory/manifest-L2-config.txt docs/superpowers/inventory/manifest-drop.txt) && echo "LEAK: L2 file in customizations" || echo "OK: customizations is L1-only"
```
Expected: `OK: customizations is L1-only`.

---

## Task 5: Pre-stage check — confirm L1 + remaining layers can reconstruct current

**Files:** none (dry-run verification)

- [ ] **Step 1: Guard** — `test "$(git branch --show-current)" != "current" && echo OK || exit 1`

- [ ] **Step 2: Snapshot what's still missing vs current after L1**

Run:
```bash
git diff --name-only customizations..origin/current | sort -u > /tmp/remaining.txt
cat docs/superpowers/inventory/manifest-L2-files.txt docs/superpowers/inventory/manifest-L2-config.txt docs/superpowers/inventory/manifest-drop.txt /tmp/upstream-reconcile.txt | sort -u > /tmp/expected-remaining.txt
diff /tmp/remaining.txt /tmp/expected-remaining.txt && echo "OK: remaining delta == L2-files+L2-config+drop+upstream-reconcile" || echo "MISMATCH: investigate per-hunk leakage"
```
Expected: `OK`. A mismatch means a per-hunk L1 file still differs from current in non-L1 ways
(expected for per-hunk files) OR a misclassification — review. Note: per-hunk files legitimately
appear in `remaining` (their L2 hunks aren't applied yet); they should also be listed in an L2
manifest. Reconcile until the diff is clean.

---

## Task 6: Build `staging` v1 — lossless (everything from current, including future drops)

**Files:** branch `staging`; content = `customizations` + every remaining file from current,
**including** files earmarked for dropping. Drops happen only in Task 7 (after the acceptance
test passes). This guarantees the restructure is lossless before any curation.

- [ ] **Step 1: Guard + create `staging` from `customizations`**

```bash
test "$(git branch --show-current)" != "current" && echo OK || exit 1
git branch staging customizations
git checkout staging
```

- [ ] **Step 2: Apply L2 discrete store files — each as its OWN logical commit (commit hygiene)**

```bash
while read f; do git checkout origin/current -- "$f"; done < docs/superpowers/inventory/manifest-L2-files.txt
# one logical commit per recognizable unit — do NOT lump these together:
git add templates/product.workshop.json templates/product.soap.json templates/product.geurblokje.json \
        templates/product.badzout.json templates/product.facialmask.json templates/product.3rd-party-product.json
git commit -m "L2: custom store product templates (workshop, soap, geurblokje, badzout, facialmask, 3rd-party)"
git add templates/page.store_finder.liquid
git commit -m "L2: store-finder custom page template"
# theme.liquid store hunks (GTM + UnlimitedFonts) applied via per-hunk in Step 4
```

- [ ] **Step 3: Apply files earmarked for dropping — INCLUDED HERE for lossless test**

```bash
while read f; do git checkout origin/current -- "$f"; done < docs/superpowers/inventory/manifest-drop.txt
git add --all
git commit -m "staging-lossless: include all drop-targets for acceptance test (removed/reverted in Task 7b)"
```
`manifest-drop.txt` lists every file ruled `drop` (e.g. `templates/password.json`, reverted to
vanilla later). They land here so the tree matches `current` exactly.

- [ ] **Step 4: Apply the L2 config blob as ONE snapshot commit**

```bash
while read f; do git checkout origin/current -- "$f"; done < docs/superpowers/inventory/manifest-L2-config.txt
git add config/settings_data.json sections/*-group.json templates/*.json
git commit -m "L2: store config snapshot (settings_data, section groups, stock template layouts)"
```

- [ ] **Step 5: Apply remaining per-hunk L2 hunks for per-hunk files**

For each per-hunk file, bring it fully to current's version (the L2/app hunks missing from L1):
```bash
git checkout origin/current -- <file>
git commit -m "L2: per-hunk remainder for <file>"
```
After all per-hunk files, every such file matches current exactly.

- [ ] **Step 6: Pull upstream-reconcile files for the lossless acceptance test**

Locales, `translation.yml`, `release-notes.md`, and `config/settings_schema.json` carry upstream
content. Include them now so the acceptance test can pass, with no special labelling:
```bash
git checkout origin/current -- locales/ translation.yml release-notes.md config/settings_schema.json
git add locales/ translation.yml release-notes.md config/settings_schema.json
git commit -m "staging-lossless: upstream-reconcile files from current (auto-reconcile on dawn-vanilla ff to 15.2.0)"
```
Note: L1-feature locale keys already added in Task 4 will be overwritten here by current's full
locale files — that's fine for the lossless test; at the next Dawn ff, re-apply the L1 keys on top
of the new upstream locales (runbook covers this).

---

## Task 7: ACCEPTANCE TEST — staging v1 reproduces current byte-for-byte

**Files:** none (the master verification — runs before any drops are applied)

- [ ] **Step 1: Guard** — `test "$(git branch --show-current)" != "current" && echo OK || exit 1`

- [ ] **Step 2: Compare the full `staging` tree against today's `current` tree**

```bash
git diff --stat staging origin/current -- . ':(exclude)docs/'
```
Expected: **empty output**. Empty = the restructure is provably lossless.

- [ ] **Step 3: Hard tree-hash equality check**

```bash
git diff --quiet staging origin/current -- . ':(exclude)docs/' && \
  echo "PASS: staging tree == current tree" || \
  echo "FAIL: trees differ — DO NOT proceed"
```
Expected: `PASS: staging tree == current tree`.

- [ ] **Step 4: If FAIL, diagnose (never edit `current`)**

```bash
git diff --name-only staging origin/current -- . ':(exclude)docs/'
```
For each listed file, identify which manifest it belongs to and fix the corresponding build step.
Re-run Step 3 until PASS.

- [ ] **Step 5: Record the lossless-pass in the anchors file**

```bash
git checkout repo-cleanup
echo "Lossless acceptance test PASS $(date -u +%FT%TZ): staging tree == origin/current (excl docs/)" >> docs/superpowers/inventory/.anchors.txt
git add docs/superpowers/inventory/.anchors.txt
git commit -m "chore: record lossless acceptance-test pass (staging v1 == current byte-for-byte)"
```

---

## Task 7b: Apply curation — remove drop-candidates with documented justification

**Files:**
- Create: `docs/superpowers/inventory/drops.md`

This task runs **only after Task 7 passes**. It produces the single named commit that explains
every delta between final `staging` and `current`. Future `git diff current..staging` is fully
explained by `git show` on this commit.

- [ ] **Step 1: Guard + switch to staging**

```bash
test "$(git branch --show-current)" != "current" && echo OK || exit 1
git checkout staging
```

- [ ] **Step 2: Write the drops record**

Create `docs/superpowers/inventory/drops.md` listing every file being removed, the reason, and
the admin-confirmation note. Example:

```markdown
# Curated drops from staging

These files exist in `current` (and passed the lossless acceptance test in Task 7) but are
removed from `staging` because they are orphaned or unused. Any `git diff current..staging`
showing these files absent is expected and intentional.

| File | Reason | Admin confirmed? |
|---|---|---|
| `assets/pop_36879859845.js` | No active reference in theme.liquid or settings_data; numeric-ID popup asset, likely orphaned | (fill in) |
```

- [ ] **Step 3: Remove the drop-candidate files and commit with the record**

```bash
while read f; do git rm --force "$f"; done < docs/superpowers/inventory/manifest-drop-candidates.txt
git add docs/superpowers/inventory/drops.md
git commit -m "chore: remove orphaned/unused files — see docs/superpowers/inventory/drops.md"
```

- [ ] **Step 4: Verify the final staging state is clean**

```bash
# The only diff vs current should be: docs/ additions + the dropped files (all documented)
git diff --name-only staging origin/current -- . ':(exclude)docs/' | sort -u
# Cross-check: every file listed here must appear in manifest-drop-candidates.txt
diff \
  <(git diff --name-only staging origin/current -- . ':(exclude)docs/' | sort -u) \
  <(sort -u docs/superpowers/inventory/manifest-drop-candidates.txt) \
  && echo "PASS: all deltas are documented drops" \
  || echo "FAIL: unexpected delta — investigate"
```
Expected: `PASS: all deltas are documented drops`.

---

## Task 8: Write the operating runbook

**Files:**
- Create: `docs/superpowers/runbook/dawn-update-and-promote.md`

- [ ] **Step 1: Guard** — `test "$(git branch --show-current)" != "current" && echo OK || exit 1`

- [ ] **Step 2: Write the runbook** covering exactly these procedures, with copy-paste commands:

1. **Backflow** (capture live admin edits): `git checkout staging && git merge origin/current` — resolve so config lands in the config-snapshot commit; harvest any new generic edit to `customizations`, any new discrete store file into its own L2 commit.
2. **Promote to live** (only after a fresh backflow): set `current` to `staging`'s tree and push.
   Document this as the *single* sanctioned way `current` is ever updated, with the backflow-first
   invariant in bold and a pre-flight checklist.
3. **Dawn version upgrade:** `git checkout dawn-vanilla && git merge --ff-only v<new>` → `git rebase dawn-vanilla customizations` (resolve once) → rebuild `staging` (drop the locale-drift commit; take new Dawn locales) → test in preview theme → backflow → promote.
4. **Harvest** recipe: lifting a bundled generic edit from `staging`/`current` onto `customizations`.
5. **Preview-theme linkage:** how the user links `staging` to a non-live theme in Shopify admin.

- [ ] **Step 3: Commit the runbook**

```bash
git add docs/superpowers/runbook/dawn-update-and-promote.md
git commit -m "docs: Dawn update + promote/backflow runbook"
```

---

## Task 9: Branch-zoo triage proposal (no destructive action)

**Files:**
- Create: `docs/superpowers/inventory/branch-triage.md`

- [ ] **Step 1: Guard** — `test "$(git branch --show-current)" != "current" && echo OK || exit 1`

- [ ] **Step 2: Enumerate every local + origin branch with its relationship to the new model**

```bash
for b in $(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin); do
  echo "$b | merged-into-current: $(git merge-base --is-ancestor "$b" origin/current 2>/dev/null && echo yes || echo no) | ahead-of-current: $(git rev-list --count origin/current.."$b" 2>/dev/null)"
done > docs/superpowers/inventory/branch-triage.md
```

- [ ] **Step 3: Annotate each with a proposed disposition** — keep / archive-as-tag / delete —
  (e.g. `update-to-*` = superseded by the new upgrade flow → archive-as-tag; merged feature
  branches → delete). **Proposal only; no branch is deleted in this plan.**

- [ ] **Step 4: Commit the triage proposal**

```bash
git add docs/superpowers/inventory/branch-triage.md
git commit -m "docs: branch-zoo triage proposal (no destructive action)"
```

- [ ] **Step 5: GATE — user decides cutover & cleanup**

STOP. Present: (a) the verified `staging` line, (b) the runbook, (c) the branch-triage proposal.
The user decides when/whether to: link `staging` to a preview theme, perform the first promote to
`current`, push the new branches, and execute branch deletions. None of these happen without
explicit user authorization.

---

## Self-review notes

- **Spec coverage:** L0 (Task 1), L1 (Task 4), L2 discrete-file commits (Task 6 Step 2, commit hygiene), L2 config-snapshot commit (Task 6 Step 4), inventory+app-audit (Task 2), per-file user ruling (Task 2 Step 5 gate), strict L1 test (Task 2), byte-for-byte acceptance (Task 7 — runs before drops), documented drops (Task 7b — runs after, with drops.md justifying all deltas), runbook incl. backflow/promote/upgrade/harvest (Task 8), branch triage (Task 9), `current` never touched (guards in every task). All spec sections map to tasks.
- **Locale reconciliation:** spec's "locales follow upstream" is a forward policy; the initial lossless rebuild preserves them in a flagged droppable commit (Task 6 Step 5), dropped at first upgrade (Task 8 Step 2 procedure 3).
- **Deferred:** squash-on-backflow churn-control mechanics (spec deferred phase) are referenced in the runbook but not mechanized here.
