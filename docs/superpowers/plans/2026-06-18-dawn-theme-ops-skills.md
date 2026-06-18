# Dawn theme-ops skills — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build four gated Claude Code skills (`dawn-backflow`, `dawn-promote`, `dawn-upgrade`, `dawn-harvest`) backed by a shared, tested bash library, so an agent can run the theme's layered git operations reliably and safely on a live storefront.

**Architecture:** A sourced bash library (`dawn-ops.sh`) holds guarded, self-verifying helpers; each skill is a `SKILL.md` (when/orchestration/gates) plus a deterministic script that composes the library and stops at hard gates via distinct exit codes. Everything lives on the `ops` branch under `.claude/skills/`; you run a skill by checking out `ops` and launching the agent there. Scripts are tested against a synthetic fixture repo, never the real branches.

**Tech Stack:** bash, git. Dependency-free test harness (plain bash assertions). No bats/external deps.

---

## Conventions for every task
- All work happens on the **`ops`** branch (`git branch --show-current` must print `ops`; never `current`).
- Commit after each task. Scripts are `chmod +x`. Shebang `#!/usr/bin/env bash`; `set -uo pipefail` (NOT `-e` — we manage exit codes explicitly).
- Exit-code contract (defined once in the lib, used everywhere):
  `0` ok · `10` guard-failure · `20` STOP-awaiting-`--confirm-live` · `21` STOP-needs-judgment · `30` verification-failure.

## File structure
```
.claude/skills/
  _dawn-ops-lib/
    dawn-ops.sh          # sourced library of guarded helpers
    config-paths.txt     # canonical config-snapshot path set (one path/glob per line)
    conventions.md       # invariants + branch model (human/agent reference)
  dawn-promote/SKILL.md  + promote.sh
  dawn-backflow/SKILL.md + backflow.sh
  dawn-harvest/SKILL.md  + harvest.sh
  dawn-upgrade/SKILL.md  + upgrade.sh
tests/
  harness.sh             # assert helpers + tiny runner
  fixture.sh             # builds a scratch repo with synthetic vanilla/customizations/staging/current
  test_lib.sh            # tests for dawn-ops.sh
  test_promote.sh  test_backflow.sh  test_harvest.sh  test_upgrade.sh
```

---

## Task 0: Test harness + fixture repo

**Files:** Create `tests/harness.sh`, `tests/fixture.sh`.

- [ ] **Step 1: Write the harness**

Create `tests/harness.sh`:
```bash
#!/usr/bin/env bash
# Tiny dependency-free test harness. Source it; use assert_* ; call finish at end.
set -uo pipefail
_T_PASS=0 _T_FAIL=0
_pass(){ _T_PASS=$((_T_PASS+1)); echo "  ok  - $1"; }
_fail(){ _T_FAIL=$((_T_FAIL+1)); echo "  NOT ok - $1"; [ -n "${2:-}" ] && echo "        $2"; }
assert_eq(){ [ "$2" = "$3" ] && _pass "$1" || _fail "$1" "expected [$3] got [$2]"; }
assert_rc(){ # assert_rc "name" expected_rc cmd...
  local name="$1" exp="$2"; shift 2; "$@"; local rc=$?
  [ "$rc" = "$exp" ] && _pass "$name" || _fail "$name" "expected rc=$exp got rc=$rc"; }
assert_contains(){ case "$2" in *"$3"*) _pass "$1";; *) _fail "$1" "[$2] lacks [$3]";; esac; }
finish(){ echo "== $_T_PASS passed, $_T_FAIL failed =="; [ "$_T_FAIL" = 0 ]; }
```

- [ ] **Step 2: Write the fixture builder**

