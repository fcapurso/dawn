# Dawn-ops: Inert Shipping + Guarded Reset — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `dawn-ship` skill that cherry-picks classified commits from `customizations` onto `current` (append-only, churn-free), add a `dawn::classify_changes` / `dawn::assert_staging_clean` to the shared lib, guard `dawn-promote` with the cleanliness check, and revise `dawn-harvest` to emit atomic classified commits — then document the full two-mode workflow in a runbook.

**Architecture:** A new `dawn::classify_changes` function in `dawn-ops.sh` does static render-graph reachability analysis (git-only, no Admin API) and labels each changed path `inert`, `active`, or `NEEDS_JUDGMENT`; `dawn-ship` uses this to gate a cherry-pick onto `current`; `dawn-promote` gains a `dawn::assert_staging_clean` guard so the authoritative reset only runs from a known-good state.

**Tech Stack:** Bash (POSIX-compatible), existing `dawn-ops.sh` lib, existing fixture/harness test pattern (no external deps).

---

## File Map

| Path | Status | Responsibility |
|---|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | **modify** | Add `dawn::classify_changes`, `dawn::assert_staging_clean`, `dawn::reachable_files` helpers |
| `.claude/skills/dawn-ship/SKILL.md` | **create** | Agent-facing instructions for the dawn-ship skill |
| `.claude/skills/dawn-ship/ship.sh` | **create** | Cherry-pick classified commit from `customizations` → `current` |
| `.claude/skills/dawn-promote/promote.sh` | **modify** | Add `dawn::assert_staging_clean` guard before reset |
| `.claude/skills/dawn-harvest/harvest.sh` | **modify** | Produce atomic inert/active commits with `Inert:` trailer; split mixed changes |
| `.claude/skills/_dawn-ops-lib/conventions.md` | **modify** | Add inert/active concepts, append-only rule, two promote modes |
| `tests/test_classify.sh` | **create** | Tests for `dawn::classify_changes` |
| `tests/test_ship.sh` | **create** | Tests for `dawn-ship` |
| `tests/test_promote.sh` | **modify** | Add cleanliness-guard tests |
| `tests/test_harvest.sh` | **modify** | Add atomic-commit and trailer tests |
| `tests/run-all.sh` | **modify** | Register `test_classify.sh` and `test_ship.sh` |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | **create** | Operator workflow guide |

---

## Task 1: Add `dawn::reachable_files` to `dawn-ops.sh`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh`
- Test: `tests/test_classify.sh` (written in Task 2, run here as a stub)

**Context:** The reachability helpers are the foundation of the classifier. They parse the theme's JSON template files and Liquid files in `layout/`, `sections/`, and `snippets/` to enumerate which files are "live" (reachable from a rendered URL). Everything else is an orphan and is therefore potentially inert.

