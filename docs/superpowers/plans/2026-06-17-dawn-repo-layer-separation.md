# Dawn Repo Layer Separation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the `fcapurso/dawn` fork into clean, layered branches (`dawn-vanilla` → `customizations` → `staging` → `current`) so vanilla Dawn, generic customizations, authored store assets, and config churn are cleanly separated and Dawn upgrades become a repeatable rebase.

**Architecture:** Reconstruct today's `current` tree as a stack of layered commits on top of pinned vanilla Dawn (v15.1.0). A human-ruled inventory assigns every changed file to a layer (L0/L1/L2a/L2b/locale-drift/app-residue). Branches are built from the approved inventory and validated by a byte-for-byte tree comparison against today's `current`. Nothing is built until the inventory is approved; `current` and the live theme are never touched until a separately-chosen cutover.

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

This task produces a *proposed* classification of every changed file. The user rules on each
before any branch is built. The proposed defaults below come from file analysis; the strict L1
test (a stranger could drop the file into vanilla Dawn unchanged) and the L2a tiebreaker apply.

- [ ] **Step 1: Generate the raw changed-file list with status**

Run:
```bash
git diff --name-status v15.1.0..origin/current > /tmp/divergence.txt
wc -l /tmp/divergence.txt
```
Expected: 101 lines.

- [ ] **Step 2: Write the inventory document with a proposed ruling per file**

Create `docs/superpowers/inventory/2026-06-17-divergence-inventory.md` containing the table below.
Columns: File · Status (A/M) · Proposed layer · Confidence · Reasoning · **User ruling (blank)**.

Proposed classification (starting point — user edits the "User ruling" column):

| File | A/M | Proposed | Conf | Reasoning |
|---|---|---|---|---|
| `assets/base.css` | M | L1 | med | core Dawn stylesheet; per-hunk split likely (generic tweaks vs store) |
| `assets/global.js` | M | L1 | med | core Dawn JS; per-hunk review needed |
| `assets/quick-add.css` | M | L1 | high | generic Dawn component CSS |
| `assets/theme-editor.js` | M | L1 | high | generic Dawn editor JS |
| `assets/component-cart.css` | M | L1 | high | generic Dawn component CSS |
| `assets/component-facets.css` | M | L1 | high | generic Dawn component CSS |
| `assets/component-localization-form.css` | M | L1 | high | generic Dawn component CSS |
| `assets/component-product-logos.css` | A | L2a | med | "product/HiB logos" custom feature; may be generic → user rules |
| `assets/pandectes-reopen-logo.png` | A | app-residue | high | Pandectes cookie-consent app asset |
| `assets/pandectes-rules.min.js` | A | app-residue | high | Pandectes app asset |
| `assets/pandectes-settings.json` | A | app-residue | high | Pandectes app config |
| `assets/pop_36879859845.js` | A | app-residue | high | popup-app asset (numeric id) |
| `snippets/pandectes-rules.liquid` | A | app-residue | high | Pandectes app snippet |
| `snippets/booster-apps-common.liquid` | A | app-residue | high | Booster Apps shared snippet |
| `templates/search.ymq.b2b.liquid` | A | app-residue | high | YMQ B2B app search template |
| `templates/page.store_finder.liquid` | A | L2a | med | store-finder page template; app-or-custom → user rules |
| `layout/theme.liquid` | M | L1+app | low | core layout; likely mixes generic edits + injected app `<script>`/`<link>` → per-hunk |
| `layout/password.liquid` | M | L1 | med | core layout; per-hunk review |
| `sections/header.liquid` | M | L1 | med | core section; per-hunk review |
| `sections/main-product.liquid` | M | L1+L2a | low | inventory-status feature (generic?) vs store specifics → per-hunk |
| `sections/pickup-availability.liquid` | M | L1 | med | "pickup for items in 1 location" — likely generic enhancement |
| `sections/email-signup-banner.liquid` | M | L1 | med | core section; per-hunk review |
| `snippets/facets.liquid` | M | L1 | med | core snippet; per-hunk review |
| `snippets/header-drawer.liquid` | M | L1 | med | core snippet; per-hunk review |
| `sections/header-group.json` | M | L2b | high | section/block placement = config snapshot |
| `sections/footer-group.json` | M | L2b | high | section/block placement = config snapshot |
| `config/settings_data.json` | M | L2b | high | the config snapshot |
| `config/settings_schema.json` | M | L1+L2b | low | schema edits may be generic; store color schemes = config → per-hunk |
| `templates/index.json` | M | L2b | high | homepage layout = config snapshot |
| `templates/cart.json` | M | L2b | high | template layout config |
| `templates/collection.json` | M | L2b | high | template layout config |
| `templates/article.json` | M | L2b | high | template layout config |
| `templates/blog.json` | M | L2b | high | template layout config |
| `templates/password.json` | M | L2b | high | template layout config |
| `templates/product.json` | M | L2b | high | default product layout config |
| `templates/product.workshop.json` | A | L2a | high | custom store product template |
| `templates/product.soap.json` | A | L2a | high | custom store product template |
| `templates/product.geurblokje.json` | A | L2a | high | custom store product template |
| `templates/product.badzout.json` | A | L2a | high | custom store product template |
| `templates/product.facialmask.json` | A | L2a | high | custom store product template |
| `templates/product.3rd-party-product.json` | A | L2a | high | custom store product template |
| `locales/*` (58 files) | M | locale-drift | high | translation-bot churn; preserved now, dropped at next Dawn upgrade |
| `translation.yml` | M | locale-drift | med | translation config churn |
| `release-notes.md` | M | L0-noise | high | Dawn release notes; follow upstream |