Create `tests/fixture.sh`. It builds a throwaway git repo mirroring the layer model so tests never
touch real branches. `dawn-vanilla` → `customizations` (one L1 commit) → `staging` (one enrichment +
one config-snapshot tip). `current` = a tree equal to staging plus extra "admin" config churn, with
an `upstream/main` ref so `merge-base` works.
```bash
#!/usr/bin/env bash
# Usage: FIX=$(tests/fixture.sh); cd "$FIX"   — prints the path to a fresh fixture repo.
set -euo pipefail
FIX="$(mktemp -d)"; cd "$FIX"; git init -q; git config user.email t@t; git config user.name t
mkdir -p config sections templates assets locales
seed(){ echo "$2" > "$1"; }
# --- vanilla base (acts as both dawn-vanilla and the upstream/main tip) ---
seed config/settings_data.json '{"current":{"blocks":{}}}'
seed sections/header-group.json '{"name":"header"}'
seed templates/index.json '{"sections":{}}'
seed assets/base.css '/* vanilla */'
seed sections/main-product.liquid 'VANILLA'
git add -A; git commit -qm "vanilla"; git branch dawn-vanilla
git update-ref refs/remotes/upstream/main HEAD
# --- customizations: one L1 commit ---
git checkout -q -b customizations
seed sections/main-product.liquid 'VANILLA + L1-INVENTORY'
git add -A; git commit -qm "L1: inventory status"
# --- staging: enrichment commit, then config-snapshot tip ---
git checkout -q -b staging
seed templates/product.workshop.json '{"enrichment":true}'
git add -A; git commit -qm "L2 enrichment: product.workshop template"
seed config/settings_data.json '{"staging":{"blocks":{"a":1}}}'
seed sections/header-group.json '{"name":"header","store":true}'
git add -A; git commit -qm "L2: store config snapshot"
# --- current: start equal to staging, then add an "admin" config edit (bot churn) ---
git checkout -q -b current staging
seed config/settings_data.json '{"staging":{"blocks":{"a":1,"b":2}}}'
git add -A; git commit -qm "Update from Shopify for theme dawn/current"
# simulate the remote
git update-ref refs/remotes/origin/current current
git checkout -q staging
echo "$FIX"
```

- [ ] **Step 3: Smoke-test the fixture**

Run:
```bash
chmod +x tests/harness.sh tests/fixture.sh
FIX=$(bash tests/fixture.sh); echo "fixture: $FIX"; git -C "$FIX" log --oneline --all | head
```
Expected: a temp path, and a log showing `vanilla`, `L1: inventory status`, the enrichment, the config snapshot, and the "Update from Shopify" commit on `current`.

- [ ] **Step 4: Commit**
```bash
git add tests/harness.sh tests/fixture.sh
git commit -m "test: dependency-free harness + layer-model fixture repo"
```

---

## Task 1: `dawn-ops.sh` shared library

**Files:** Create `.claude/skills/_dawn-ops-lib/dawn-ops.sh`, `.claude/skills/_dawn-ops-lib/config-paths.txt`, `tests/test_lib.sh`.

- [ ] **Step 1: Write the config path-set file**

Create `.claude/skills/_dawn-ops-lib/config-paths.txt` (the canonical config-snapshot set; globs
allowed; resolved against tracked files at runtime):
```
config/settings_data.json
config/settings_schema.json
sections/header-group.json
sections/footer-group.json
templates/index.json
templates/cart.json
templates/collection.json
templates/article.json
templates/blog.json
templates/password.json
templates/product.json
```
> Note: custom `product.*.json` templates are L2 **enrichments**, NOT config — deliberately excluded.

- [ ] **Step 2: Write the failing lib tests**

