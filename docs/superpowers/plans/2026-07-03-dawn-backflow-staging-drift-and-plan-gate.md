# Backflow staging-drift auto-heal + plan/approve gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `dawn-backflow` fetch and fold `origin/staging`'s bot-linked live-editor drift automatically (closing the gap that let today's preview-theme edits go missing), and make it print a plan report and wait for explicit approval before committing anything, instead of committing silently in one shot.

**Architecture:** Two additive layers on top of the existing 2026-07-02 leaf-level config reconciler. (1) Generalize the reconciler's "other ref" from a hardcoded `current` to a parameter, and call it a second time against a new `dawn::staging_remote_ref` (mirrors `dawn::current_ref`) for config-class files; fall back to a real `git merge-tree` 3-way text merge only for the one file class with no leaf reconciler (locale files). (2) Split `backflow.sh` into a default read-only-in-effect PLAN mode (does the real work on `staging`, prints a report, then hard-resets `staging` back to its starting commit) and an explicit `--apply` mode (does the same work and keeps it).

**Tech Stack:** bash, git (2.38+ for `git merge-tree --write-tree`), jq. Existing test harness: `.claude/skills/_dawn-ops-lib/tests/*.sh`, plain-bash assertions, no framework.

**Design docs:**
- `docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md` (the reconciler being generalized)
- `docs/superpowers/specs/2026-07-03-dawn-backflow-staging-drift-and-plan-gate-design.md` (this plan's spec — read §2 and §3 before starting, they define the exact ordering and exit-code contract this plan implements)

---

## File structure

| File | Role |
|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | Add `DAWN_STOP_APPROVAL=22`, `dawn::staging_remote_ref`, `dawn::nonconfig_drift_scan`/`apply`. Generalize `dawn::config_targets`, `dawn::reconcile_scan`, `dawn::reconcile_apply` to take an optional "other ref" param (default: `dawn::current_ref`, so existing callers are unaffected). |
| `.claude/skills/_dawn-ops-lib/tests/helpers.sh` | `dawn_test_repo()` grows a `staging_remote` branch (mirrors the existing `current` branch); `in_repo()` grows `DAWN_STAGING_REMOTE_REF=staging_remote` in its env. |
| `.claude/skills/_dawn-ops-lib/tests/test_staging_remote_ref.sh` (new) | Covers `dawn::staging_remote_ref`'s test seam. |
| `.claude/skills/_dawn-ops-lib/tests/test_reconcile_other_ref.sh` (new) | Covers the generalized `dawn::reconcile_scan`/`config_targets` against a non-`current` other-ref. |
| `.claude/skills/_dawn-ops-lib/tests/test_nonconfig_drift.sh` (new) | Covers `dawn::nonconfig_drift_scan`/`apply` (clean fold, no-op, conflict). |
| `.claude/skills/dawn-backflow/backflow.sh` | Full rewrite: Step 0 (fold `origin/staging`, two sub-steps), plan/apply split, abort-and-reset helper, report. |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh` | Existing "current-ahead" scenario updated for the new plan/apply split (the other 3 scenarios are staging-ahead-only / pure-collapse and are unaffected — verified in spec research). |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh` (new) | New integration scenarios: clean config-class drift fold (this incident's shape), drift collision, non-config drift + conflict, drift+current together, plan-then-abort leaves no trace, plan/apply consistency. |
| `.claude/skills/dawn-backflow/SKILL.md` | Document exit `22`, the report format, and the `--apply` re-run step. |
| `.claude/skills/_dawn-ops-lib/conventions.md` | §2a: backflow now self-heals `origin/staging` drift automatically. §4: mention the plan/apply split. |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | Update the backflow line in the skill table. |

---

## Task 1: Test harness — `staging_remote` branch + `DAWN_STOP_APPROVAL`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh:5`
- Modify: `.claude/skills/_dawn-ops-lib/tests/helpers.sh:14-22, 26-30`

- [ ] **Step 1: Add the new exit-code constant**

In `.claude/skills/_dawn-ops-lib/dawn-ops.sh`, line 5, change:

```bash
DAWN_OK=0 DAWN_GUARD=10 DAWN_STOP_LIVE=20 DAWN_STOP_JUDGMENT=21 DAWN_VERIFY=30
```

to:

```bash
DAWN_OK=0 DAWN_GUARD=10 DAWN_STOP_LIVE=20 DAWN_STOP_JUDGMENT=21 DAWN_STOP_APPROVAL=22 DAWN_VERIFY=30
```

Also update the exit-code contract comment on line 3 from:

```bash
# Exit-code contract: 0 ok · 10 guard · 20 stop-live · 21 stop-judgment · 30 verify
```

to:

```bash
# Exit-code contract: 0 ok · 10 guard · 20 stop-live · 21 stop-judgment · 22 stop-approval · 30 verify
```

- [ ] **Step 2: Add the `staging_remote` branch to the test fixture repo**

In `.claude/skills/_dawn-ops-lib/tests/helpers.sh`, in `dawn_test_repo()`:

```bash
dawn_test_repo(){
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" commit -q --allow-empty -m base
  git -C "$d" branch staging
  git -C "$d" branch current
  git -C "$d" branch staging_remote      # bot-linked remote copy of staging (§2, plan.md)
  git -C "$d" branch customizations    # collapse floor for backflow (staging's stable base)
  echo "$d"
}
```

(one new line: `git -C "$d" branch staging_remote`, placed next to `current` since they play the
same structural role — a local branch standing in for a remote ref via the `DAWN_*_REF` test seam)

- [ ] **Step 3: Wire the test seam into `in_repo`**

In the same file, change:

```bash
in_repo(){
  local d="$1"; shift
  ( cd "$d" && DAWN_CURRENT_REF=current bash -c "source '$DAWN_LIB_SRC'; $*" )
}
```

to:

```bash
in_repo(){
  local d="$1"; shift
  ( cd "$d" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
    bash -c "source '$DAWN_LIB_SRC'; $*" )
}
```

- [ ] **Step 4: Run the existing suite to confirm nothing broke**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all tests still pass (`staging_remote` is an inert extra branch at this point — nothing
reads it yet).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/helpers.sh
git commit -m "test(ops): add staging_remote fixture branch + DAWN_STOP_APPROVAL constant"
```

---

## Task 2: `dawn::staging_remote_ref`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh` (add after `dawn::current_ref`, around line 35)
- Test: `.claude/skills/_dawn-ops-lib/tests/test_staging_remote_ref.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/_dawn-ops-lib/tests/test_staging_remote_ref.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

d=$(dawn_test_repo)
out=$(in_repo "$d" 'dawn::staging_remote_ref')
assert_eq "$out" "staging_remote" "test seam wins over remote-ref detection"

echo "  staging_remote_ref ok"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_staging_remote_ref.sh`
Expected: FAIL — `dawn::staging_remote_ref: command not found`

- [ ] **Step 3: Add the function**

In `.claude/skills/_dawn-ops-lib/dawn-ops.sh`, immediately after `dawn::current_ref` (after line 35):

```bash

# Resolve the ref that represents the staging preview theme's bot-linked remote copy.
# Test seam: DAWN_STAGING_REMOTE_REF.
dawn::staging_remote_ref(){
  if [ -n "${DAWN_STAGING_REMOTE_REF:-}" ]; then echo "$DAWN_STAGING_REMOTE_REF"; return 0; fi
  if git rev-parse --verify -q refs/remotes/origin/staging >/dev/null; then
    echo refs/remotes/origin/staging
  else
    echo origin/staging
  fi
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_staging_remote_ref.sh`
Expected: PASS (`staging_remote_ref ok`)

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_staging_remote_ref.sh
git commit -m "feat(ops): add dawn::staging_remote_ref"
```

---

## Task 3: Generalize the leaf reconciler to a parameterized "other ref"

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh:106-118` (`dawn::config_targets`), `:126-154` (`dawn::reconcile_scan`), `:184-231` (`dawn::reconcile_apply`)
- Test: `.claude/skills/_dawn-ops-lib/tests/test_reconcile_other_ref.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/_dawn-ops-lib/tests/test_reconcile_other_ref.sh` (mirrors the existing
`test_reconcile_scan.sh` collision fixture, but points the "other ref" at `staging_remote` instead
of relying on the default):

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

d=$(dawn_test_repo)
# base
commit_on "$d" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"base","fold_remote":"base","collide":"base"}}}}
JSON
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
# staging edits keep_staging + collide
commit_on "$d" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"S","fold_remote":"base","collide":"S"}}}}
JSON
# staging_remote (the bot) edits fold_remote + collide
commit_on "$d" staging_remote sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"base","fold_remote":"R","collide":"R"}}}}
JSON