- [ ] **Step 3: Append the app audit section to the inventory document**

Add a section listing each detected app, its theme footprint, and a "likely unused?" flag for
the user to confirm in admin:

```markdown
## App audit (code+config inference — confirm in admin)
| App | Footprint (files) | Notes |
|---|---|---|
| Pandectes (cookie consent) | pandectes-*.{png,js,json}, snippets/pandectes-rules.liquid | active footprint present |
| Booster Apps | snippets/booster-apps-common.liquid | shared snippet; check which Booster app still installed |
| YMQ B2B | templates/search.ymq.b2b.liquid | B2B search; confirm still used |
| Popup app | assets/pop_36879859845.js | numeric-id asset; identify & confirm |
| PageFly (page builder) | NONE (removed) | `pagefly-main-css.liquid` in history, not tracked → likely uninstalled/unused |
```

Also grep `layout/theme.liquid` and `config/settings_data.json` for app references to enrich the audit:
```bash
grep -nE 'pandectes|booster|ymq|pagefly|app-block|shopify-app|\.apps\.' layout/theme.liquid config/settings_data.json | head -40
```

- [ ] **Step 4: Commit the proposed inventory**

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
- Create: `docs/superpowers/inventory/manifest-L1.txt`, `manifest-L2a.txt`, `manifest-L2b.txt`, `manifest-drop.txt`

- [ ] **Step 1: Guard** — `test "$(git branch --show-current)" != "current" && echo OK || exit 1` → `OK`

- [ ] **Step 2: From the approved inventory, write one manifest file per layer**

Manually populate four newline-separated path lists from the **approved** rulings:
- `manifest-L1.txt` — files (or files needing per-hunk extraction) ruled L1.
- `manifest-L2a.txt` — added/custom store files ruled L2a (incl. app-residue the user wants to keep).
- `manifest-L2b.txt` — config-snapshot files (settings_data, *-group.json, template *.json).
- `manifest-drop.txt` — locale-drift, release-notes, and any app-residue the user wants gone.

- [ ] **Step 3: Verify the manifests partition ALL 101 changed files exactly once**

Run:
```bash
cat docs/superpowers/inventory/manifest-*.txt | sort -u > /tmp/classified.txt
git diff --name-only v15.1.0..origin/current | sort -u > /tmp/changed.txt
diff /tmp/changed.txt /tmp/classified.txt && echo "OK: every changed file is classified exactly once"
```
Expected: `OK: every changed file is classified exactly once`. Any diff = a file missed or double-counted; fix the manifests.

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
Expected: only generic hunks present in the worktree copy. Store/app hunks for these files are
deferred to L2a/L2b in later tasks.

- [ ] **Step 4: Commit L1 as feature-grouped commits**

Group related files into meaningful commits (not one giant commit). Example grouping:
```bash
git add assets/quick-add.css assets/component-*.css
git commit -m "L1: generic component CSS tweaks"
git add sections/pickup-availability.liquid
git commit -m "L1: pickup availability for single-location items"
# ...repeat per feature group per the inventory...
```

- [ ] **Step 5: Verify `customizations` carries NO L2a/L2b/app files**