Create `tests/test_lib.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"
source "$HERE/tests/harness.sh"
LIB="$HERE/.claude/skills/_dawn-ops-lib/dawn-ops.sh"
FIX=$(bash "$HERE/tests/fixture.sh")
cd "$FIX"; source "$LIB"

# current_branch
git checkout -q staging
assert_eq "current_branch=staging" "$(dawn::current_branch)" "staging"

# assert_not_current: ok on staging, guard on current
( git checkout -q staging; dawn::assert_not_current ); assert_eq "not_current ok on staging" "$?" "0"
( git checkout -q current; dawn::assert_not_current ); assert_eq "not_current guards on current" "$?" "10"
git checkout -q staging

# assert_clean_tree: ok clean, guard when dirty
dawn::assert_clean_tree; assert_eq "clean ok" "$?" "0"
echo dirty >> config/settings_data.json
dawn::assert_clean_tree; assert_eq "dirty guards" "$?" "10"
git checkout -q -- config/settings_data.json

# merge_base_vanilla = the upstream/main tip (the vanilla commit)
assert_eq "merge_base_vanilla" "$(dawn::merge_base_vanilla)" "$(git rev-parse refs/remotes/upstream/main)"

# config_files resolves only existing tracked config paths
out="$(dawn::config_files)"
assert_contains "config has settings_data" "$out" "config/settings_data.json"
assert_contains "config has header-group" "$out" "sections/header-group.json"
case "$out" in *product.workshop.json*) _fail "config excludes enrichment templates" "found workshop";; *) _pass "config excludes enrichment templates";; esac

# backflow_pending: true (rc 0) because origin/current has the admin commit not in staging
dawn::backflow_pending; assert_eq "backflow pending true" "$?" "0"
# after folding current into staging it should be false (rc 1)
git checkout -q staging; git checkout -q origin/current -- config/settings_data.json; git commit -qm tmp
dawn::backflow_pending; assert_eq "backflow pending false after sync" "$?" "1"

# verify_tree_equal: equal vs different
git checkout -q staging
dawn::verify_tree_equal HEAD HEAD; assert_eq "tree equal" "$?" "0"
dawn::verify_tree_equal HEAD dawn-vanilla; assert_eq "tree differ" "$?" "30"

finish
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `chmod +x tests/test_lib.sh && bash tests/test_lib.sh`
Expected: FAIL — `dawn-ops.sh` does not exist yet (source error / functions undefined).

- [ ] **Step 4: Implement the library**

Create `.claude/skills/_dawn-ops-lib/dawn-ops.sh`:
```bash
#!/usr/bin/env bash
# Dawn theme-ops shared library. Source from a checkout of the dawn repo.
# Exit-code contract: 0 ok · 10 guard · 20 stop-live · 21 stop-judgment · 30 verify
set -uo pipefail
DAWN_OK=0 DAWN_GUARD=10 DAWN_STOP_LIVE=20 DAWN_STOP_JUDGMENT=21 DAWN_VERIFY=30
# Directory of this lib (for sibling files like config-paths.txt), resolved even when sourced.
DAWN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

dawn::current_branch(){ git rev-parse --abbrev-ref HEAD; }

dawn::assert_not_current(){
  if [ "$(dawn::current_branch)" = "current" ]; then
    echo "GUARD: refusing to operate on 'current' (the live shop)" >&2; return $DAWN_GUARD; fi; }

dawn::assert_clean_tree(){
  if [ -n "$(git status --porcelain)" ]; then
    echo "GUARD: working tree not clean — commit or stash first" >&2; return $DAWN_GUARD; fi; }

# Checkout target and restore the original branch when the *script* exits (success or failure).
dawn::with_branch(){
  local target="$1" orig; orig="$(dawn::current_branch)"
  git checkout -q "$target" 2>/dev/null || { echo "GUARD: cannot checkout $target" >&2; return $DAWN_GUARD; }
  trap "git checkout -q '$orig' 2>/dev/null || true" EXIT; }

dawn::merge_base_vanilla(){ git merge-base refs/remotes/upstream/main refs/remotes/origin/current 2>/dev/null \
  || git merge-base upstream/main origin/current; }

# Emit config-snapshot paths from config-paths.txt that actually exist as tracked files.
dawn::config_files(){
  local p; while IFS= read -r p; do [ -z "$p" ] && continue
    git ls-files -- "$p"; done < "$DAWN_LIB_DIR/config-paths.txt" | sort -u; }

# rc 0 if origin/current has commits not in staging (backflow needed), else rc 1.
dawn::backflow_pending(){
  local n; n="$(git rev-list --count staging..refs/remotes/origin/current 2>/dev/null \
    || git rev-list --count staging..origin/current)"
  [ "${n:-0}" -gt 0 ]; }