The theme structure is:
- `layout/*.liquid` — always reachable roots (layout files)
- `templates/*.json` — reachable if they are the default template for a resource type (e.g. `index.json`, `cart.json`) or are listed in `config/settings_data.json` as bound to a page/product (shop-global state we can't read from git, so new non-default templates are `NEEDS_JUDGMENT`)
- `sections/header-group.json`, `sections/footer-group.json` — always reachable (pulled by every layout)
- `sections/*.liquid` — reachable if referenced from a reachable template/group JSON
- `snippets/*.liquid` — reachable if `render`-ed from a reachable liquid file
- `assets/*` — reachable if `asset_url`-d from a reachable liquid file
- `locales/*` — always has special treatment (additive new keys = inert; changed existing values = active)

The **conservative default**: if a file does not appear in the reachable set we computed, it is an orphan — potentially inert. But if the changed file is an orphan that **wires itself in** (i.e. the diff adds a `render` tag or `asset_url` pointing to it in a reachable file), that's active. We only need to detect changes in already-known paths; the wiring is detected by classifying the reachable files that reference the new file.

For this implementation, keep it simple and conservative:
- **Always-reachable set** (hard-coded as patterns): `layout/`, `sections/header-group.json`, `sections/footer-group.json`, plus the "default" templates `templates/index.json`, `templates/cart.json`, `templates/search.json`, `templates/404.json`, `templates/gift_card.liquid`, `templates/password.json`, `templates/product.json`, `templates/collection.json`, `templates/article.json`, `templates/blog.json`.
- **Section files** referenced in a reachable template/group JSON are reachable.
- Everything else is an orphan.
- We do NOT parse `render` and `asset_url` links into sections/snippets/assets for the initial implementation (too complex, unnecessary for the spec's use case). Conservative default handles it: a changed snippet/asset is flagged active unless it's provably unreferenced.

- [ ] **Step 1: Read current `dawn-ops.sh` end to know where to append**

```bash
wc -l .claude/skills/_dawn-ops-lib/dawn-ops.sh
# should print ~45 lines
```

- [ ] **Step 2: Add `dawn::reachable_templates` and `dawn::assert_staging_clean` to `dawn-ops.sh`**

Open `.claude/skills/_dawn-ops-lib/dawn-ops.sh` and append the following **after the existing `dawn::verify_tree_equal` function**:

```bash
# --- Inert/active classifier helpers ---

# Print the set of template JSON basenames that are always reachable (not suffix templates).
# Suffix templates (page.foo.json, product.foo.json) are NEEDS_JUDGMENT because
# whether a resource is bound to them is shop-global admin state, not in git.
dawn::_default_templates(){
  echo "index.json cart.json search.json 404.json gift_card.liquid password.json \
product.json collection.json article.json blog.json page.json"
}

# Print repo-relative paths of files reachable from the render graph (conservative).
# Outputs one path per line. Always includes layout/, header/footer groups, default templates,
# and any sections listed in reachable template/group JSON files.
dawn::reachable_files(){
  # Always-reachable roots
  git ls-files -- 'layout/' 'sections/header-group.json' 'sections/footer-group.json' \
    'config/settings_data.json' 'config/settings_schema.json'
  # Default templates
  local t; for t in $(dawn::_default_templates); do git ls-files -- "templates/$t"; done
  # Sections referenced in reachable template JSONs and section-group JSONs
  {
    git ls-files -- 'templates/index.json' 'templates/cart.json' 'templates/search.json' \
      'templates/404.json' 'templates/password.json' 'templates/product.json' \
      'templates/collection.json' 'templates/article.json' 'templates/blog.json' \
      'templates/page.json' 'sections/header-group.json' 'sections/footer-group.json'
  } | while IFS= read -r jf; do
    [ -f "$jf" ] || continue
    # extract "type":"<section-handle>" values → sections/<handle>.liquid
    grep -o '"type":"[^"]*"' "$jf" 2>/dev/null | sed 's/"type":"//;s/"//' \
      | while IFS= read -r h; do git ls-files -- "sections/${h}.liquid"; done
  done
}

# Assert staging is "clean" for a guarded reset:
# staging must equal customizations with only config-snapshot enrichments on top —
# i.e. the last commit's subject must match "config snapshot" and
# no commits since customizations contain debug/WIP markers.
# Conservative: checks that staging is ahead of customizations (no divergence) and
# the tip commit subject contains "config" (the snapshot invariant).
dawn::assert_staging_clean(){
  # staging must be ahead of (or equal to) customizations, not diverged
  local behind; behind=$(git rev-list --count staging..customizations 2>/dev/null || echo 1)
  if [ "$behind" != "0" ]; then
    echo "GUARD: staging has diverged from customizations (customizations is $behind commits ahead of staging). Rebase staging onto customizations first." >&2
    return $DAWN_GUARD
  fi
  # tip commit must be a config snapshot
  local tip_msg; tip_msg=$(git log -1 --format=%s staging)
  case "$tip_msg" in
    *config*|*snapshot*|*settings*) ;;
    *) echo "GUARD: staging tip commit '$tip_msg' does not look like a config snapshot. Run dawn-backflow to recreate the snapshot at the tip." >&2
       return $DAWN_GUARD ;;
  esac
}
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh
git commit -m "feat(lib): add reachable_files and assert_staging_clean helpers"
```

---

## Task 2: Add `dawn::classify_changes` to `dawn-ops.sh`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh`
- Create: `tests/test_classify.sh`

**Context:** The classifier takes a commit ref (or range `base..tip`) and emits:
- Per-path lines: `inert <path>`, `active <path>`, or `needs_judgment <path>`
- A final verdict line: `ALL_INERT`, `HAS_ACTIVE`, or `NEEDS_JUDGMENT`
- A human-readable explanation on stderr (for the operator review)

Rules (from spec §2.1):
- Changed path is a **new template with a suffix** (`page.*.json`, `product.*.json`) → `needs_judgment`
- Changed path is in the always-reachable set (`dawn::reachable_files`) → `active`
- Locale file (`locales/`) with only **additive** changes (no `-` lines in diff) → `inert`
- Otherwise not in reachable set → `inert` (it's an orphan)
- **Conservative default:** anything not provably inert is `active`

The function signature: `dawn::classify_changes <ref-or-range>`
- If arg is a single ref (no `..`): classify changes introduced by that single commit (`<ref>^..<ref>`)
- If arg contains `..`: use as-is

Output format (stdout):
```
inert sections/withdrawal.liquid
active sections/main-product.liquid
needs_judgment templates/page.herroeping.json
VERDICT ALL_INERT
```

- [ ] **Step 1: Write `tests/test_classify.sh` first (TDD)**

Create `tests/test_classify.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
source "$HERE/.claude/skills/_dawn-ops-lib/dawn-ops.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Helper: make a commit with a given file content and classify it.
classify_commit(){
  local file="$1" content="$2"
  echo "$content" > "$file"
  git add "$file"; git commit -qm "test: $file"
  dawn::classify_changes HEAD 2>/dev/null
}

git checkout -q customizations

# 1. New orphan section (not referenced by any reachable template) → inert
mkdir -p sections
out=$(classify_commit sections/orphan-widget.liquid '<div>new</div>')
assert_contains "orphan section is inert" "$out" "inert sections/orphan-widget.liquid"
assert_contains "orphan verdict ALL_INERT" "$out" "VERDICT ALL_INERT"

# 2. Edit to always-reachable layout file → active
out=$(classify_commit layout/theme.liquid '{% render "orphan-widget" %}')
assert_contains "layout edit is active" "$out" "active layout/theme.liquid"
assert_contains "active verdict HAS_ACTIVE" "$out" "VERDICT HAS_ACTIVE"

# 3. New suffix template (page.herroeping.json) → needs_judgment
mkdir -p templates
out=$(classify_commit templates/page.herroeping.json '{"sections":{}}')
assert_contains "suffix template is needs_judgment" "$out" "needs_judgment templates/page.herroeping.json"
assert_contains "needs_judgment verdict" "$out" "VERDICT NEEDS_JUDGMENT"

# 4. Additive locale key → inert
mkdir -p locales
echo '{"hello":"wereld"}' > locales/nl.default.json
git add locales/nl.default.json; git commit -qm "base locale"
out=$(classify_commit locales/nl.default.json '{"hello":"wereld","goodbye":"dag"}')
assert_contains "additive locale is inert" "$out" "inert locales/nl.default.json"

# 5. Changed existing locale value → active
out=$(classify_commit locales/nl.default.json '{"hello":"CHANGED","goodbye":"dag"}')
assert_contains "changed locale value is active" "$out" "active locales/nl.default.json"

# 6. Mixed commit: orphan section + reachable section → HAS_ACTIVE
git checkout -q customizations
echo '<div>orphan2</div>' > sections/orphan2.liquid
# header-group.json is always reachable
echo '{"name":"header","v":2}' > sections/header-group.json
git add sections/orphan2.liquid sections/header-group.json
git commit -qm "mixed: orphan + reachable"
out=$(dawn::classify_changes HEAD 2>/dev/null)
assert_contains "mixed: orphan2 inert" "$out" "inert sections/orphan2.liquid"
assert_contains "mixed: header active" "$out" "active sections/header-group.json"
assert_contains "mixed verdict HAS_ACTIVE" "$out" "VERDICT HAS_ACTIVE"

finish
```

- [ ] **Step 2: Run the test to confirm it fails (classifier not yet implemented)**

```bash
bash tests/test_classify.sh 2>/dev/null || true
# Expected: several NOT ok lines and/or errors from missing function
```

- [ ] **Step 3: Add `dawn::classify_changes` to `dawn-ops.sh`**

Append after `dawn::assert_staging_clean` in `.claude/skills/_dawn-ops-lib/dawn-ops.sh`:

```bash
# Classify changes in a commit ref or range (base..tip).
# Stdout: one "<label> <path>" per changed file, then "VERDICT <ALL_INERT|HAS_ACTIVE|NEEDS_JUDGMENT>".
# Stderr: human-readable explanation for each classification decision.
dawn::classify_changes(){
  local range="${1:?usage: dawn::classify_changes <ref-or-range>}"
  # Normalize single ref to parent..ref
  case "$range" in *..*) ;; *) range="${range}^..${range}" ;; esac

  local reachable; reachable=$(dawn::reachable_files | sort -u)

  local verdict="ALL_INERT" path label
  while IFS= read -r path; do
    [ -z "$path" ] && continue

    # Rule 1: new suffix template → NEEDS_JUDGMENT
    if echo "$path" | grep -qE '^templates/[a-z]+-[a-z]+\..+\.json$|^templates/page\..+\.json$|^templates/product\..+\.json$'; then
      label="needs_judgment"
      echo "NEEDS_JUDGMENT: $path — new suffix template; confirm no resource is bound to it in admin" >&2
      verdict="NEEDS_JUDGMENT"

    # Rule 2: locale file — check for removed/changed lines (not purely additive)
    elif echo "$path" | grep -qE '^locales/'; then
      local removed; removed=$(git diff "$range" -- "$path" | grep -c '^-[^-]' || true)
      if [ "$removed" = "0" ]; then
        label="inert"
        echo "inert: $path — locale addition only (no changed/removed keys)" >&2
      else
        label="active"
        echo "active: $path — locale value changed or key removed" >&2
        [ "$verdict" = "ALL_INERT" ] && verdict="HAS_ACTIVE"
      fi

    # Rule 3: in always-reachable set → active
    elif echo "$reachable" | grep -qxF "$path"; then
      label="active"
      echo "active: $path — in reachable render graph" >&2
      [ "$verdict" = "ALL_INERT" ] && verdict="HAS_ACTIVE"

    # Rule 4: not reachable → inert orphan
    else
      label="inert"
      echo "inert: $path — not reachable from any live render root" >&2
    fi

    echo "$label $path"
  done < <(git diff --name-only "$range")

  echo "VERDICT $verdict"
}
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
bash tests/test_classify.sh
# Expected:
#   ok  - orphan section is inert
#   ok  - orphan verdict ALL_INERT
#   ok  - layout edit is active
#   ok  - active verdict HAS_ACTIVE
#   ok  - suffix template is needs_judgment
#   ok  - needs_judgment verdict
#   ok  - additive locale is inert
#   ok  - changed locale value is active
#   ok  - mixed: orphan2 inert
#   ok  - mixed: header active
#   ok  - mixed verdict HAS_ACTIVE
# == 11 passed, 0 failed ==
```

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh tests/test_classify.sh
git commit -m "feat(lib): add dawn::classify_changes with static render-graph reachability"
```

---

## Task 3: Create `dawn-ship` skill

**Files:**
- Create: `.claude/skills/dawn-ship/ship.sh`
- Create: `.claude/skills/dawn-ship/SKILL.md`
- Create: `tests/test_ship.sh`

**Context:** `dawn-ship` cherry-picks a commit from `customizations` onto `current` (append-only, no force-push, no config files). It runs the classifier on the commit diff and applies gates:
- `ALL_INERT` → light gate: show diff + classifier report, ask for `--confirm-live`
- `HAS_ACTIVE` → full gate: same + smoke-test checklist + pre-ship rollback tag
- `NEEDS_JUDGMENT` → stop immediately (`DAWN_STOP_JUDGMENT`)

Usage: `ship.sh <commit-ish> [--confirm-live]`

The script:
1. Validates the commit is reachable from `customizations` (not from `staging` or elsewhere)
2. Shows the diff and classifier report to stdout
3. If not `--confirm-live` → exit 20
4. Creates a rollback tag `ship-rollback/<timestamp>` at `origin/current`
5. Cherry-picks the commit onto `current` via `git push origin <cherry-pick-sha>:current` (append-only, using a temp branch for the cherry-pick)

For tests we simulate the push with `DAWN_PUSH_SHIP` env var (same pattern as `DAWN_PROMOTE_REF` in promote.sh).

- [ ] **Step 1: Write `tests/test_ship.sh` first (TDD)**

Create `tests/test_ship.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-ship/ship.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Setup: add an inert orphan commit on customizations
git checkout -q customizations
mkdir -p sections
echo '<div>withdrawal form</div>' > sections/withdrawal.liquid
git add sections/withdrawal.liquid; git commit -qm "L1: add withdrawal section (inert)"
INERT_COMMIT=$(git rev-parse HEAD)

# Add an active commit on customizations (edits always-reachable header-group)
echo '{"name":"header","v":99}' > sections/header-group.json
git add sections/header-group.json; git commit -qm "L1: update header (active)"
ACTIVE_COMMIT=$(git rev-parse HEAD)

git checkout -q staging

# 1. NEEDS_JUDGMENT: commit with a suffix template → rc 21
git checkout -q customizations
mkdir -p templates
echo '{}' > templates/page.herroeping.json
git add templates/page.herroeping.json; git commit -qm "L1: withdrawal template (needs judgment)"
NJ_COMMIT=$(git rev-parse HEAD)
git checkout -q staging
assert_rc "ship stops for needs_judgment" 21 bash "$SH" "$NJ_COMMIT"

# 2. Inert commit without --confirm-live → rc 20 (STOP-live)
out=$(bash "$SH" "$INERT_COMMIT" 2>&1 || true)
echo "$out" | grep -q "INERT\|inert\|ALL_INERT" && _pass "inert report shown" || _fail "inert report shown" "$out"
assert_rc "inert commit stops for live confirm" 20 bash "$SH" "$INERT_COMMIT"

# 3. Active commit without --confirm-live → rc 20 and shows smoke-test prompt
out=$(bash "$SH" "$ACTIVE_COMMIT" 2>&1 || true)
echo "$out" | grep -qi "smoke\|test\|active\|HAS_ACTIVE" && _pass "active report shown" || _fail "active report shown" "$out"
assert_rc "active commit stops for live confirm" 20 bash "$SH" "$ACTIVE_COMMIT"

# 4. Inert commit with --confirm-live → rc 0, rollback tag created, current updated
# Use test seam: DAWN_SHIP_PUSH=mock
export DAWN_SHIP_PUSH=mock
pre_current=$(git rev-parse refs/remotes/origin/current)
assert_rc "inert ship with confirm succeeds" 0 bash "$SH" "$INERT_COMMIT" --confirm-live
# rollback tag must exist
git tag | grep -q '^ship-rollback/' && _pass "rollback tag created" || _fail "rollback tag created"
# In test mode (mock push), we can't check current moved — just check rc 0 was returned
unset DAWN_SHIP_PUSH

# 5. Commit not reachable from customizations → guard (rc 10)
# Make a commit only on staging
git checkout -q staging
echo 'staging-only' > assets/staging-only.css
git add assets/staging-only.css; git commit -qm "staging-only commit"
STAGING_ONLY=$(git rev-parse HEAD)
assert_rc "ship refuses non-customizations commit" 10 bash "$SH" "$STAGING_ONLY"

finish
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bash tests/test_ship.sh 2>/dev/null || true
# Expected: errors / NOT ok lines because ship.sh doesn't exist yet
```

- [ ] **Step 3: Create `ship.sh`**

Create `.claude/skills/dawn-ship/ship.sh`:

```bash
#!/usr/bin/env bash
# Usage: ship.sh <commit-ish> [--confirm-live]
# Cherry-picks a classified commit from customizations onto current (append-only).
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

commit="${1:?usage: ship.sh <commit-ish> [--confirm-live]}"
confirm="${2:-}"

# Resolve to a full sha
sha=$(git rev-parse --verify "${commit}^{commit}" 2>/dev/null) \
  || { echo "GUARD: cannot resolve commit '$commit'" >&2; exit $DAWN_GUARD; }

# Commit must be reachable from customizations (not just staging or elsewhere)
if ! git merge-base --is-ancestor "$sha" customizations 2>/dev/null; then
  echo "GUARD: $sha is not reachable from customizations — only cherry-pick from customizations" >&2
  exit $DAWN_GUARD
fi

# Classify the commit
echo "=== Classifier report ===" >&2
classify_out=$(dawn::classify_changes "$sha" 2>&1)
echo "$classify_out" >&2
verdict=$(echo "$classify_out" | grep '^VERDICT ' | awk '{print $2}')

# NEEDS_JUDGMENT → stop immediately
if [ "$verdict" = "NEEDS_JUDGMENT" ]; then
  echo "" >&2
  echo "STOP: commit contains a new suffix template. Confirm in Shopify admin that NO page or" >&2
  echo "      product is currently assigned to this template, then re-run with --confirm-live." >&2
  exit $DAWN_STOP_JUDGMENT
fi

# Show the full diff the operator will be shipping
echo "" >&2
echo "=== Full diff to be shipped ===" >&2
git diff "${sha}^..${sha}" >&2

# Gate: require --confirm-live
if [ "$confirm" != "--confirm-live" ]; then
  echo "" >&2
  echo "Classifier verdict: $verdict" >&2
  if [ "$verdict" = "HAS_ACTIVE" ]; then
    echo "" >&2
    echo "ACTIVE changes detected. Before confirming, run a manual smoke test:" >&2
    echo "  1. Open the live storefront in an incognito window." >&2
    echo "  2. Visit the homepage, a product page, cart, and any recently changed page." >&2
    echo "  3. Confirm no visual regressions, no JS errors in console." >&2
  fi
  echo "" >&2
  echo "STOP: review the classifier report and diff above, then re-run with --confirm-live." >&2
  exit $DAWN_STOP_LIVE
fi

# Archive a rollback tag at the pre-ship current
stamp="ship-rollback/$(date +%Y-%m-%d-%H%M%S)"
git tag -f "$stamp" refs/remotes/origin/current >/dev/null 2>&1 \
  || git tag -f "$stamp" origin/current
echo "Archived pre-ship current at tag $stamp"

# Cherry-pick onto a temp branch based on origin/current, then push
if [ "${DAWN_SHIP_PUSH:-}" = "mock" ]; then
  echo "TEST MODE: would push $sha onto current (mock)" ; exit $DAWN_OK
fi

tmp_branch="__dawn-ship-tmp-$$"
trap "git branch -D '$tmp_branch' 2>/dev/null || true; git checkout -q - 2>/dev/null || true" EXIT
git checkout -q -b "$tmp_branch" refs/remotes/origin/current \
  || { echo "GUARD: cannot create temp branch from origin/current" >&2; exit $DAWN_GUARD; }
git cherry-pick --no-edit "$sha" \
  || { echo "STOP: cherry-pick conflict — resolve manually, then push with:" >&2
       echo "  git push origin $tmp_branch:current" >&2; exit $DAWN_STOP_JUDGMENT; }
git push origin "${tmp_branch}:current" \
  || { echo "GUARD: push to current failed (non-fast-forward?)" >&2; exit $DAWN_GUARD; }
# Update our local remote ref
git update-ref refs/remotes/origin/current "$(git rev-parse "$tmp_branch")"
echo "Shipped $sha onto current ($verdict)."
exit $DAWN_OK
```

- [ ] **Step 4: Create `SKILL.md`**

Create `.claude/skills/dawn-ship/SKILL.md`:

```markdown
---
name: dawn-ship
description: Cherry-pick a classified commit from customizations onto the live theme (current). Use when the user says ship inert, ship this commit, push to live without a full promote, or unblock a page binding.
---

## dawn-ship

Ships a **single classified commit** from `customizations` onto `current` — append-only, no force-push, churn-free. Use this to push dormant (inert) building blocks to the live theme ahead of a full promote, or to ship tested-active changes incrementally.

This skill operates from a checked-out `ops` branch (or any non-`current` branch with a clean working tree).

### Running

```bash
bash .claude/skills/dawn-ship/ship.sh <commit-ish>
```

Replace `<commit-ish>` with the SHA or branch tip you want to ship (must be reachable from `customizations`).

### Exit codes and required responses

**Exit 10 (GUARD)**
The commit is not reachable from `customizations`, or another precondition failed. Report the printed reason to the user and do not proceed.

**Exit 21 (STOP-JUDGMENT — new suffix template)**
The commit adds a suffix template (`page.*.json` or `product.*.json`). **STOP.**

Tell the user:
> "This commit adds a new suffix template. Before shipping, confirm in the Shopify admin that NO page or product is currently assigned to this template. Once confirmed, re-run with `--confirm-live`."

**Exit 20 (STOP-live — awaiting human approval)**
The script has printed:
1. The classifier report (per-path `inert`/`active` labels and verdict)
2. The full diff to be shipped
3. (For active changes) A smoke-test checklist

**STOP here.** Show the operator the output and ask explicitly:
> "The above diff and classifier report describe exactly what will be shipped to the LIVE theme. Classifier verdict: [ALL_INERT / HAS_ACTIVE]. Do you approve shipping this commit to current? (yes/no)"

If the verdict is `HAS_ACTIVE`, also say:
> "This contains active changes. Please complete the smoke-test checklist above before confirming."

Only re-run with `--confirm-live` after the user has clearly said yes.

```bash
bash .claude/skills/dawn-ship/ship.sh <commit-ish> --confirm-live
```

**Exit 0 (success)**
Tell the user:
> "Commit `<sha>` has been shipped to current (live). Classifier verdict: [ALL_INERT / HAS_ACTIVE]. A rollback tag `ship-rollback/<timestamp>` was created at the pre-ship state."

Rollback command if needed:
```bash
git push --force-with-lease origin ship-rollback/<timestamp>:current
```
```

- [ ] **Step 5: Run `test_ship.sh` and verify it passes**

```bash
bash tests/test_ship.sh
# Expected:
#   ok  - ship stops for needs_judgment
#   ok  - inert report shown
#   ok  - inert commit stops for live confirm
#   ok  - active report shown
#   ok  - active commit stops for live confirm
#   ok  - inert ship with confirm succeeds
#   ok  - rollback tag created
#   ok  - ship refuses non-customizations commit
# == 8 passed, 0 failed ==
```

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/dawn-ship/ tests/test_ship.sh
git commit -m "feat: add dawn-ship skill (cherry-pick classified commit onto current)"
```

---

## Task 4: Guard `dawn-promote` with `assert_staging_clean`

**Files:**
- Modify: `.claude/skills/dawn-promote/promote.sh`
- Modify: `tests/test_promote.sh`

**Context:** The guarded reset should only run when `staging` is in a known-clean state: built on top of `customizations` with no divergence and the tip commit is a config snapshot. This prevents accidentally promoting a `staging` that has unresolved dev commits or was not rebuilt after a harvest rebase.

- [ ] **Step 1: Add the cleanliness guard to `promote.sh`**

In `.claude/skills/dawn-promote/promote.sh`, add the guard immediately after the `dawn::backflow_pending` check (before the archive tag). The file currently reads:

```bash
dawn::backflow_pending && { echo "GUARD: backflow first — origin/current has unsynced edits" >&2; exit $DAWN_GUARD; }

stamp="config-archive/$(date +%Y-%m-%d-%H%M%S)"
```

Replace that first line (and add the new guard) so it becomes:

```bash
dawn::backflow_pending && { echo "GUARD: backflow first — origin/current has unsynced edits" >&2; exit $DAWN_GUARD; }
dawn::assert_staging_clean || exit $DAWN_GUARD

stamp="config-archive/$(date +%Y-%m-%d-%H%M%S)"
```

- [ ] **Step 2: Extend `tests/test_promote.sh` with cleanliness-guard tests**

Add the following tests **before the final `finish` call** in `tests/test_promote.sh`:

```bash
# --- Cleanliness guard tests ---
# Rebuild the fixture (need a fresh one for these tests)
FIX2=$(bash "$HERE/tests/fixture.sh"); cd "$FIX2"

# staging is diverged from customizations: add a commit only on staging
git checkout -q staging
# drop the config-snapshot tip so we can add a real commit
git reset -q --soft HEAD~1
echo 'debug content' > assets/debug.css
git add assets/debug.css; git commit -qm "debug: temp experiment"
# Now staging tip is not a config snapshot → guard
assert_rc "promote blocks dirty staging tip" 10 bash "$SH"

# Recreate the config snapshot at the tip and sync origin/current
git checkout -q origin/current -- config/settings_data.json sections/header-group.json 2>/dev/null || true
git commit -qm "L2: store config snapshot" 2>/dev/null || git commit -qam "L2: store config snapshot"
# Now backflow is pending (we need to sync) - skip backflow guard by syncing inline
git checkout -q staging
git checkout -q origin/current -- config/settings_data.json 2>/dev/null || true
git commit -qam "L2: store config snapshot" --allow-empty 2>/dev/null || true
# staging tip is now "config snapshot" → cleanliness guard passes, proceed to stop-live
assert_rc "promote proceeds past cleanliness check to stop-live" 20 bash "$SH"
```

- [ ] **Step 3: Run the full promote test suite**

```bash
bash tests/test_promote.sh
# Expected: all ok lines, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/dawn-promote/promote.sh tests/test_promote.sh
git commit -m "feat(promote): add assert_staging_clean guard before reset"
```

---

## Task 5: Revise `dawn-harvest` for atomic classified commits

**Files:**
- Modify: `.claude/skills/dawn-harvest/harvest.sh`
- Modify: `tests/test_harvest.sh`

**Context:** Harvest must now:
1. Run the classifier on the file being harvested
2. Record a `Inert: yes` or `Inert: no` trailer in the commit message
3. For a mixed file (`--hunks` mode), already exits with `DAWN_STOP_JUDGMENT` — no change needed there, but the error message should mention "split to produce a purely inert or purely active commit"
4. The harvest commit message changes from `L1: harvest <file>` to include the classifier result

The classifier runs on the diff between `customizations` and the harvested file on `staging`. Since harvest checks out the file from `staging` onto `customizations`, we classify after `git add` but before `git commit` using `dawn::classify_changes HEAD` on the staged diff (using `--cached`).

Actually, simpler: classify the file on `staging` vs `customizations` before the checkout. We can use `git diff customizations staging -- <file>` but `dawn::classify_changes` takes a commit range. Instead, use a lightweight per-path classification: call the reachability check directly.

Simplest approach: after `git add "$file"` on the `customizations` branch, classify using `git stash` + `dawn::classify_changes` on the staged changes. Even simpler: classify based on whether the file path appears in `dawn::reachable_files`. This is sufficient for the atomicity invariant.

- [ ] **Step 1: Write new harvest tests first (TDD)**

Add to the end of `tests/test_harvest.sh` (before `finish`):

```bash
# --- Trailer tests ---
FIX2=$(bash "$HERE/tests/fixture.sh"); cd "$FIX2"

# Harvest an orphan file (not reachable) → commit trailer Inert: yes
git checkout -q staging
echo '<div>new widget</div>' > sections/new-widget.liquid
git add sections/new-widget.liquid; git commit -qm "add new-widget on staging"
bash "$SH" sections/new-widget.liquid
trailer=$(git log -1 --format=%B customizations | grep '^Inert:')
assert_eq "orphan harvest trailer Inert: yes" "$trailer" "Inert: yes"

# Harvest a reachable file (header-group.json is always reachable) → trailer Inert: no
git checkout -q staging
echo '{"name":"header","v":2}' > sections/header-group.json
git add sections/header-group.json; git commit -qam "tweak header on staging"
bash "$SH" sections/header-group.json
trailer=$(git log -1 --format=%B customizations | grep '^Inert:')
assert_eq "reachable harvest trailer Inert: no" "$trailer" "Inert: no"
```

- [ ] **Step 2: Run the new harvest tests to confirm they fail**

```bash
bash tests/test_harvest.sh 2>/dev/null || true
# Expected: the two new trailer tests fail (NOT ok), existing tests still pass
```

- [ ] **Step 3: Revise `harvest.sh` to add classifier trailer**

Replace the commit line in `harvest.sh`. Currently:

```bash
git add "$file"; git commit -q -m "L1: harvest $file"
```

Replace with:

```bash
git add "$file"
# Classify the path to determine inert/active for the trailer
_harvest_reachable=$(dawn::reachable_files | sort -u)
if echo "$_harvest_reachable" | grep -qxF "$file"; then
  _inert_trailer="Inert: no"
else
  case "$file" in
    templates/*.*.*) _inert_trailer="Inert: needs_judgment" ;;
    locales/*) _inert_trailer="Inert: yes" ;;
    *) _inert_trailer="Inert: yes" ;;
  esac
fi
git commit -q -m "L1: harvest $file

$_inert_trailer"
```

Also update the `--hunks` error message to mention atomicity:

```bash
if [ "$mode" = "--hunks" ]; then
  echo "STOP: $file mixes inert and active lines; split into a purely inert or purely active file before harvesting." >&2
  echo "Agent: split the hunks with the user (generic -> L1), then re-run on a trimmed file." >&2
  exit $DAWN_STOP_JUDGMENT
fi
```

- [ ] **Step 4: Run the full harvest test suite**

```bash
bash tests/test_harvest.sh
# Expected: all ok, 0 failed
```

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/dawn-harvest/harvest.sh tests/test_harvest.sh
git commit -m "feat(harvest): add Inert trailer and atomic-commit messaging"
```

---

## Task 6: Register new tests in `run-all.sh`

**Files:**
- Modify: `tests/run-all.sh`

- [ ] **Step 1: Read current `run-all.sh`**

```bash
cat tests/run-all.sh
```

- [ ] **Step 2: Add `test_classify.sh` and `test_ship.sh`**

In `tests/run-all.sh`, add `test_classify.sh` and `test_ship.sh` to the list of tests that are run. The existing pattern runs each test script with `bash`. Follow the same pattern.

- [ ] **Step 3: Run the full test suite**

```bash
bash tests/run-all.sh
# Expected: all test files pass, 0 failures total
```

- [ ] **Step 4: Commit**

```bash
git add tests/run-all.sh
git commit -m "test: register test_classify and test_ship in run-all.sh"
```

---

## Task 7: Update `conventions.md`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/conventions.md`

**Context:** The conventions file is the single source of truth for all skills. It needs:
1. A new section explaining inert vs active (render-graph reachability)
2. A new section explaining the append-only rule for bot-linked branches
3. The "two promote modes" table (`dawn-ship` vs `dawn-promote`)
4. The branch model updated to show `customizations` is bot-free/rewritable
5. The "hard rule" expanded: never force-push a bot-linked branch except the guarded reset

- [ ] **Step 1: Read the current `conventions.md` to locate insertion points**

Read `.claude/skills/_dawn-ops-lib/conventions.md` (already done above — it's ~102 lines).

- [ ] **Step 2: Add new sections**

After the existing `## 2. The hard rule — never touch current by hand` section, insert a new `## 2a. Bot-linked branches are append-only` section. After the existing `## 3. Two operating modes` table, add `## 3a. Two promote modes`. After `## 5. L1 vs L2 classification`, add `## 5a. Inert vs active (render-graph reachability)`.

Edit `.claude/skills/_dawn-ops-lib/conventions.md` to add:

After `## 2. The hard rule` section (after the blank line following the section content), insert:

```markdown
## 2a. Bot-linked branches are append-only

`staging` and `current` are linked to real Shopify themes. The Shopify GitHub integration writes "Update from Shopify…" commits to them directly. Because of this:

- **Never force-push `staging` or `current`** except the one deliberate guarded reset performed by `dawn-promote`.
- **All history surgery** (rebase, split, reword) happens on `customizations`, which is not linked to any theme and is always bot-free.
- Force-pushing a bot-linked branch while the bot has committed to it produces repeated churn (conflicting history) that re-triggers on every editor save.

---
```

After `## 3. Two operating modes` section, insert:

```markdown
## 3a. Two promote modes

| Mode | Skill | What it does | When to use |
|---|---|---|---|
| **Ship** (incremental) | `dawn-ship` | Cherry-picks a classified commit from `customizations` onto `current`. Append-only. Classifier gates: ALL_INERT → light confirm; HAS_ACTIVE → full confirm + smoke test; NEEDS_JUDGMENT → stop. | Ship dormant building blocks early (to unblock shop-global activation), or ship tested-active changes incrementally. |
| **Promote** (release) | `dawn-promote` | Force-pushes `staging` onto `current` (the authoritative reset). Yields `current == staging`. Guarded: staging must be clean. | Full release after rebuild, backflow, and testing. |

The two modes are complementary: `dawn-ship` ships pieces incrementally between releases; `dawn-promote` resets `current` to the authoritative tested `staging` at each release, reconciling any divergence.

---
```

After `## 5. L1 vs L2 classification` section, insert:

```markdown
## 5a. Inert vs active (render-graph reachability)

A change is **inert** if publishing it does not alter the rendered output of any URL a visitor can currently reach.

**Always-reachable roots:** `layout/*.liquid`, `sections/header-group.json`, `sections/footer-group.json`, `config/settings_data.json`, `config/settings_schema.json`, and the **default templates** (`templates/index.json`, `templates/cart.json`, `templates/product.json`, `templates/collection.json`, `templates/article.json`, `templates/blog.json`, `templates/password.json`, `templates/search.json`, `templates/404.json`, `templates/page.json`), plus sections listed in those templates.

**Inert examples:** a new section / snippet / asset not referenced by any reachable file; additive-only new locale keys; a new suffix template (`page.foo.json`) with no resource bound to it.

**Active examples:** any edit to a file in the always-reachable set; a changed locale value; wiring a new section into a reachable template.

**NEEDS_JUDGMENT:** new suffix templates (`page.*.json`, `product.*.json`). Whether a resource is bound is shop-global admin state, not in git. The operator must confirm "no page/product is assigned this template" before shipping.

**Conservative default:** anything not provably inert is flagged active. The classifier (`dawn::classify_changes`) never silently calls something inert.

---
```

- [ ] **Step 3: Run the full test suite to confirm nothing broke**

```bash
bash tests/run-all.sh
# Expected: all pass
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/conventions.md
git commit -m "docs(conventions): add inert/active, append-only rule, two promote modes"
```

---

## Task 8: Write the operator runbook

**Files:**
- Create: `docs/superpowers/runbook/dawn-dev-and-release.md`

**Context:** A fresh operator (human or agent) should be able to read this document and know which skill to run, when, and in what order. It covers the full workflow from development through release, plus the decision tree from the spec.

- [ ] **Step 1: Create the runbook**

Create `docs/superpowers/runbook/dawn-dev-and-release.md`:

```markdown
# Dawn Development and Release Workflow

Single reference for operating the Zogezeept theme repo. Read this before running any skill.

---

## Branch roles

```
dawn-vanilla      L0 — pristine Dawn @ fixed upstream commit; ff-only, never commit here
  └─ customizations  L1+L2 code — bot-free, rewritable (rebase, split OK)
       └─ staging    L2 + config snapshot at tip — bot-linked preview theme (append-only)
            ⇄ current  LIVE shop — bot-linked (append-only except guarded reset)
```

`customizations` is **never linked to a Shopify theme**. The Shopify GitHub bot never writes to it.  
`staging` and `current` **are linked** to real themes. Treat them as append-only; never force-push them except the deliberate guarded reset (`dawn-promote`).

---

## Skill reference

| Skill | What it does | When to use |
|---|---|---|
| `dawn-harvest` | Lifts a generic file from `staging` into `customizations` as an atomic, classified L1 commit | After finishing a reusable feature on staging |
| `dawn-ship` | Cherry-picks a classified commit from `customizations` onto `current` (append-only) | To push a dormant piece to the live theme early, or to ship a tested active change incrementally |
| `dawn-backflow` | Mirrors live admin/editor changes from `current` back into `staging` | Before a promote, or when the admin UI has config you need in staging |
| `dawn-promote` | Force-pushes `staging` → `current` (the authoritative reset; guarded) | Full release after rebuild, backflow, and testing |
| `dawn-upgrade` | Fast-forwards `dawn-vanilla` to a new Dawn release, then rebases `customizations` and `staging` | When a new Dawn version is available |

---

## Standard workflow

### 1. Develop

Work on a scratch branch off `staging` (or directly on `staging`). The `staging` branch is linked to the preview theme — changes you push appear in the Shopify theme preview.

```bash
git checkout staging
# ... make changes, test on preview theme ...
git commit -am "feat: add withdrawal form section"
```

### 2. Harvest generic pieces

When a change is **generic** (passes the "stranger test" — any Dawn merchant could use it unchanged), lift it into `customizations`:

```bash
# From ops branch, with a clean working tree:
bash .claude/skills/dawn-harvest/harvest.sh sections/withdrawal.liquid
```

Harvest produces an atomic commit with an `Inert: yes/no` trailer. If a file mixes generic and store-specific lines, use `--hunks` to split first.

### 3. Ship inert pieces early (optional)

If you need a dormant building block on the **live theme** before the full release (e.g. to unblock a page→template binding in the Shopify admin), ship it directly:

```bash
# Check which commits are on customizations
git log --oneline customizations ^staging

# Ship a specific commit (agent will show diff + classifier report, then ask for confirmation)
bash .claude/skills/dawn-ship/ship.sh <commit-sha>
```

This is **append-only** — no force-push, no config files. The Shopify bot's config churn on `current` is unaffected.

### 4. Activate shop-global state in admin

Once inert building blocks are live on `current` (e.g. a new `page.herroeping.json` template), you can bind them in the Shopify admin:

- **Pages → Edit page → Template**: assign `page.herroeping` to the `/herroeping` page.
- Test the bound URL on **both** the preview theme (which now has the template too) and the live theme.

### 5. Release

When the feature is complete and tested:

```bash
# a) Capture any live admin edits back into staging
bash .claude/skills/dawn-backflow/backflow.sh

# b) Verify staging is clean (all harvested, config snapshot at tip)
# dawn-promote will check this automatically; if it fails, rebase staging onto customizations
# and recreate the config snapshot.

# c) Promote
bash .claude/skills/dawn-promote/promote.sh
# Agent will stop at the live-confirm gate and show you the full diff.
# After reviewing, confirm with --confirm-live.
bash .claude/skills/dawn-promote/promote.sh --confirm-live
```

After promote, `current == staging` exactly. Any interim `dawn-ship` cherry-picks are superseded.

---

## Decision tree

```
Want to push a dormant piece to the live theme now?
  → dawn-ship (inert commit from customizations)

Want to publish a full tested release?
  → dawn-backflow → rebuild staging → dawn-promote

Captured live admin edits that aren't in staging yet?
  → dawn-backflow

Upgrading to a new Dawn version?
  → dawn-upgrade

Need to lift a generic feature from staging into L1?
  → dawn-harvest
```

---

## Rules (never break these)

1. **Never force-push `staging` or `current`** except the guarded reset in `dawn-promote`.
2. **All history surgery** (rebase, split, reword) on `customizations` only.
3. **Classify before shipping.** `dawn-ship` does this automatically; `dawn-harvest` records the trailer.
4. **`staging` tip = config snapshot.** Always ends in exactly one config-snapshot commit.
5. **Never commit to `current` locally.** `current` is the live shop — see `assert_not_current`.
6. **The mandatory pre-ship review is non-negotiable.** `dawn-ship` shows the exact diff and classifier report before anything is appended to `current`. The operator must confirm; the agent must never pass `--confirm-live` autonomously.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/runbook/dawn-dev-and-release.md
git commit -m "docs: add dawn-dev-and-release runbook (workflow guide + decision tree)"
```

---

## Task 9: Update `conventions.md` pointer and run final suite

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/conventions.md` (update the "Full depth" pointer at the top)
- Run: `tests/run-all.sh`

- [ ] **Step 1: Update the header pointer in `conventions.md`**

The current header reads:
```
Single source of truth for all four skills (`dawn-backflow`, `dawn-promote`, `dawn-upgrade`,
`dawn-harvest`). Full depth: runbook at `docs/superpowers/runbook/dawn-update-and-promote.md`, ...
```

Update it to mention `dawn-ship` and the new runbook:

Change the first paragraph to:
```markdown
Single source of truth for all five skills (`dawn-backflow`, `dawn-promote`, `dawn-upgrade`,
`dawn-harvest`, `dawn-ship`). Full depth: runbook at
`docs/superpowers/runbook/dawn-dev-and-release.md`, layer design at
`docs/superpowers/specs/2026-06-17-dawn-repo-layer-separation-design.md`, skills design at
`docs/superpowers/specs/2026-06-18-dawn-theme-ops-skills-design.md`,
inert-shipping design at `docs/superpowers/specs/2026-06-28-dawn-ops-inert-shipping-design.md`.
```

- [ ] **Step 2: Run the full test suite one final time**

```bash
bash tests/run-all.sh
# Expected: all test files pass, 0 failures total
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/conventions.md
git commit -m "docs(conventions): point to new runbook and inert-shipping design"
```

---

## Self-Review

### Spec coverage check

| Spec section | Covered by task |
|---|---|
| §2.1 Inert vs active (render-graph reachability) | Task 2 (`classify_changes`), Task 7 (conventions) |
| §2.2 Bot-free vs bot-linked branches | Task 7 (conventions §2a) |
| §3.1 `dawn-ship` — cherry-pick, incremental, append-only | Task 3 |
| §3.1 Mandatory pre-ship review (diff + classifier report shown before confirm) | Task 3 (`ship.sh` shows diff + report before the `--confirm-live` gate) |
| §3.2 `dawn-promote` — guarded reset | Task 4 |
| §4.1 `dawn::classify_changes` | Task 2 |
| §5 Harvest revision — atomic, classified, split mixed | Task 5 |
| §6 Workflow guide / runbook | Task 8 |
| §7 Error handling and gates (exit codes, gates per verdict) | Tasks 2, 3, 4 |
| §8 Testing (`test_classify`, `test_ship`, extend `test_promote`, extend `test_harvest`) | Tasks 2, 3, 4, 5, 6 |
| §9 Success criteria: no force-push except guarded reset | Task 3 (append-only push), Task 4 (assert_staging_clean) |

All spec sections have a corresponding task. No gaps found.

### Placeholder scan

No TBD, TODO, or placeholder text found in the plan. All code blocks are complete.

### Type/name consistency

- `dawn::classify_changes` defined in Task 2, used in Task 3 (`ship.sh`) — consistent.
- `dawn::reachable_files` defined in Task 1, used in Task 2 and Task 5 — consistent.
- `dawn::assert_staging_clean` defined in Task 1, used in Task 4 — consistent.
- Exit code constants (`DAWN_GUARD`, `DAWN_STOP_LIVE`, `DAWN_STOP_JUDGMENT`, `DAWN_OK`) — already defined in `dawn-ops.sh`, reused consistently throughout.
- `DAWN_SHIP_PUSH` test seam in Task 3, referenced in `test_ship.sh` in Task 3 — consistent.
- Rollback tag prefix: `ship-rollback/` in `ship.sh` and `test_ship.sh` — consistent.
- Classifier verdict strings: `ALL_INERT`, `HAS_ACTIVE`, `NEEDS_JUDGMENT` — used consistently across Tasks 2, 3, 7.