other=$(in_repo "$d" 'dawn::staging_remote_ref')
scan=$(in_repo "$d" "dawn::reconcile_scan $other")
assert_contains "$scan" 'staging_ahead	sections/footer-group.json	["sections","f","settings","keep_staging"]' "staging_ahead vs other ref"
assert_contains "$scan" 'current_ahead	sections/footer-group.json	["sections","f","settings","fold_remote"]' "other-ref-ahead reuses current_ahead verdict name"
assert_contains "$scan" 'collision	sections/footer-group.json	["sections","f","settings","collide"]' "collision vs other ref"

# default (no arg) must be unaffected — still compares against dawn::current_ref
default_scan=$(in_repo "$d" 'dawn::reconcile_scan')
assert_not_contains "$default_scan" "fold_remote" "default call site untouched by the new param"

# dawn::reconcile_apply against the other ref folds fold_remote and leaves keep_staging alone
echo "R" > /tmp/dawn_test_decision_$$
decisions_file="$(mktemp)"
printf 'sections/footer-group.json\t["sections","f","settings","collide"]\tvalue:"R"\n' > "$decisions_file"
merged=$(in_repo "$d" "dawn::reconcile_apply sections/footer-group.json $decisions_file $other")
assert_contains "$merged" '"fold_remote": "R"' "reconcile_apply folds other-ref-ahead value"
assert_contains "$merged" '"keep_staging": "S"' "reconcile_apply keeps staging value"
assert_contains "$merged" '"collide": "R"' "reconcile_apply applies the collision decision"
rm -f "$decisions_file" /tmp/dawn_test_decision_$$