# rc 0 if trees equal (excl docs/ + .claude/), rc 30 with a summary if not.
dawn::verify_tree_equal(){
  local a="$1" b="$2"
  if git diff --quiet "$a" "$b" -- . ':(exclude)docs/' ':(exclude).claude/'; then return $DAWN_OK; fi
  echo "VERIFY FAIL: $a vs $b differ:" >&2
  git diff --stat "$a" "$b" -- . ':(exclude)docs/' ':(exclude).claude/' >&2; return $DAWN_VERIFY; }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/test_lib.sh`
Expected: `== N passed, 0 failed ==` (exit 0).

- [ ] **Step 6: Commit**
```bash
chmod +x .claude/skills/_dawn-ops-lib/dawn-ops.sh
git add .claude/skills/_dawn-ops-lib/ tests/test_lib.sh
git commit -m "feat: dawn-ops.sh guarded helper library + config path-set + tests"
```

---

## Task 2: `conventions.md` shared reference

**Files:** Create `.claude/skills/_dawn-ops-lib/conventions.md`.

- [ ] **Step 1: Write it** (the single source of truth every SKILL.md links to)

Create `.claude/skills/_dawn-ops-lib/conventions.md` with: the branch model
(`dawn-vanilla`→`customizations`→`staging`→`current`); the hard rule (never write `current` except
via gated promote); the config-snapshot invariant (one regenerable commit at the tip); the L1-vs-L2
strict test; the exit-code contract; "develop on `staging`, operate from `ops`, never check out
`current`." Keep it to one screen; link to the spec + runbook for depth.

- [ ] **Step 2: Commit**
```bash
git add .claude/skills/_dawn-ops-lib/conventions.md
git commit -m "docs: dawn-ops conventions reference"
```

---

## Task 3: `dawn-promote` skill (pure refs; the live gate)

**Files:** Create `.claude/skills/dawn-promote/SKILL.md`, `.claude/skills/dawn-promote/promote.sh`, `tests/test_promote.sh`.

- [ ] **Step 1: Write failing tests**

Create `tests/test_promote.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-promote/promote.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# With backflow pending (origin/current ahead of staging) → guard, rc 10, no push.
assert_rc "promote blocks when backflow pending" 10 bash "$SH"

# Sync staging to current (backflow), then promote without --confirm-live → STOP-live rc 20.
git checkout -q staging; git checkout -q origin/current -- config/settings_data.json; git commit -qm "sync"
assert_rc "promote stops for live confirm" 20 bash "$SH"
# origin/current must be UNCHANGED (no push happened)
assert_eq "current untouched pre-confirm" "$(git rev-parse refs/remotes/origin/current)" "$(git rev-parse current)"

# A config-archive tag was created at the pre-promote current.
git tag | grep -q '^config-archive/' && _pass "archive tag created" || _fail "archive tag created"

# With --confirm-live → rc 0 and origin/current now equals staging.
assert_rc "promote live succeeds with confirm" 0 bash "$SH" --confirm-live
assert_eq "current == staging after promote" "$(git rev-parse refs/remotes/origin/current)" "$(git rev-parse staging)"
finish
```
> Fixture note: `promote.sh` must accept an env override for the push target so tests can point at the
> local `refs/remotes/origin/current` instead of a real remote (see DAWN_PROMOTE_REF below).

- [ ] **Step 2: Run to verify fail**

Run: `chmod +x tests/test_promote.sh && bash tests/test_promote.sh`
Expected: FAIL (promote.sh missing).

- [ ] **Step 3: Implement `promote.sh`**

Create `.claude/skills/dawn-promote/promote.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
# Test seam: in tests, set DAWN_PROMOTE_REF=refs/remotes/origin/current and DAWN_PUSH="git update-ref"
PUSH="${DAWN_PUSH:-git push --force-with-lease}"
REMOTE="${DAWN_REMOTE:-origin}"

dawn::backflow_pending && { echo "GUARD: backflow first — origin/current has unsynced edits" >&2; exit $DAWN_GUARD; }

stamp="config-archive/$(date +%Y-%m-%d-%H%M%S)"
git tag -f "$stamp" refs/remotes/origin/current >/dev/null 2>&1 || git tag -f "$stamp" origin/current
echo "Archived pre-promote current at tag $stamp"