Run:
```bash
git diff --name-only dawn-vanilla..customizations | grep -Ef <(sed 's/[.[]/\\&/g' docs/superpowers/inventory/manifest-L2a.txt docs/superpowers/inventory/manifest-L2b.txt) && echo "LEAK: L2 file in customizations" || echo "OK: customizations is L1-only"
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
cat docs/superpowers/inventory/manifest-L2a.txt docs/superpowers/inventory/manifest-L2b.txt docs/superpowers/inventory/manifest-drop.txt | sort -u > /tmp/expected-remaining.txt
diff /tmp/remaining.txt /tmp/expected-remaining.txt && echo "OK: remaining delta == L2a+L2b+drop" || echo "MISMATCH: investigate per-hunk leakage"
```
Expected: `OK: remaining delta == L2a+L2b+drop`. A mismatch means a per-hunk L1 file still
differs from current in non-L1 ways (expected for per-hunk files) OR a misclassification — review.
Note: per-hunk files legitimately appear in `remaining` (their L2 hunks aren't applied yet); they
should also be listed in L2a/L2b manifests. Reconcile until the diff is clean.

---

## Task 6: Build `staging` (L2a curated + L2b snapshot + locale-drift)

**Files:** branch `staging`; content = `customizations` + every remaining file from current.

- [ ] **Step 1: Guard + create `staging` from `customizations`**

```bash
test "$(git branch --show-current)" != "current" && echo OK || exit 1
git branch staging customizations
git checkout staging
```

- [ ] **Step 2: Apply L2a authored store assets as feature-grouped commits**

```bash
while read f; do git checkout origin/current -- "$f"; done < docs/superpowers/inventory/manifest-L2a.txt
git add templates/product.*.json
git commit -m "L2a: custom store product templates (workshop, soap, geurblokje, badzout, facialmask, 3rd-party)"
git add templates/page.store_finder.liquid assets/component-product-logos.css
git commit -m "L2a: store-finder page + product logos"
# app-residue the user chose to KEEP:
git add snippets/pandectes-rules.liquid assets/pandectes-* snippets/booster-apps-common.liquid templates/search.ymq.b2b.liquid assets/pop_36879859845.js
git commit -m "L2a: app-injected files (Pandectes, Booster, YMQ B2B, popup) — retained app residue"
```

- [ ] **Step 3: Apply L2b config snapshot as ONE commit**

```bash
while read f; do git checkout origin/current -- "$f"; done < docs/superpowers/inventory/manifest-L2b.txt
git add config/settings_data.json config/settings_schema.json sections/*-group.json templates/*.json
git commit -m "L2b: store config snapshot (settings_data, section groups, template layouts)"
```

- [ ] **Step 4: Apply remaining per-hunk L2 hunks for L1 files**

For each per-hunk file, now add the store/app hunks that were excluded from L1:
```bash
git checkout origin/current -- <file>   # bring file fully to current's version
```
After all per-hunk files, every such file matches current exactly.

- [ ] **Step 5: Apply locale-drift as ONE flagged, droppable commit**

```bash
while read f; do git checkout origin/current -- "$f"; done < docs/superpowers/inventory/manifest-drop.txt
git add locales/ translation.yml release-notes.md
git commit -m "locale-drift: translation-bot churn — DROP at next Dawn upgrade (do not carry forward)"
```

---

## Task 7: ACCEPTANCE TEST — staging reproduces current byte-for-byte

**Files:** none (the master verification)

- [ ] **Step 1: Guard** — `test "$(git branch --show-current)" != "current" && echo OK || exit 1`

- [ ] **Step 2: Compare the full `staging` tree against today's `current` tree**

Run:
```bash
git diff --stat staging origin/current -- . ':(exclude)docs/'
```
Expected: **empty output** (no differences outside the `docs/` planning dir, which exists only on
the cleanup line). Empty = the restructure is provably lossless.

- [ ] **Step 3: Hard tree-hash equality check (excluding docs/)**

Run:
```bash
git diff --quiet staging origin/current -- . ':(exclude)docs/' && echo "PASS: staging tree == current tree" || echo "FAIL: trees differ — DO NOT promote"
```
Expected: `PASS: staging tree == current tree`.

- [ ] **Step 4: If FAIL, diagnose (never edit `current`)**

```bash
git diff --name-only staging origin/current -- . ':(exclude)docs/'
```
For each listed file, identify which manifest it belongs to and fix the corresponding build task.
Re-run Step 3 until PASS. Today's `current` and the live theme remain untouched throughout.

- [ ] **Step 5: Commit a verification record**

```bash
git checkout repo-cleanup
echo "Acceptance test PASS $(date -u +%FT%TZ): staging tree == origin/current (excl docs/)" >> docs/superpowers/inventory/.anchors.txt
git add docs/superpowers/inventory/.anchors.txt
git commit -m "chore: record acceptance-test pass (staging == current byte-for-byte)"
```

---

## Task 8: Write the operating runbook

**Files:**
- Create: `docs/superpowers/runbook/dawn-update-and-promote.md`

- [ ] **Step 1: Guard** — `test "$(git branch --show-current)" != "current" && echo OK || exit 1`

- [ ] **Step 2: Write the runbook** covering exactly these procedures, with copy-paste commands:

1. **Backflow** (capture live admin edits): `git checkout staging && git merge origin/current` — resolve so config lands in the L2b snapshot; harvest any new generic edit to `customizations`, any new file to L2a.
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

- **Spec coverage:** L0 (Task 1), L1 (Task 4), L2a (Task 6 Step 2), L2b (Task 6 Step 3), inventory+app-audit (Task 2), per-file user ruling (Task 2 Step 5 gate), strict L1 test (Task 2), byte-for-byte acceptance (Task 7), runbook incl. backflow/promote/upgrade/harvest (Task 8), branch triage (Task 9), `current` never touched (guards in every task). All spec sections map to tasks.
- **Locale reconciliation:** spec's "locales follow upstream" is a forward policy; the initial lossless rebuild preserves them in a flagged droppable commit (Task 6 Step 5), dropped at first upgrade (Task 8 Step 2 procedure 3).
- **Deferred:** squash-on-backflow churn-control mechanics (spec deferred phase) are referenced in the runbook but not mechanized here.