echo "  reconcile_other_ref ok"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_other_ref.sh`
Expected: FAIL — `dawn::reconcile_scan` ignores the argument today (it always compares against
`dawn::current_ref`), so the `fold_remote`/`collide` assertions against `staging_remote` fail.

- [ ] **Step 3: Generalize `dawn::config_targets`**

In `.claude/skills/_dawn-ops-lib/dawn-ops.sh`, replace (lines 104-118):

```bash
# Files to reconcile: all existing config-paths.txt files, plus suffix templates
# that differ across any pair of {base, staging, current}.
dawn::config_targets(){
  local cur base; cur="$(dawn::current_ref)"; base="$(git merge-base staging "$cur" 2>/dev/null)"
  {
    dawn::config_files
    if [ -n "$base" ]; then
      { git diff --name-only "$base" staging      -- 'templates/'
        git diff --name-only "$base" "$cur"       -- 'templates/'
        git diff --name-only staging "$cur"       -- 'templates/'; } \
      | grep -E '^templates/[a-z_]+\.[a-z0-9_-]+\.json$' \
      | grep -vxFf <(printf '%s\n' "$DAWN_CONFIG_PATHS") || true
    fi
  } | sort -u
}
```

with:

```bash
# Files to reconcile: all existing config-paths.txt files, plus suffix templates
# that differ across any pair of {base, staging, <other>}.
# <other> defaults to dawn::current_ref (existing call sites keep today's behavior); pass
# dawn::staging_remote_ref explicitly to reconcile against the staging preview theme's bot instead.
dawn::config_targets(){
  local other="${1:-$(dawn::current_ref)}"
  local base; base="$(git merge-base staging "$other" 2>/dev/null)"
  {
    dawn::config_files
    if [ -n "$base" ]; then
      { git diff --name-only "$base" staging  -- 'templates/'
        git diff --name-only "$base" "$other" -- 'templates/'
        git diff --name-only staging "$other" -- 'templates/'; } \
      | grep -E '^templates/[a-z_]+\.[a-z0-9_-]+\.json$' \
      | grep -vxFf <(printf '%s\n' "$DAWN_CONFIG_PATHS") || true
    fi
  } | sort -u
}
```

- [ ] **Step 4: Generalize `dawn::reconcile_scan`**

Replace (lines 120-154, the whole function and its doc comment):

```bash
# 3-way classify every leaf of every reconcile target.
# Emits (only for non-agreeing leaves), tab-separated:
#   <verdict>\t<file>\t<path-json>\t<base>\t<staging>\t<current>
# verdict ∈ current_ahead | staging_ahead | collision.  Absent => $DAWN_ABSENT.
# NOTE: awk (not bash assoc arrays) for grouping; awk (not sed) for tab tagging.
# Safe because leaf lines are canonical jq -c: values never contain a raw TAB.
dawn::reconcile_scan(){
  local cur base f
  cur="$(dawn::current_ref)"
  base="$(git merge-base staging "$cur" 2>/dev/null)" \
    || { echo "GUARD: no merge-base for staging vs $cur" >&2; return $DAWN_GUARD; }
  [ -z "$base" ] && { echo "GUARD: no merge-base for staging vs $cur" >&2; return $DAWN_GUARD; }
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    {
      dawn::config_leaves "$base"   "$f" | awk '{print "B\t"$0}'
      dawn::config_leaves staging   "$f" | awk '{print "S\t"$0}'
      dawn::config_leaves "$cur"    "$f" | awk '{print "C\t"$0}'
    } | awk -F'\t' -v file="$f" -v ABSENT="$DAWN_ABSENT" '
      { side=$1; path=$2; val=$3; seen[path]=1
        if(side=="B"){b[path]=val}
        else if(side=="S"){s[path]=val}
        else {c[path]=val} }
      END{
        for(p in seen){
          bv=(p in b)?b[p]:ABSENT; sv=(p in s)?s[p]:ABSENT; cv=(p in c)?c[p]:ABSENT
          if(sv==cv) continue
          if(sv==bv && cv!=bv) v="current_ahead"
          else if(cv==bv && sv!=bv) v="staging_ahead"
          else v="collision"
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", v, file, p, bv, sv, cv
        }
      }'
  done < <(dawn::config_targets)
}
```

with:

```bash
# 3-way classify every leaf of every reconcile target against <other> (default dawn::current_ref).
# Emits (only for non-agreeing leaves), tab-separated:
#   <verdict>\t<file>\t<path-json>\t<base>\t<staging>\t<other>
# verdict ∈ current_ahead | staging_ahead | collision.  Absent => $DAWN_ABSENT.
# The verdict names are historical (from when <other> was always current) and are kept as-is
# regardless of which ref is passed: current_ahead means "the other side is ahead", staging_ahead
# means "staging is ahead of that same other side".
# NOTE: awk (not bash assoc arrays) for grouping; awk (not sed) for tab tagging.
# Safe because leaf lines are canonical jq -c: values never contain a raw TAB.
dawn::reconcile_scan(){
  local other="${1:-$(dawn::current_ref)}"
  local base f
  base="$(git merge-base staging "$other" 2>/dev/null)" \
    || { echo "GUARD: no merge-base for staging vs $other" >&2; return $DAWN_GUARD; }
  [ -z "$base" ] && { echo "GUARD: no merge-base for staging vs $other" >&2; return $DAWN_GUARD; }
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    {
      dawn::config_leaves "$base"   "$f" | awk '{print "B\t"$0}'
      dawn::config_leaves staging   "$f" | awk '{print "S\t"$0}'
      dawn::config_leaves "$other"  "$f" | awk '{print "C\t"$0}'
    } | awk -F'\t' -v file="$f" -v ABSENT="$DAWN_ABSENT" '
      { side=$1; path=$2; val=$3; seen[path]=1
        if(side=="B"){b[path]=val}
        else if(side=="S"){s[path]=val}
        else {c[path]=val} }
      END{
        for(p in seen){
          bv=(p in b)?b[p]:ABSENT; sv=(p in s)?s[p]:ABSENT; cv=(p in c)?c[p]:ABSENT
          if(sv==cv) continue
          if(sv==bv && cv!=bv) v="current_ahead"
          else if(cv==bv && sv!=bv) v="staging_ahead"
          else v="collision"
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", v, file, p, bv, sv, cv
        }
      }'
  done < <(dawn::config_targets "$other")
}
```

- [ ] **Step 5: Generalize `dawn::reconcile_apply`**

Replace the function signature line and its final `done < <(dawn::reconcile_scan)` call (lines 184
and 217 respectively — the body in between is untouched):

```bash
dawn::reconcile_apply(){
  local file="$1" decisions="$2"
```

with:

```bash
dawn::reconcile_apply(){
  local file="$1" decisions="$2" other="${3:-$(dawn::current_ref)}"
```

and:

```bash
  done < <(dawn::reconcile_scan)
```

with:

```bash
  done < <(dawn::reconcile_scan "$other")
```

Also update its doc comment (the line starting `# Args: <file> <decisions-file>`) to:

```bash
# Args: <file> <decisions-file> [<other-ref>, default dawn::current_ref].
```

- [ ] **Step 6: Run the new test to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_other_ref.sh`
Expected: PASS (`reconcile_other_ref ok`)

- [ ] **Step 7: Run the full suite to confirm no regressions**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all tests pass, including the pre-existing `test_reconcile_scan.sh`,
`test_reconcile_apply.sh`, `test_reconcile_pending.sh`, `test_backflow.sh` (their calls all omit
the new parameter, so they exercise the `${1:-$(dawn::current_ref)}` default path).

- [ ] **Step 8: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_reconcile_other_ref.sh
git commit -m "feat(ops): parameterize the leaf reconciler's comparison ref"
```

---

## Task 4: Non-config-file drift fold (raw 3-way merge)

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh` (add after `dawn::reconcile_apply`, around line 232)
- Test: `.claude/skills/_dawn-ops-lib/tests/test_nonconfig_drift.sh` (new)

- [ ] **Step 1: Write the failing tests**

Create `.claude/skills/_dawn-ops-lib/tests/test_nonconfig_drift.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Clean fold: staging and staging_remote each change a different, non-adjacent key in a locale file.
d=$(dawn_test_repo)
commit_on "$d" staging locales/nl.json <<'JSON'
{
  "a": "base-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "base-e"
}
JSON
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
commit_on "$d" staging locales/nl.json <<'JSON'
{
  "a": "staging-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "base-e"
}
JSON
commit_on "$d" staging_remote locales/nl.json <<'JSON'
{
  "a": "base-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "bot-e"
}
JSON
git -C "$d" checkout -q staging

out=$(in_repo "$d" 'dawn::nonconfig_drift_scan'); rc=$?
assert_rc "$rc" 0 "clean non-config drift scan ok"
assert_contains "$out" "locales/nl.json" "changed file reported"

in_repo "$d" 'dawn::nonconfig_drift_apply'
folded=$(git -C "$d" show staging:locales/nl.json 2>/dev/null || cat "$d/locales/nl.json")
# reconcile_apply writes to the *working tree*, not a commit — read the file directly
folded=$(cat "$d/locales/nl.json")
assert_contains "$folded" '"e": "bot-e"' "bot edit folded into working tree"
assert_contains "$folded" '"a": "staging-a"' "staging's own edit preserved"

# No drift: staging_remote unchanged since merge-base
d2=$(dawn_test_repo)
commit_on "$d2" staging locales/nl.json <<< '{"a":"x"}'
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging
out2=$(in_repo "$d2" 'dawn::nonconfig_drift_scan'); rc2=$?
assert_rc "$rc2" 0 "no-drift scan ok"
assert_eq "$out2" "" "no-drift scan reports nothing"

# Conflict: both sides change the exact same line
d3=$(dawn_test_repo)
commit_on "$d3" staging locales/nl.json <<< '{"a":"base"}'
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging locales/nl.json <<< '{"a":"staging-value"}'
commit_on "$d3" staging_remote locales/nl.json <<< '{"a":"bot-value"}'
git -C "$d3" checkout -q staging
out3=$(in_repo "$d3" 'dawn::nonconfig_drift_scan'); rc3=$?
assert_rc "$rc3" 1 "conflicting drift scan returns 1"
assert_contains "$out3" "locales/nl.json" "conflicting file named"

echo "  nonconfig_drift ok"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_nonconfig_drift.sh`
Expected: FAIL — `dawn::nonconfig_drift_scan: command not found`

- [ ] **Step 3: Add the functions**

In `.claude/skills/_dawn-ops-lib/dawn-ops.sh`, immediately after `dawn::reconcile_apply` (after the
closing `}` around line 232):

```bash

# Read-only-in-effect preview of folding dawn::staging_remote_ref's remaining (non-leaf-reconciled)
# drift into staging — in practice, locale files (dawn::config_class has no leaf reconciler for
# them). Call this AFTER the config-class fold (dawn::reconcile_apply against
# dawn::staging_remote_ref) has been committed, so config-class files no longer differ here and
# don't spuriously surface as conflicts.
# Real 3-way text merge (git merge-tree), since no leaf-level reconciler covers these paths.
# Stdout: one changed-file path per line. Exit 0 = clean (list may be empty). Exit 1 = conflict
# (same file list — see caller for the "resolve manually" message).
dawn::nonconfig_drift_scan(){
  local remote base changed
  remote="$(dawn::staging_remote_ref)"
  git rev-parse --verify -q "$remote" >/dev/null 2>&1 || return 0
  base="$(git merge-base staging "$remote" 2>/dev/null)" \
    || { echo "GUARD: no merge-base for staging vs $remote" >&2; return 1; }
  [ -z "$base" ] && { echo "GUARD: no merge-base for staging vs $remote" >&2; return 1; }
  changed="$(git diff --name-only "$base" "$remote" -- .)"
  [ -z "$changed" ] && return 0

  if git merge-tree --write-tree --merge-base="$base" staging "$remote" >/dev/null 2>&1; then
    printf '%s\n' "$changed"
    return 0
  fi
  printf '%s\n' "$changed"
  return 1
}

# Materialize dawn::nonconfig_drift_scan's clean fold into the working tree. Call only after a 0
# return from dawn::nonconfig_drift_scan. No commit is created — same working-tree-write pattern
# as dawn::reconcile_apply's callers.
dawn::nonconfig_drift_apply(){
  local remote base tree f blob content
  remote="$(dawn::staging_remote_ref)"
  base="$(git merge-base staging "$remote" 2>/dev/null)" || return 1
  tree="$(git merge-tree --write-tree --merge-base="$base" staging "$remote" 2>/dev/null | head -1)"
  [ -z "$tree" ] && return 1
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    blob="$(git rev-parse "$tree:$f" 2>/dev/null)" || continue
    content="$(git cat-file -p "$blob" 2>/dev/null)" || continue
    mkdir -p "$(dirname "$f")"
    printf '%s\n' "$content" > "$f"
  done < <(git diff --name-only "$base" "$remote" -- .)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_nonconfig_drift.sh`
Expected: PASS (`nonconfig_drift ok`)

If the conflict case (d3) doesn't reproduce a conflict (git's merge can be more permissive than
expected for a single-line file), replace the `d3` fixture's JSON with a multi-line pretty-printed
object where both sides edit the exact same line (matching the reproduction in the design doc's
Part A correction note), e.g.:

```bash
commit_on "$d3" staging locales/nl.json <<'JSON'
{
  "a": "base",
  "b": "base"
}
JSON
```

then edit `"a"` on both sides to different values — a same-line edit reliably conflicts.

- [ ] **Step 5: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_nonconfig_drift.sh
git commit -m "feat(ops): add dawn::nonconfig_drift_scan/apply (raw merge for non-leaf-reconciled files)"
```

---

## Task 5: Rewrite `backflow.sh` — Step 0 fold + plan/apply split

**Files:**
- Modify: `.claude/skills/dawn-backflow/backflow.sh` (full rewrite)

This task has no isolated unit test of its own — Task 6 covers it end-to-end via
`test_backflow.sh` and `test_backflow_drift.sh`. Write the implementation now; Task 6 proves it.

- [ ] **Step 1: Replace the entire file**

Replace the full contents of `.claude/skills/dawn-backflow/backflow.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

# Optional decisions file for collisions: --decisions <path>
# Apply mode: --apply (default is PLAN — does the real work, then hard-resets staging back to
# where it started, so a plan-only run never leaves a lasting change).
DECISIONS=/dev/null
APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --decisions) DECISIONS="${2:?}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    *) echo "GUARD: unknown argument: $1" >&2; exit $DAWN_GUARD ;;
  esac
done

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD
cur="$(dawn::current_ref)"
staging_remote="$(dawn::staging_remote_ref)"
git fetch origin current --quiet 2>/dev/null || true
git fetch origin staging --quiet 2>/dev/null || true
base="$(git merge-base staging "$cur" 2>/dev/null)" \
  || { echo "GUARD: no merge-base staging vs $cur" >&2; exit $DAWN_GUARD; }

orig_sha="$(git rev-parse staging)"
dawn::with_branch staging || exit $DAWN_GUARD

# Every exit from here on that isn't a genuine success (apply-mode exit 0) must leave staging
# exactly as it started — including the plan-mode "everything's fine, please approve" exit.
_dawn_bf_abort(){ git reset -q --hard "$orig_sha" 2>/dev/null || true; exit "$1"; }

report_staging_remote=()
report_current=()

# --- Step 0a: fold origin/staging's config-class drift (same leaf reconciler as current) ---
sr_scan="$(dawn::reconcile_scan "$staging_remote")" || _dawn_bf_abort $DAWN_GUARD
sr_collisions="$(grep -E '^collision'$'\t' <<< "$sr_scan" || true)"
if [ -n "$sr_collisions" ]; then
  missing=""
  while IFS=$'\t' read -r verdict f p b s c; do
    res="$(awk -F'\t' -v ff="$f" -v pp="$p" '$1==ff && $2==pp {print $3}' "$DECISIONS" 2>/dev/null | head -1)"
    [ -z "$res" ] && missing+="$f"$'\t'"$p"$'\t'"base=$b"$'\t'"staging=$s"$'\t'"origin/staging=$c"$'\n'
  done <<< "$sr_collisions"
  if [ -n "$missing" ]; then
    echo "STOP: origin/staging config collisions need decisions (keep staging / take origin/staging / enter value):" >&2
    printf '%s' "$missing" >&2
    _dawn_bf_abort $DAWN_STOP_JUDGMENT
  fi
fi
sr_config_changed=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  merged="$(dawn::reconcile_apply "$f" "$DECISIONS" "$staging_remote")" || _dawn_bf_abort $?
  [ -z "$merged" ] && continue
  if [ ! -f "$f" ] || [ "$(cat "$f")" != "$merged" ]; then
    mkdir -p "$(dirname "$f")"; printf '%s\n' "$merged" > "$f"
    report_staging_remote+=("$f")
    sr_config_changed=1
  fi
done < <(dawn::config_targets "$staging_remote")
if [ "$sr_config_changed" = "1" ]; then
  git add -A
  git commit -q -m "fold origin/staging (config)"
fi

# --- Step 0b: fold origin/staging's remaining (non-config) drift (raw 3-way merge) ---
nc_out="$(dawn::nonconfig_drift_scan)"; nc_rc=$?
if [ "$nc_rc" = "1" ]; then
  echo "GUARD: origin/staging conflicts with local staging in:" >&2
  sed 's/^/  /' <<< "$nc_out" >&2
  echo "Resolve manually (e.g. git merge $staging_remote on a scratch branch, or hand-edit) and re-run." >&2
  _dawn_bf_abort $DAWN_GUARD
fi
if [ -n "$nc_out" ]; then
  dawn::nonconfig_drift_apply
  git add -A
  git commit -q -m "fold origin/staging (other)"
  while IFS= read -r f; do [ -n "$f" ] && report_staging_remote+=("$f"); done <<< "$nc_out"
fi

# --- Step 1: direction-aware non-config partition (current vs staging, unchanged) ---
noncfg=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -n "$(dawn::config_class "$f")" ] && continue
  git diff --quiet "$base" "$cur" -- "$f" && continue
  noncfg+=("$f")
done < <(git diff --name-only staging "$cur" -- . ':(exclude)docs/' ':(exclude).claude/')

if [ "${#noncfg[@]}" -gt 0 ]; then
  echo "STOP: current-ahead non-config changes need classification (enrichment vs generic-L1 vs ignore):" >&2
  printf '  %s\n' "${noncfg[@]}" >&2
  echo "Decide per file: enrichment -> own L2 commit; generic -> dawn-harvest; churn -> ignore." >&2
  _dawn_bf_abort $DAWN_STOP_JUDGMENT
fi

# --- Step 2: current-vs-staging collisions without decisions -> stop and list (unchanged) ---
scan="$(dawn::reconcile_scan)" || _dawn_bf_abort $DAWN_GUARD
collisions="$(grep -E '^collision'$'\t' <<< "$scan" || true)"
if [ -n "$collisions" ]; then
  missing=""
  while IFS=$'\t' read -r verdict f p b s c; do
    res="$(awk -F'\t' -v ff="$f" -v pp="$p" '$1==ff && $2==pp {print $3}' "$DECISIONS" 2>/dev/null | head -1)"
    [ -z "$res" ] && missing+="$f"$'\t'"$p"$'\t'"base=$b"$'\t'"staging=$s"$'\t'"current=$c"$'\n'
  done <<< "$collisions"
  if [ -n "$missing" ]; then
    echo "STOP: config collisions need decisions (keep staging / take current / enter value):" >&2
    printf '%s' "$missing" >&2
    _dawn_bf_abort $DAWN_STOP_JUDGMENT
  fi
fi

# --- Step 3: apply current-vs-staging reconcile folds (unchanged) ---
while IFS= read -r f; do
  [ -z "$f" ] && continue
  merged="$(dawn::reconcile_apply "$f" "$DECISIONS")" || _dawn_bf_abort $?
  [ -z "$merged" ] && continue
  if [ ! -f "$f" ] || [ "$(cat "$f")" != "$merged" ]; then
    mkdir -p "$(dirname "$f")"; printf '%s\n' "$merged" > "$f"
    report_current+=("$f")
  fi
done < <(dawn::config_targets)

# --- Step 4: collapse the contiguous config-only commit run at the tip into ONE snapshot (unchanged) ---
cust_base="$(git merge-base staging customizations 2>/dev/null)" \
  || { echo "GUARD: no merge-base with customizations; cannot collapse snapshot" >&2; _dawn_bf_abort $DAWN_GUARD; }
[ -z "$cust_base" ] && { echo "GUARD: no merge-base with customizations" >&2; _dawn_bf_abort $DAWN_GUARD; }
floor="$cust_base"
for c in $(git rev-list staging "^$cust_base"); do
  dawn::_commit_is_config_only "$c" || { floor="$c"; break; }
done

git add -A
git reset -q --soft "$floor"
if git diff --cached --quiet; then
  git commit -q --allow-empty -m "L2: store config snapshot (reconciled)"
else
  git commit -q -m "L2: store config snapshot (reconciled)"
fi

# --- Report / approval gate ---
if [ "${#report_staging_remote[@]}" = "0" ] && [ "${#report_current[@]}" = "0" ]; then
  if git diff --quiet "$floor" HEAD -- .; then
    echo "Nothing to reconcile; staging config collapsed to one empty snapshot at the tip."
  else
    echo "Backflow complete: staging config collapsed into one snapshot at the tip."
  fi
  exit $DAWN_OK
fi

if [ "$APPLY" != "1" ]; then
  echo "Backflow plan:"
  echo
  if [ "${#report_staging_remote[@]}" -gt 0 ]; then
    echo "Pulling in from the live preview theme ($staging_remote) — your local copy didn't have these:"
    printf '  - %s\n' "${report_staging_remote[@]}"
    echo
  fi
  if [ "${#report_current[@]}" -gt 0 ]; then
    echo "Folding in from the live published theme ($cur):"
    printf '  - %s\n' "${report_current[@]}"
    echo
  fi
  rerun="bash .claude/skills/dawn-backflow/backflow.sh --apply"
  [ "$DECISIONS" != "/dev/null" ] && rerun="$rerun --decisions $DECISIONS"
  echo "Proceed? re-run with: $rerun"
  _dawn_bf_abort $DAWN_STOP_APPROVAL
fi

echo "Backflow complete: staging config collapsed into one snapshot at the tip."
exit $DAWN_OK
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/dawn-backflow/backflow.sh
git commit -m "feat(ops): backflow folds origin/staging drift + gates on a plan/approve report"
```

---

## Task 6: Backflow integration tests

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh:18-27` (current-ahead scenario)
- Create: `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh`

- [ ] **Step 1: Update the existing "current-ahead" scenario for the plan/apply split**

In `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh`, replace lines 18-27:

```bash
# current-ahead => folded into the single collapsed snapshot
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
commit_on "$d2" current config/settings_data.json <<< '{"k":"live"}'
git -C "$d2" checkout -q staging
( cd "$d2" && DAWN_CURRENT_REF=current bash "$BF" ); rc=$?
assert_rc "$rc" 0 "current-ahead backflow ok"
assert_eq "$(git -C "$d2" show staging:config/settings_data.json | jq -r .k)" "live" "current folded"
assert_eq "$(git -C "$d2" rev-list --count customizations..staging)" "1" "collapsed to one snapshot commit"
```

with:

```bash
# current-ahead => plan reports it and gates on --apply; --apply folds it into one snapshot
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
commit_on "$d2" current config/settings_data.json <<< '{"k":"live"}'
git -C "$d2" checkout -q staging
before_sha=$(git -C "$d2" rev-parse staging)

( cd "$d2" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote bash "$BF" )
plan_rc=$?
assert_rc "$plan_rc" 22 "current-ahead plan stops for approval"
assert_eq "$(git -C "$d2" rev-parse staging)" "$before_sha" "plan-only run leaves staging untouched"

( cd "$d2" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote bash "$BF" --apply )
apply_rc=$?
assert_rc "$apply_rc" 0 "current-ahead apply ok"
assert_eq "$(git -C "$d2" show staging:config/settings_data.json | jq -r .k)" "live" "current folded"
assert_eq "$(git -C "$d2" rev-list --count customizations..staging)" "1" "collapsed to one snapshot commit"
```

Then update the other three invocations in the same file (the `staging-ahead`, `multiple config
commits`, and `enrichment floor` scenarios, none of which produce a fold from `current` or
`origin/staging` — verified in the design/plan research: they only stay `rc 0` immediately because
nothing external gets folded) to also pass `DAWN_STAGING_REMOTE_REF=staging_remote`, so the new
`staging_remote` fetch/scan step has a valid (empty-drift) ref to resolve instead of failing to
find `origin/staging` in the throwaway repo. For each of the three remaining
`DAWN_CURRENT_REF=current bash "$BF"` invocations, change to
`DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote bash "$BF"`. Their assertions
(`assert_rc "$rc" 0 ...`) are otherwise unchanged — none of them fold anything external, so they
stay on the immediate-exit-0 fast path.

- [ ] **Step 2: Run the updated file to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_backflow.sh`
Expected: PASS (`  backflow ok`)

- [ ] **Step 3: Write the new drift-integration test file**

Create `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"
run(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote bash "$BF" "${@:2}" ); }

# 1) Clean config-class drift fold (this incident's shape): origin/staging has a suffix-template
#    settings edit local staging never fetched. Plan reports it; --apply folds it.
d=$(dawn_test_repo)
commit_on "$d" staging templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":36}}}}
JSON
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
commit_on "$d" staging_remote templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":0}}}}
JSON
git -C "$d" checkout -q staging
before=$(git -C "$d" rev-parse staging)
run "$d"; assert_rc "$?" 22 "clean drift: plan stops for approval"
assert_eq "$(git -C "$d" rev-parse staging)" "$before" "clean drift: plan-only run untouched"
run "$d" --apply; assert_rc "$?" 0 "clean drift: apply ok"
assert_eq "$(git -C "$d" show staging:templates/page.withdrawal.json | jq -r .sections.wf.settings.padding_bottom)" "0" "bot edit folded"

# 2) Config-class drift collision: same setting edited both live (staging_remote) and locally.
d2=$(dawn_test_repo)
commit_on "$d2" staging templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":36}}}}
JSON
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
commit_on "$d2" staging templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":10}}}}
JSON
commit_on "$d2" staging_remote templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":0}}}}
JSON
git -C "$d2" checkout -q staging
run "$d2"; assert_rc "$?" 21 "drift collision: stops for decision"
decisions=$(mktemp)
printf 'templates/page.withdrawal.json\t["sections","wf","settings","padding_bottom"]\tvalue:0\n' > "$decisions"
run "$d2" --decisions "$decisions"; assert_rc "$?" 22 "drift collision: plan resolves, waits for apply"
run "$d2" --apply --decisions "$decisions"; assert_rc "$?" 0 "drift collision: apply ok"
assert_eq "$(git -C "$d2" show staging:templates/page.withdrawal.json | jq -r .sections.wf.settings.padding_bottom)" "0" "collision resolved to entered value"
rm -f "$decisions"

# 3) Non-config drift conflict (locale file, same line edited both places) -> GUARD, nothing written.
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging_remote locales/nl.json <<'JSON'
{
  "a": "bot-value",
  "b": "base"
}
JSON
git -C "$d3" checkout -q staging
commit_on "$d3" staging locales/nl.json <<'JSON'
{
  "a": "staging-value",
  "b": "base"
}
JSON
before3=$(git -C "$d3" rev-parse staging)
run "$d3"; assert_rc "$?" 10 "non-config drift conflict: GUARD"
assert_eq "$(git -C "$d3" rev-parse staging)" "$before3" "GUARD leaves staging untouched"

# 4) Plan/apply consistency: apply's commit matches what the immediately preceding plan reported.
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
commit_on "$d4" current config/settings_data.json <<< '{"k":"live"}'
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging
plan_out=$(run "$d4"); assert_rc "$?" 22 "plan/apply consistency: plan stops"
apply_out=$(run "$d4" --apply); assert_rc "$?" 0 "plan/apply consistency: apply ok"
assert_eq "$(git -C "$d4" show staging:config/settings_data.json | jq -r .k)" "live" "apply matches what plan reported"
assert_contains "$plan_out" "config/settings_data.json" "plan report named the folded file"

echo "  backflow_drift ok"
```

- [ ] **Step 4: Run it to verify it fails, then implement any gaps it surfaces**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh`
Expected: this exercises Task 5's rewrite end-to-end for the first time. If it fails, debug against
`backflow.sh`'s actual stdout/stderr (run the `run "$d" ...` lines manually with output visible) —
common culprits: `git merge -q staging_remote -m sync` ordering (the `staging_remote` branch must
be created at the point it's meant to represent the last-shared state, mirroring how `current` is
synced in the existing fixtures), or a missing `DAWN_STAGING_REMOTE_REF` in a `run` call.

- [ ] **Step 5: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all tests pass, including `test_promote_guard.sh` (uses `dawn::reconcile_pending`, which
calls `dawn::reconcile_scan` with no args — must still default to `dawn::current_ref` and be
unaffected by this feature).

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/tests/test_backflow.sh .claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh
git commit -m "test(ops): cover backflow's origin/staging drift fold + plan/approve gate"
```

---

## Task 7: Update `dawn-backflow/SKILL.md`

**Files:**
- Modify: `.claude/skills/dawn-backflow/SKILL.md`

- [ ] **Step 1: Rewrite the Overview and Running sections**

Replace the file's contents (all 70 lines) with:

```markdown
---
name: dawn-backflow
description: Pull live Shopify admin/config edits from the current branch back into staging. Use when the user says backflow, capture admin changes, sync config from live, or before a promote.
---

## Overview

The `dawn-backflow` skill folds live admin/config edits into `staging`'s config-snapshot commit
from **two** bot-linked sources: the published theme (`current`) and the staging preview theme
itself (`origin/staging` — Shopify's GitHub integration writes live-editor commits there directly,
same as it does for `current`). It fetches both automatically on every run. If non-config changes
are detected, it stops and asks the human to classify each file. Before committing anything, it
prints a plan report and waits for explicit approval.

## Prerequisites

- Be checked out on the `ops` branch (never on `current`).
- Conventions reference: `.claude/skills/_dawn-ops-lib/conventions.md`

## Running

```bash
bash .claude/skills/dawn-backflow/backflow.sh
```

This is **plan mode** (the default) — it fetches, reconciles, and computes everything, but does not
leave a lasting commit unless you re-run with `--apply`. Backflow performs a **direction-aware
3-way reconcile** (see `docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md` and
`docs/superpowers/specs/2026-07-03-dawn-backflow-staging-drift-and-plan-gate-design.md`) against
both `current` and `origin/staging`:

- **staging-ahead** settings (you changed them in staging's preview theme) are **kept** and will
  promote to `current`.
- **current-ahead** / **origin/staging-ahead** settings (edited live) are **folded** into staging's
  snapshot.
- **collisions** (both sides changed the same setting differently) stop for your decision.
- Non-config drift from `origin/staging` (in practice, locale files) folds via a plain 3-way text
  merge; a genuine conflict there is a guard, not a decision prompt (no per-key UI exists for it).

### Exit 0 — nothing to reconcile, or apply completed

Either there was nothing to fold from any live source (report with the user which case), or you
ran with `--apply` and the config snapshot at the tip of `staging` now holds the reconciled result.

### Exit 10 — guard triggered

Report the guard message from stderr. Common causes:

- **Dirty working tree** — commit or stash local changes first, then re-run.
- **Staging tip is not the config snapshot** — the commit ordering is wrong; fix the branch
  ordering first.
- **`origin/staging` conflicts with local staging** in a non-config file (in practice, a locale
  file edited on the same line both live and locally) — no automated resolution exists for this;
  resolve by hand (e.g. `git merge origin/staging` on a scratch branch) and re-run.

### Exit 21 — decisions or classification needed

Three possible causes, checked in this order — resolve one, re-run, and you'll hit the next if it
also applies:

1. **`origin/staging` config collisions.** Same shape as (2) below, but the "other side" is the
   staging preview theme's live editor instead of the published theme. Ask via `AskUserQuestion`
   with **Keep staging** / **Take origin/staging** / **Enter a value**, write to the same decisions
   TSV, re-run with `--decisions`.
2. **Config collisions** (current vs. staging). The script prints each colliding `file → path` with
   its base / staging / current values. For each, ask the operator via `AskUserQuestion`:

   | Option | Meaning |
   |---|---|
   | **Keep staging** | staging's value wins (promotes to current) |
   | **Take current** | fold the live edit into staging |
   | **Enter a value** | supply a replacement (follow-up open-text; parsed as JSON when valid) |

   Write the answers to a decisions TSV — one line per collision:
   `<file>\t<path-json>\t<staging|current|value:JSON>` — then re-run:

   ```bash
   bash .claude/skills/dawn-backflow/backflow.sh --decisions /tmp/decisions.tsv
   ```

3. **Current-ahead non-config files.** Classify each per the table below (enrichment → own L2
   commit; generic → `dawn-harvest`; churn → ignore), then re-run.

| Classification | Action |
|---|---|
| **Enrichment** (L2 store-specific logic or content) | Create its own L2 commit on `staging` per conventions §4 Case B |
| **Generic L1 improvement** (something all Dawn stores would want) | Use the `dawn-harvest` skill to pull it into the `customizations` layer |
| **Churn / noise** (reverted, irrelevant, or already present) | Ignore — no action needed |

### Exit 22 — plan ready, needs approval

Every collision and classification above is resolved; nothing more needs a decision. The script
printed a plan report to stdout listing exactly what it will fold from `origin/staging` and from
`current`. **Relay the report to the user verbatim** and ask one `AskUserQuestion`
(approve/abort). On approval, re-run with `--apply` (carry forward the same `--decisions` path if
one was used):

```bash
bash .claude/skills/dawn-backflow/backflow.sh --apply [--decisions /tmp/decisions.tsv]
```

On abort, stop — nothing was written; `staging` is exactly as it was before you ran the command.
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/dawn-backflow/SKILL.md
git commit -m "docs(ops): dawn-backflow SKILL — origin/staging drift + plan/approve gate"
```

---

## Task 8: Update `conventions.md`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/conventions.md` §2a (around line 38-45), §4 (around line 126-144)

- [ ] **Step 1: Update §2a**

After the existing §2a paragraph (lines 38-44, ending "...re-triggers on every editor save."), add:

```markdown

`dawn-backflow` fetches and folds `origin/staging`'s bot commits automatically on every run (see
`docs/superpowers/specs/2026-07-03-dawn-backflow-staging-drift-and-plan-gate-design.md`) — there is
no manual "pull staging first" step to remember. Config-class drift (settings, templates) folds
through the same leaf-level reconciler as `current`'s drift (§4); everything else (in practice,
locale files) folds through a plain 3-way text merge, guarded on conflict.
```

- [ ] **Step 2: Update §4**

At the end of §4's first paragraph (after "...never by a blind 'checkout current', which would
lose values authored on staging)."), add:

```markdown
Since 2026-07-03, the same reconcile also runs against `origin/staging` (the staging preview
theme's own bot-linked drift) before the `current` reconcile — see the drift design doc above.
`dawn-backflow` defaults to a **plan mode**: it computes and prints what it would fold, then
requires `--apply` to actually commit. A plan-only run never leaves `staging` changed.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/conventions.md
git commit -m "docs(ops): conventions — origin/staging auto-heal + backflow plan/apply split"
```

---

## Task 9: Update the runbook

**Files:**
- Modify: `docs/superpowers/runbook/dawn-dev-and-release.md:27`

- [ ] **Step 1: Update the skill table row**

Replace line 27:

```markdown
| `dawn-backflow` | Direction-aware 3-way config reconcile between `staging` and `current` — staging-ahead values kept, current-ahead values folded, collisions prompted | Before a promote, or when the admin UI has config you need in staging |
```

with:

```markdown
| `dawn-backflow` | Direction-aware 3-way config reconcile between `staging` and both `current` and `origin/staging` (the preview theme's own bot-linked drift) — staging-ahead values kept, other-ahead values folded, collisions prompted. Prints a plan report and requires `--apply` to commit. | Before a promote, or when the admin UI (published theme or preview theme) has config you need in staging |
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/runbook/dawn-dev-and-release.md
git commit -m "docs(ops): runbook — backflow now covers origin/staging drift + plan/apply"
```

---

## Task 10: Use the new backflow to fix today's stuck divergence

**Files:** none (operational task against the real repo)

This is the motivating incident (see the design doc's Context note and §9): local `staging`
(`2f505c2d`) is missing `origin/staging`'s (`7edb385f`) padding/`mailto:`-link edits to
`templates/page.withdrawal.json` and its locale-file formatting pass.

- [ ] **Step 1: Confirm you're on `ops` with a clean tree**

Run: `git status --short --branch`
Expected: `## ops...origin/ops`, clean.

- [ ] **Step 2: Run the new backflow in plan mode**

Run: `bash .claude/skills/dawn-backflow/backflow.sh`
Expected: exit `22`, with a report naming `templates/page.withdrawal.json` and the locale files
under "Pulling in from the live preview theme". If it instead exits `21` (a genuine collision — one
of the previously-run manual backflow's values happens to disagree with `origin/staging`'s), resolve
via the printed instructions before continuing.

- [ ] **Step 3: Review the report, then apply**

Run: `bash .claude/skills/dawn-backflow/backflow.sh --apply`
Expected: exit `0`, "Backflow complete: staging config collapsed into one snapshot at the tip."

- [ ] **Step 4: Verify the divergence is resolved**

Run: `git fetch origin staging --quiet && git diff origin/staging staging -- templates/page.withdrawal.json locales/`
Expected: no output (or only content that predates `origin/staging`'s tip and is legitimately
staging-ahead) — confirm with the operator which, if any, remaining diff is intentional before
treating this as done.