if [ "${1:-}" != "--confirm-live" ]; then
  echo "STOP: ready to promote staging -> $REMOTE/current (LIVE)." >&2
  echo "      Re-run with --confirm-live after human approval." >&2
  git --no-pager diff --stat staging refs/remotes/origin/current -- . ':(exclude)docs/' ':(exclude).claude/' >&2 || true
  exit $DAWN_STOP_LIVE
fi

if [ -n "${DAWN_PROMOTE_REF:-}" ]; then         # test path: move local ref
  git update-ref "$DAWN_PROMOTE_REF" staging; git update-ref refs/remotes/origin/current staging
else                                            # real path: force-push staging onto current
  git push "$REMOTE" staging
  $PUSH "$REMOTE" staging:current
fi
echo "Promoted staging -> current."
exit $DAWN_OK
```
> The test harness exports `DAWN_PROMOTE_REF` so the live branch updates a local ref; in production
> the `else` path force-pushes. Update `tests/test_promote.sh` Step 1 to `DAWN_PROMOTE_REF=refs/remotes/origin/current bash "$SH" ...` for the confirm case.

- [ ] **Step 4: Run to verify pass**

Run: `DAWN_PROMOTE_REF=refs/remotes/origin/current bash tests/test_promote.sh`
Expected: `== N passed, 0 failed ==`.

- [ ] **Step 5: Write SKILL.md**

Create `.claude/skills/dawn-promote/SKILL.md` with frontmatter:
```markdown
---
name: dawn-promote
description: Publish the staging branch to the live Shopify theme (current). Use when the user says promote, go live, publish staging, or deploy the theme. Requires explicit live confirmation.
---
```
Body: link to `_dawn-ops-lib/conventions.md`; the procedure (ensure on `ops`; run `promote.sh`; on
exit 10 tell user to run `dawn-backflow` first; on exit 20 **STOP and ask the user to approve the
live push**, showing the printed diff; only after explicit "yes" re-run with `--confirm-live`; on
exit 0 tell them to verify the live theme). State plainly: the agent must never pass `--confirm-live`
without an explicit human go-ahead in the conversation.

- [ ] **Step 6: Commit**
```bash
chmod +x .claude/skills/dawn-promote/promote.sh
git add .claude/skills/dawn-promote/ tests/test_promote.sh
git commit -m "feat: dawn-promote skill (gated live publish) + tests"
```

---

## Task 4: `dawn-backflow` skill

**Files:** Create `.claude/skills/dawn-backflow/SKILL.md`, `.claude/skills/dawn-backflow/backflow.sh`, `tests/test_backflow.sh`.

- [ ] **Step 1: Write failing tests**

Create `tests/test_backflow.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-backflow/backflow.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Config-only churn on current → Case A: staging config-tip amended, commit COUNT unchanged.
before=$(git rev-list --count customizations..staging)
assert_rc "backflow config-only ok" 0 bash "$SH"
after=$(git rev-list --count customizations..staging)
assert_eq "no new commit (amended tip)" "$after" "$before"
# staging config now matches current's config
assert_eq "config synced" "$(git show staging:config/settings_data.json)" "$(git show origin/current:config/settings_data.json)"
# guard: refuse on dirty tree
echo x >> config/settings_data.json
assert_rc "backflow guards dirty tree" 10 bash "$SH"
git checkout -q -- config/settings_data.json
finish
```

- [ ] **Step 2: Run to verify fail**

Run: `chmod +x tests/test_backflow.sh && bash tests/test_backflow.sh`
Expected: FAIL (backflow.sh missing).

- [ ] **Step 3: Implement `backflow.sh`**

Create `.claude/skills/dawn-backflow/backflow.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD
git fetch origin current --quiet 2>/dev/null || true

# Files changed on current since staging.
mapfile -t changed < <(git diff --name-only staging refs/remotes/origin/current 2>/dev/null \
  || git diff --name-only staging origin/current)
[ "${#changed[@]}" -eq 0 ] && { echo "Nothing to backflow."; exit $DAWN_OK; }

# Partition: config vs non-config. Non-config requires human judgment (enrichment vs generic).
mapfile -t cfg < <(dawn::config_files)
noncfg=()
for f in "${changed[@]}"; do
  case " ${cfg[*]} " in *" $f "*) : ;; *) noncfg+=("$f");; esac
done

if [ "${#noncfg[@]}" -gt 0 ]; then
  echo "STOP: non-config changes need classification (enrichment vs generic-L1 vs ignore):" >&2
  printf '  %s\n' "${noncfg[@]}" >&2
  echo "Decide per file: enrichment -> own L2 commit; generic -> dawn-harvest; churn -> ignore." >&2
  exit $DAWN_STOP_JUDGMENT
fi

# Case A: pure config churn. Refresh config files and amend the tip config-snapshot commit.
dawn::with_branch staging || exit $DAWN_GUARD
last_msg="$(git log -1 --format=%s)"
case "$last_msg" in
  *"config snapshot"*) ;;  # tip is the config snapshot — safe to amend
  *) echo "GUARD: staging tip is not the config snapshot ('$last_msg'); fix ordering first" >&2; exit $DAWN_GUARD;;
esac
while IFS= read -r f; do git checkout refs/remotes/origin/current -- "$f" 2>/dev/null \
  || git checkout origin/current -- "$f"; done < <(printf '%s\n' "${cfg[@]}")
git commit -q --amend --no-edit
echo "Backflow complete (config snapshot amended)."
exit $DAWN_OK
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/test_backflow.sh`
Expected: `== N passed, 0 failed ==`.

- [ ] **Step 5: Write SKILL.md**

Create `.claude/skills/dawn-backflow/SKILL.md` frontmatter:
```markdown
---
name: dawn-backflow
description: Pull live Shopify admin/config edits from the current branch back into staging. Use when the user says backflow, capture admin changes, sync config from live, or before a promote.
---
```
Body: link conventions; run `backflow.sh`; on exit 21 **STOP** and walk the user through classifying
each listed non-config file (enrichment → its own L2 commit per conventions; generic → `dawn-harvest`;
churn → ignore), then re-run; on exit 10 report the guard; on exit 0 confirm one config-snapshot commit.

- [ ] **Step 6: Commit**
```bash
chmod +x .claude/skills/dawn-backflow/backflow.sh
git add .claude/skills/dawn-backflow/ tests/test_backflow.sh
git commit -m "feat: dawn-backflow skill (config amend + classification gate) + tests"
```

---

## Task 5: `dawn-harvest` skill

**Files:** Create `.claude/skills/dawn-harvest/SKILL.md`, `.claude/skills/dawn-harvest/harvest.sh`, `tests/test_harvest.sh`.

- [ ] **Step 1: Write failing tests**

Create `tests/test_harvest.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-harvest/harvest.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Whole-file harvest of a generic file from staging into customizations.
git checkout -q staging; echo 'GENERIC TWEAK' > assets/base.css; git commit -qam "tweak base.css on staging"
assert_rc "harvest whole-file ok" 0 bash "$SH" assets/base.css
# customizations now carries the change…
assert_eq "in customizations" "$(git show customizations:assets/base.css)" "GENERIC TWEAK"
# …and staging was rebased onto it (config snapshot still the tip)
git checkout -q staging
assert_contains "config tip preserved" "$(git log -1 --format=%s)" "config snapshot"
# guard: refuse a config file (not harvestable to L1)
assert_rc "harvest refuses config file" 10 bash "$SH" config/settings_data.json
finish
```

- [ ] **Step 2: Run to verify fail**

Run: `chmod +x tests/test_harvest.sh && bash tests/test_harvest.sh`
Expected: FAIL (harvest.sh missing).

- [ ] **Step 3: Implement `harvest.sh`**

Create `.claude/skills/dawn-harvest/harvest.sh`:
```bash
#!/usr/bin/env bash
# Usage: harvest.sh <path> [--hunks]   Lift a generic change from staging into customizations (L1).
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
file="${1:?usage: harvest.sh <path> [--hunks]}"; mode="${2:-}"

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD
# refuse config-snapshot files — those are L2, not L1
while IFS= read -r c; do [ "$c" = "$file" ] && { echo "GUARD: $file is config (L2), not harvestable to L1" >&2; exit $DAWN_GUARD; }; done < <(dawn::config_files)

if [ "$mode" = "--hunks" ]; then
  echo "STOP: $file mixes generic + store-specific lines; needs per-hunk selection." >&2
  echo "Agent: split the hunks with the user (generic -> L1), then re-run on a trimmed file." >&2
  exit $DAWN_STOP_JUDGMENT
fi

dawn::with_branch customizations || exit $DAWN_GUARD
git checkout staging -- "$file"
git add "$file"; git commit -q -m "L1: harvest $file"
git checkout -q staging
git rebase -q customizations || { echo "STOP: rebase conflict bringing harvest into staging" >&2; exit $DAWN_STOP_JUDGMENT; }
echo "Harvested $file into customizations; staging rebased."
exit $DAWN_OK
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/test_harvest.sh`
Expected: `== N passed, 0 failed ==`.

- [ ] **Step 5: Write SKILL.md**

Create `.claude/skills/dawn-harvest/SKILL.md` frontmatter:
```markdown
---
name: dawn-harvest
description: Lift a generic, reusable change from staging up into the customizations (L1) layer. Use when the user says harvest, this should be generic, move to customizations, or make this upstreamable.
---
```
Body: link conventions; explain whole-file vs `--hunks` (mixed files); on exit 21 **STOP** and do the
per-hunk generic/store split with the user; on exit 10 report the guard (config files aren't L1);
on exit 0 confirm the L1 commit + that the config snapshot is still staging's tip.

- [ ] **Step 6: Commit**
```bash
chmod +x .claude/skills/dawn-harvest/harvest.sh
git add .claude/skills/dawn-harvest/ tests/test_harvest.sh
git commit -m "feat: dawn-harvest skill (lift generic change to L1) + tests"
```

---

## Task 6: `dawn-upgrade` skill

**Files:** Create `.claude/skills/dawn-upgrade/SKILL.md`, `.claude/skills/dawn-upgrade/upgrade.sh`, `tests/test_upgrade.sh`.

- [ ] **Step 1: Write failing tests**

Create `tests/test_upgrade.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-upgrade/upgrade.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Create a new "upstream release" tag advancing vanilla with a non-conflicting file.
git checkout -q dawn-vanilla; echo '/* v2 */' > assets/component-new.css; git commit -qam "vanilla v2"; git tag vNEXT
git checkout -q staging
assert_rc "upgrade ff+rebase ok" 0 bash "$SH" vNEXT
# dawn-vanilla advanced to the tag
assert_eq "vanilla ffd" "$(git rev-parse dawn-vanilla)" "$(git rev-parse vNEXT)"
# customizations + staging now contain the new upstream file
assert_eq "staging has upstream file" "$(git show staging:assets/component-new.css)" "/* v2 */"
# and still has L1 + config tip
assert_contains "L1 survived" "$(git log customizations --oneline)" "L1: inventory status"
assert_contains "config tip survived" "$(git log -1 --format=%s staging)" "config snapshot"

# Conflict case: make customizations and a new tag edit the same line → STOP rc 21.
git checkout -q dawn-vanilla; echo 'CONFLICT-A' > sections/main-product.liquid; git commit -qam "vanilla v3"; git tag vCONF
assert_rc "upgrade halts on conflict" 21 bash "$SH" vCONF
git rebase --abort 2>/dev/null || true
finish
```

- [ ] **Step 2: Run to verify fail**

Run: `chmod +x tests/test_upgrade.sh && bash tests/test_upgrade.sh`
Expected: FAIL (upgrade.sh missing).

- [ ] **Step 3: Implement `upgrade.sh`**

Create `.claude/skills/dawn-upgrade/upgrade.sh`:
```bash
#!/usr/bin/env bash
# Usage: upgrade.sh <upstream-tag>   ff dawn-vanilla -> rebase customizations -> rebase staging.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
tag="${1:?usage: upgrade.sh <upstream-tag>}"

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD

git checkout -q dawn-vanilla || exit $DAWN_GUARD
if ! git merge-base --is-ancestor dawn-vanilla "$tag" 2>/dev/null; then
  echo "GUARD: $tag is not ahead of dawn-vanilla (ff not possible)" >&2; exit $DAWN_GUARD; fi
git merge --ff-only "$tag" -q || { echo "GUARD: ff to $tag failed" >&2; exit $DAWN_GUARD; }

for br in customizations staging; do
  git checkout -q "$br"
  if ! git rebase -q "$( [ "$br" = customizations ] && echo dawn-vanilla || echo customizations )"; then
    echo "STOP: rebase conflict on '$br' upgrading to $tag. Resolve with the user, then continue." >&2
    exit $DAWN_STOP_JUDGMENT
  fi
done
echo "Upgraded to $tag: dawn-vanilla ffd, customizations + staging rebased. Test on preview, then promote."
exit $DAWN_OK
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/test_upgrade.sh`
Expected: `== N passed, 0 failed ==`.

- [ ] **Step 5: Write SKILL.md**

Create `.claude/skills/dawn-upgrade/SKILL.md` frontmatter:
```markdown
---
name: dawn-upgrade
description: Upgrade to a new Dawn version — fast-forward dawn-vanilla then rebase customizations and staging. Use when the user says upgrade Dawn, bump Dawn version, or move to a new Dawn release.
---
```
Body: link conventions; run `upgrade.sh <tag>` (e.g. `v15.4.1`); on exit 21 **STOP** at the conflict,
show conflicting files, resolve with the user, then `git rebase --continue` and re-run remaining
steps; on exit 10 report the guard; on exit 0 instruct: test on the preview theme, then `dawn-promote`.
Note: after upgrade, the new Dawn's locales supersede ours — re-apply L1-feature locale keys per
`docs/superpowers/inventory/manifest-L1-locale.md`.

- [ ] **Step 6: Commit**
```bash
chmod +x .claude/skills/dawn-upgrade/upgrade.sh
git add .claude/skills/dawn-upgrade/ tests/test_upgrade.sh
git commit -m "feat: dawn-upgrade skill (ff vanilla + rebase layers, conflict gate) + tests"
```

---

## Task 7: Full suite runner + discoverability check

**Files:** Create `tests/run-all.sh`.

- [ ] **Step 1: Write the runner**

Create `tests/run-all.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; fail=0
for t in test_lib test_backflow test_harvest test_upgrade; do
  echo "### $t"; bash "$HERE/tests/$t.sh" || fail=1
done
echo "### test_promote"; DAWN_PROMOTE_REF=refs/remotes/origin/current bash "$HERE/tests/test_promote.sh" || fail=1
exit $fail
```

- [ ] **Step 2: Run the whole suite**

Run: `chmod +x tests/run-all.sh && bash tests/run-all.sh`
Expected: every block ends `== N passed, 0 failed ==`; overall exit 0.

- [ ] **Step 3: Verify skill discoverability + safety invariant**

Run:
```bash
ls .claude/skills/*/SKILL.md           # 4 SKILL.md files
grep -L 'name:' .claude/skills/*/SKILL.md   # expect empty (all have frontmatter name)
grep -rn 'push .*:current\|update-ref .*current' .claude/skills | grep -v dawn-promote && echo "LEAK" || echo "OK: only dawn-promote writes current"
```
Expected: 4 skills; no missing frontmatter; `OK: only dawn-promote writes current`.

- [ ] **Step 4: Commit**
```bash
git add tests/run-all.sh
git commit -m "test: full suite runner + safety-invariant check"
```

---

## Self-review notes
- **Spec coverage:** 4 skills (Tasks 3–6), `_dawn-ops-lib` helpers + config set (Task 1), conventions (Task 2), structural safety / exit codes (lib + every script + Task 7 leak check), no-worktree checkout-in-place + restore trap (`dawn::with_branch`, Task 1), launch-from-`ops` discoverability (frontmatter + Task 7), fixture testing never touching real branches (Task 0 + per-skill tests). All spec sections map to tasks.
- **Discoverability:** no symlink/`setup.sh`/worktree tasks — by design (spec). The only "install" is `git checkout ops` before launching.
- **Test seam:** `promote.sh` uses `DAWN_PROMOTE_REF`/`DAWN_PUSH` env so tests exercise the live path against a local ref; production path force-pushes.
- **Deferred:** the squash-on-backflow churn-control is already handled (Case A amends the single config tip); no separate mechanism needed.
