# Dawn config 3-way reconcile — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Dawn-ops' blind "current wins" config backflow with a direction-aware, key-level 3-way merge so config authored on `staging` survives backflow and promotes to `current`, prompting the operator only on true both-sides collisions.

**Architecture:** New pure-bash helpers in `_dawn-ops-lib/dawn-ops.sh` parse config JSON into canonical *leaf maps* (scalar-or-whole-array values keyed by JSON path) at three refs — `base` (`git merge-base staging <current>`), `staging`, and `current` — and classify each leaf as staging-ahead (keep), current-ahead (fold), agree (skip), or collision (prompt). `dawn-backflow` drives the loop and surfaces collisions via `AskUserQuestion`; `dawn-promote`'s guard becomes direction-aware. Value comparison makes it immune to Shopify re-serialization noise. Suffix templates are reconciled on their `settings` leaves only.

**Tech Stack:** bash, git, jq 1.7, perl (JSONC comment stripping). Reference spec: `docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md`.

---

## Conventions used throughout

- All new functions are namespaced `dawn::` in `.claude/skills/_dawn-ops-lib/dawn-ops.sh`.
- **Test seam:** new functions resolve "current" through `dawn::current_ref`, which honours the env override `DAWN_CURRENT_REF` (default: `refs/remotes/origin/current`, falling back to `origin/current`). Tests set `DAWN_CURRENT_REF=current` and use a local `current` branch — mirroring the `DAWN_PROMOTE_REF`/`DAWN_PUSH` seam already in `promote.sh`.
- **ABSENT sentinel:** `DAWN_ABSENT=$'\x01ABSENT'` — a byte that cannot appear in JSON, used to mark "key not present at this ref" in leaf comparisons.
- **Leaf map line format:** `<path-json>\t<value-json>`, one per line, e.g. `["footer","show_withdrawal_link"]\ttrue`. Path and value are both compact canonical JSON from `jq -c`.
- Reuse the existing `dawn::_strip_jsonc` for the Shopify `/* … */` header comment before any `jq` parse.
- Run all test scripts with `bash <path>`; each exits non-zero on first failure.
- **PORTABILITY — macOS ships bash 3.2 (verified: `/bin/bash` is 3.2.57).** Do **not** use bash
  associative arrays (`declare -A` / `local -A`) — they are bash 4+ only. All key→value grouping is
  done in `awk` (its associative arrays are always available) or `jq`. Indexed arrays
  (`local -a x=()`) are fine. Process substitution `< <(…)`, here-strings `<<<`, and `$'\t'` all
  work in 3.2 and are used freely.
- **PORTABILITY — BSD tools on macOS.** `sed` here is BSD sed: it does **not** interpret `\t` as a
  tab (it inserts a literal `t`). Use `awk` for any tab insertion/splitting (`awk '{print "X\t"$0}'`,
  `awk -F'\t'`), where `\t` *is* a tab on both BSD and GNU. Same caution for `grep -P` (not
  available) — use `grep -E`.

---

## File Structure

- **Create:** `.claude/skills/_dawn-ops-lib/tests/helpers.sh` — test harness (fixture repo builder + assertions).
- **Create:** `.claude/skills/_dawn-ops-lib/tests/run.sh` — runs every `test_*.sh` in the dir.
- **Create:** `.claude/skills/_dawn-ops-lib/tests/test_config_class.sh`, `test_config_leaves.sh`, `test_reconcile_scan.sh`, `test_reconcile_pending.sh`, `test_reconcile_apply.sh`, `test_backflow.sh`, `test_promote_guard.sh` — one per unit.
- **Modify:** `.claude/skills/_dawn-ops-lib/dawn-ops.sh` — new helpers; replace `dawn::backflow_pending`.
- **Modify:** `.claude/skills/dawn-backflow/backflow.sh` — reconcile loop + direction-aware non-config partition.
- **Modify:** `.claude/skills/dawn-backflow/SKILL.md` — collision `AskUserQuestion` flow + decisions file.
- **Modify:** `.claude/skills/dawn-promote/promote.sh` — guard on `dawn::reconcile_pending`.
- **Modify:** `.claude/skills/_dawn-ops-lib/conventions.md`, both runbooks, `dawn-harvest/SKILL.md` — documentation.

---

## Task 1: Test harness scaffold

**Files:**
- Create: `.claude/skills/_dawn-ops-lib/tests/helpers.sh`
- Create: `.claude/skills/_dawn-ops-lib/tests/run.sh`
- Create: `.claude/skills/_dawn-ops-lib/tests/test_smoke.sh`

- [ ] **Step 1: Write the harness**

Create `.claude/skills/_dawn-ops-lib/tests/helpers.sh`:

```bash
#!/usr/bin/env bash
# Test harness for dawn-ops. Plain bash, no bats dependency.
set -uo pipefail
DAWN_LIB_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dawn-ops.sh"

_dawn_fail(){ echo "  FAIL: $*" >&2; exit 1; }
assert_eq(){ [ "$1" = "$2" ] || _dawn_fail "expected [$2], got [$1] ${3:+($3)}"; }
assert_contains(){ grep -qF "$2" <<< "$1" || _dawn_fail "[$1] does not contain [$2] ${3:+($3)}"; }
assert_not_contains(){ grep -qF "$2" <<< "$1" && _dawn_fail "[$1] unexpectedly contains [$2] ${3:+($3)}" || true; }
assert_rc(){ [ "$1" = "$2" ] || _dawn_fail "expected rc $2, got $1 ${3:+($3)}"; }

# Create a throwaway git repo with base/staging/current branches. Prints its path.
# Usage: repo=$(dawn_test_repo); then use commit_on to build history.
dawn_test_repo(){
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" commit -q --allow-empty -m base
  git -C "$d" branch staging
  git -C "$d" branch current
  echo "$d"
}

# commit_on <repo> <branch> <path> <content-file-or-heredoc-via-stdin>
# Reads file content from stdin, writes it at <path> on <branch>, commits.
commit_on(){
  local d="$1" br="$2" path="$3" msg="${4:-edit}"
  git -C "$d" checkout -q "$br"
  mkdir -p "$d/$(dirname "$path")"
  cat > "$d/$path"
  git -C "$d" add -A
  git -C "$d" commit -q -m "$msg"
}

# Run a function inside the repo with the test seam pointing at the local 'current' branch.
# Usage: in_repo <repo> <function-and-args...>
in_repo(){
  local d="$1"; shift
  ( cd "$d" && DAWN_CURRENT_REF=current bash -c "source '$DAWN_LIB_SRC'; $*" )
}
```

- [ ] **Step 2: Write the runner**

Create `.claude/skills/_dawn-ops-lib/tests/run.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
fail=0
for t in test_*.sh; do
  [ "$t" = "test_smoke.sh" ] && :  # smoke included
  echo "== $t =="
  if bash "$t"; then echo "  ok"; else echo "  FAILED"; fail=1; fi
done
exit $fail
```

- [ ] **Step 3: Write a smoke test**

Create `.claude/skills/_dawn-ops-lib/tests/test_smoke.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"a":1}'
out=$(git -C "$d" show staging:config/settings_data.json)
assert_eq "$out" '{"a":1}' "smoke read"
echo "  smoke ok"
```

- [ ] **Step 4: Run it**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: `test_smoke.sh` prints `smoke ok` then `ok`; overall exit 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/tests/
git commit -m "test(ops): add plain-bash test harness for dawn-ops"
```

---

## Task 2: `dawn::current_ref` + `DAWN_ABSENT` plumbing

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh` (after line 7, the `DAWN_LIB_DIR` block)
- Test: `.claude/skills/_dawn-ops-lib/tests/test_config_class.sh` (reused later; start it here)

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/_dawn-ops-lib/tests/test_config_class.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
d=$(dawn_test_repo)

# current_ref honours the seam
out=$(in_repo "$d" 'dawn::current_ref')
assert_eq "$out" "current" "current_ref uses DAWN_CURRENT_REF"

echo "  config_class/current_ref ok"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_config_class.sh`
Expected: FAIL — `dawn::current_ref: command not found` (non-zero exit).

- [ ] **Step 3: Implement**

In `dawn-ops.sh`, immediately after line 7 (`DAWN_LIB_DIR=…`) insert:

```bash
# Sentinel for "leaf absent at this ref" — a byte JSON can never contain.
DAWN_ABSENT=$'\x01ABSENT'

# Resolve the ref that represents the live theme. Test seam: DAWN_CURRENT_REF.
dawn::current_ref(){
  if [ -n "${DAWN_CURRENT_REF:-}" ]; then echo "$DAWN_CURRENT_REF"; return 0; fi
  if git rev-parse --verify -q refs/remotes/origin/current >/dev/null; then
    echo refs/remotes/origin/current
  else
    echo origin/current
  fi
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_config_class.sh`
Expected: `config_class/current_ref ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_config_class.sh
git commit -m "feat(ops): dawn::current_ref seam + DAWN_ABSENT sentinel"
```

---

## Task 3: `dawn::config_class`

Classifies a path as `full` (in config-paths.txt → all leaves), `suffix` (custom suffix template → settings leaves only), or empty (not a reconcile target).

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh`
- Test: `.claude/skills/_dawn-ops-lib/tests/test_config_class.sh`

- [ ] **Step 1: Extend the failing test**

Append to `test_config_class.sh` (before the final echo):

```bash
assert_eq "$(in_repo "$d" 'dawn::config_class config/settings_data.json')" "full"   "settings_data => full"
assert_eq "$(in_repo "$d" 'dawn::config_class sections/footer-group.json')" "full"  "footer-group => full"
assert_eq "$(in_repo "$d" 'dawn::config_class templates/product.json')" "full"      "default template => full"
assert_eq "$(in_repo "$d" 'dawn::config_class templates/page.withdrawal.json')" "suffix" "suffix => suffix"
assert_eq "$(in_repo "$d" 'dawn::config_class templates/product.soap.json')" "suffix" "suffix product => suffix"
assert_eq "$(in_repo "$d" 'dawn::config_class sections/footer.liquid')" ""           "non-config => empty"
assert_eq "$(in_repo "$d" 'dawn::config_class snippets/foo.liquid')" ""              "snippet => empty"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_config_class.sh`
Expected: FAIL — `dawn::config_class: command not found`.

- [ ] **Step 3: Implement**

Add to `dawn-ops.sh` (near `dawn::config_files`, after line 31):

```bash
# Classify a repo path for reconcile:
#   "full"   -> listed in config-paths.txt (all leaves are config)
#   "suffix" -> custom suffix template templates/<type>.<suffix>.json (settings leaves only)
#   ""       -> not a reconcile target
dawn::config_class(){
  local p="$1"
  if grep -qxF "$p" "$DAWN_LIB_DIR/config-paths.txt"; then echo full; return 0; fi
  # suffix template: templates/<type>.<suffix>.json, but NOT a default templates/<type>.json
  if echo "$p" | grep -qE '^templates/[a-z_]+\.[a-z0-9_-]+\.json$'; then echo suffix; return 0; fi
  echo ""
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_config_class.sh`
Expected: `config_class/current_ref ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_config_class.sh
git commit -m "feat(ops): dawn::config_class (full/suffix/none)"
```

---

## Task 4: `dawn::config_leaves`

Emit the canonical leaf map for one file at one ref. Leaf = scalar OR whole array; objects recursed. For `suffix` class, keep only leaves whose path passes through a `settings` key.

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh`
- Test: `.claude/skills/_dawn-ops-lib/tests/test_config_leaves.sh`

- [ ] **Step 1: Write the failing test**

Create `test_config_leaves.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
d=$(dawn_test_repo)

# A section-group-like file with a nested settings object and an array.
commit_on "$d" staging sections/footer-group.json <<'JSON'
{
  "sections": {
    "footer": {
      "type": "footer",
      "settings": { "show_withdrawal_link": true, "margin_top": 48 },
      "block_order": ["a","b"]
    }
  }
}
JSON

leaves=$(in_repo "$d" 'dawn::config_leaves staging sections/footer-group.json')
# scalar leaf, path + value
assert_contains "$leaves" '["sections","footer","settings","show_withdrawal_link"]	true'
assert_contains "$leaves" '["sections","footer","settings","margin_top"]	48'
assert_contains "$leaves" '["sections","footer","type"]	"footer"'
# array is atomic (one leaf, whole array)
assert_contains "$leaves" '["sections","footer","block_order"]	["a","b"]'

# Missing file => no output
empty=$(in_repo "$d" 'dawn::config_leaves staging sections/does-not-exist.json')
assert_eq "$empty" "" "absent file => empty"

# Suffix class keeps only settings leaves
commit_on "$d" staging templates/page.withdrawal.json <<'JSON'
{
  "sections": {
    "wf": { "type": "withdrawal-form", "settings": { "heading": "Herroeping" } }
  },
  "order": ["wf"]
}
JSON
sfx=$(in_repo "$d" 'dawn::config_leaves staging templates/page.withdrawal.json')
assert_contains "$sfx" '["sections","wf","settings","heading"]	"Herroeping"'
assert_not_contains "$sfx" '"type"'   # skeleton excluded
assert_not_contains "$sfx" '"order"'  # skeleton excluded

echo "  config_leaves ok"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_config_leaves.sh`
Expected: FAIL — `dawn::config_leaves: command not found`.

- [ ] **Step 3: Implement**

Add to `dawn-ops.sh` (after `dawn::config_class`):

```bash
# Emit canonical leaf map for one config file at one ref.
# One line per leaf:  <path-json>\t<value-json>. Leaf = scalar or whole array.
# For class "suffix", restrict to leaves whose path passes through a `settings` key.
dawn::config_leaves(){
  local ref="$1" file="$2" class
  class="$(dawn::config_class "$file")"
  local raw; raw="$(git show "$ref:$file" 2>/dev/null | dawn::_strip_jsonc)" || return 0
  [ -z "$raw" ] && return 0
  local sel='.'
  [ "$class" = suffix ] && sel='select(.p | index("settings"))'
  printf '%s' "$raw" | jq -rc "
    def leaves(\$p):
      if type==\"object\" then (to_entries[] as \$e | (\$e.value | leaves(\$p + [\$e.key])))
      else {p:\$p, v:.} end;
    leaves([]) | $sel | (.p|tojson) + \"\t\" + (.v|tojson)
  " 2>/dev/null
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_config_leaves.sh`
Expected: `config_leaves ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_config_leaves.sh
git commit -m "feat(ops): dawn::config_leaves — canonical JSON leaf map (settings-scoped for suffix)"
```

---

## Task 5: `dawn::config_targets`

List the files to reconcile: all `config-paths.txt` files, plus suffix templates that differ across any pair of {base, staging, current}.

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh`
- Test: `.claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh` (start it here)

- [ ] **Step 1: Write the failing test**

Create `test_reconcile_scan.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
d=$(dawn_test_repo)

# config-paths.txt files must be listed even if unchanged; provide one on all branches.
commit_on "$d" staging config/settings_data.json <<< '{"a":1}'
git -C "$d" checkout -q current
git -C "$d" merge -q staging -m merge   # give current the same file too

# A differing suffix template only on staging
commit_on "$d" staging templates/page.withdrawal.json <<< '{"sections":{"wf":{"settings":{"heading":"x"}}}}'

targets=$(in_repo "$d" 'dawn::config_targets')
assert_contains "$targets" "config/settings_data.json" "full-config listed"
assert_contains "$targets" "templates/page.withdrawal.json" "differing suffix listed"
assert_not_contains "$targets" "templates/product.json" "absent default not listed"

echo "  config_targets ok"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh`
Expected: FAIL — `dawn::config_targets: command not found`.

- [ ] **Step 3: Implement**

Add to `dawn-ops.sh`:

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
      | grep -vxFf "$DAWN_LIB_DIR/config-paths.txt" || true
    fi
  } | sort -u
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh`
Expected: `config_targets ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh
git commit -m "feat(ops): dawn::config_targets — full config + differing suffix templates"
```

---

## Task 6: `dawn::reconcile_scan` — the 3-way classifier

Emit one line per non-agreeing leaf: `<verdict>\t<file>\t<path-json>\t<base>\t<staging>\t<current>`, where verdict ∈ `current_ahead | staging_ahead | collision`. ABSENT values render as the sentinel.

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh`
- Test: `.claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh` (extend)

- [ ] **Step 1: Extend the failing test**

Append to `test_reconcile_scan.sh` (before the final echo). Build a fresh repo with the four cases:

```bash
d2=$(dawn_test_repo)
# base
commit_on "$d2" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"base","fold_current":"base","collide":"base","agree":"base"}}}}
JSON
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
# staging edits: keep_staging + collide + agree
commit_on "$d2" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"S","fold_current":"base","collide":"S","agree":"same"}}}}
JSON
# current edits: fold_current + collide + agree
commit_on "$d2" current sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"base","fold_current":"C","collide":"C","agree":"same"}}}}
JSON

scan=$(in_repo "$d2" 'dawn::reconcile_scan')
assert_contains "$scan" 'staging_ahead	sections/footer-group.json	["sections","f","settings","keep_staging"]'
assert_contains "$scan" 'current_ahead	sections/footer-group.json	["sections","f","settings","fold_current"]'
assert_contains "$scan" 'collision	sections/footer-group.json	["sections","f","settings","collide"]'
assert_not_contains "$scan" '"agree"'   # both changed to same value => no line
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh`
Expected: FAIL — `dawn::reconcile_scan: command not found`.

- [ ] **Step 3: Implement**

Add to `dawn-ops.sh`:

```bash
# 3-way classify every leaf of every reconcile target.
# Emits (only for non-agreeing leaves), tab-separated:
#   <verdict>\t<file>\t<path-json>\t<base>\t<staging>\t<current>
# verdict ∈ current_ahead | staging_ahead | collision.  Absent => $DAWN_ABSENT.
# NOTE: key→value grouping is done in awk (bash 3.2 has no associative arrays).
# Safe because leaf lines are canonical jq -c: values never contain a raw TAB
# (jq escapes control chars), so -F'\t' splits cleanly into side/path/value.
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

Note: `awk`'s `$3` captures the value; if a value ever contained a literal `\t` sequence it is the
two characters backslash-t (jq's escaping), never a field-splitting TAB, so this is safe.

- [ ] **Step 4: Run to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh`
Expected: `config_targets ok` and no assertion failure, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh
git commit -m "feat(ops): dawn::reconcile_scan — 3-way leaf classifier"
```

---

## Task 7: `dawn::reconcile_pending` (replaces `dawn::backflow_pending`)

Pending iff any `current_ahead` or `collision` leaf exists. Staging-ahead-only is NOT pending.

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh` (add new fn; keep `dawn::backflow_pending` as a thin alias so nothing breaks mid-migration)
- Test: `.claude/skills/_dawn-ops-lib/tests/test_reconcile_pending.sh`

- [ ] **Step 1: Write the failing test**

Create `test_reconcile_pending.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Case: staging-ahead only => NOT pending (rc 1)
d=$(dawn_test_repo)
commit_on "$d" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"base_key":"base"}}}}'
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
commit_on "$d" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"base_key":"base","new_key":true}}}}'
in_repo "$d" 'dawn::reconcile_pending'; rc=$?
assert_rc "$rc" 1 "staging-ahead only => not pending"

# Case: current-ahead => pending (rc 0)
d2=$(dawn_test_repo)
commit_on "$d2" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base"}}}}'
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
commit_on "$d2" current sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"live-edit"}}}}'
in_repo "$d2" 'dawn::reconcile_pending'; rc=$?
assert_rc "$rc" 0 "current-ahead => pending"

echo "  reconcile_pending ok"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_pending.sh`
Expected: FAIL — `dawn::reconcile_pending: command not found`.

- [ ] **Step 3: Implement**

Add to `dawn-ops.sh`:

```bash
# rc 0 (pending) if any current-ahead or collision leaf exists; else rc 1.
dawn::reconcile_pending(){
  local scan; scan="$(dawn::reconcile_scan)" || return $DAWN_GUARD
  grep -qE '^(current_ahead|collision)'$'\t' <<< "$scan"
}
```

Then replace the body of the existing `dawn::backflow_pending` (lines 33-37) with a thin alias:

```bash
# Deprecated name — kept so callers migrate incrementally. Prefer dawn::reconcile_pending.
dawn::backflow_pending(){ dawn::reconcile_pending; }
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_pending.sh`
Expected: `reconcile_pending ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_reconcile_pending.sh
git commit -m "feat(ops): dawn::reconcile_pending (direction-aware); alias backflow_pending"
```

---

## Task 8: `dawn::reconcile_apply` — materialise the merge

Print the merged content for one file to stdout: substrate = current's document (preserving order + JSONC header), then overlay staging-ahead leaves, resolved-to-staging/entered collisions. Current-ahead and resolved-to-current need no overlay (already in the substrate).

Decisions are passed via a file: lines `<file>\t<path-json>\t<resolution>` where resolution ∈ `staging | current | value:<json>`. If a collision for the file has no decision, return `$DAWN_STOP_JUDGMENT` and list it.

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh`
- Test: `.claude/skills/_dawn-ops-lib/tests/test_reconcile_apply.sh`

- [ ] **Step 1: Write the failing test**

Create `test_reconcile_apply.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
d=$(dawn_test_repo)
commit_on "$d" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep":"base","fold":"base","collide":"base"}}}}
JSON
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
commit_on "$d" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep":"S","fold":"base","collide":"S"}}}}
JSON
commit_on "$d" current sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep":"base","fold":"C","collide":"C"}}}}
JSON

# Without a decision for the collision => STOP_JUDGMENT (rc 21)
out=$(in_repo "$d" 'dawn::reconcile_apply sections/footer-group.json /dev/null'); rc=$?
assert_rc "$rc" 21 "unresolved collision stops"

# With a decision (keep staging for collide) => merged JSON
dec="$d/decisions.tsv"
printf 'sections/footer-group.json\t["sections","f","settings","collide"]\tstaging\n' > "$dec"
merged=$(in_repo "$d" "dawn::reconcile_apply sections/footer-group.json '$dec'"); rc=$?
assert_rc "$rc" 0 "resolved collision applies"
# keep: staging-ahead kept; fold: current folded; collide: staging chosen
assert_eq "$(jq -r '.sections.f.settings.keep' <<< "$merged")" "S"    "staging-ahead kept"
assert_eq "$(jq -r '.sections.f.settings.fold' <<< "$merged")" "C"    "current-ahead folded"
assert_eq "$(jq -r '.sections.f.settings.collide' <<< "$merged")" "S" "collision -> staging"

# value:<json> resolution
printf 'sections/footer-group.json\t["sections","f","settings","collide"]\tvalue:"X"\n' > "$dec"
merged=$(in_repo "$d" "dawn::reconcile_apply sections/footer-group.json '$dec'")
assert_eq "$(jq -r '.sections.f.settings.collide' <<< "$merged")" "X" "collision -> entered value"

echo "  reconcile_apply ok"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_apply.sh`
Expected: FAIL — `dawn::reconcile_apply: command not found`.

- [ ] **Step 3: Implement**

Add to `dawn-ops.sh`:

```bash
# Print the merged content for ONE file to stdout.
# Args: <file> <decisions-file>. Decisions lines: <file>\t<path-json>\t<staging|current|value:JSON>
# Returns $DAWN_STOP_JUDGMENT (and lists paths) if a collision has no decision.
dawn::reconcile_apply(){
  local file="$1" decisions="$2"
  local cur base; cur="$(dawn::current_ref)"; base="$(git merge-base staging "$cur" 2>/dev/null)"
  local class; class="$(dawn::config_class "$file")"

  # Substrate = current's document (order-preserving). Capture JSONC header to re-prepend.
  local raw header body
  raw="$(git show "$cur:$file" 2>/dev/null)"
  if [ -z "$raw" ]; then
    # No live version: suffix templates have nothing to protect — skip (caller leaves staging's).
    [ "$class" = suffix ] && return 0
    raw="$(git show "staging:$file" 2>/dev/null)"   # full-config safety net
  fi
  header="$(printf '%s' "$raw" | perl -0ne 'print $1 if m{\A(\s*/\*.*?\*/\s*)}s')"
  body="$(printf '%s' "$raw" | dawn::_strip_jsonc)"

  # Build the ops array: staging-ahead + resolved collisions.
  local ops='[]' verdict f p b s c line res
  local -a unresolved=()
  while IFS=$'\t' read -r verdict f p b s c; do
    [ "$f" = "$file" ] || continue
    case "$verdict" in
      current_ahead) : ;;                            # already in substrate
      staging_ahead)
        if [ "$s" = "$DAWN_ABSENT" ]; then
          ops="$(jq -c --argjson p "$p" '. + [{p:$p,del:true}]' <<< "$ops")"
        else
          ops="$(jq -c --argjson p "$p" --argjson v "$s" '. + [{p:$p,v:$v}]' <<< "$ops")"
        fi ;;
      collision)
        res="$(awk -F'\t' -v f="$file" -v pp="$p" '$1==f && $2==pp {print $3}' "$decisions" 2>/dev/null | head -1)"
        case "$res" in
          current) : ;;
          staging)
            if [ "$s" = "$DAWN_ABSENT" ]; then
              ops="$(jq -c --argjson p "$p" '. + [{p:$p,del:true}]' <<< "$ops")"
            else
              ops="$(jq -c --argjson p "$p" --argjson v "$s" '. + [{p:$p,v:$v}]' <<< "$ops")"
            fi ;;
          value:*)
            ops="$(jq -c --argjson p "$p" --argjson v "${res#value:}" '. + [{p:$p,v:$v}]' <<< "$ops")" ;;
          *) unresolved+=("$p") ;;
        esac ;;
    esac
  done < <(dawn::reconcile_scan)

  if [ "${#unresolved[@]}" -gt 0 ]; then
    echo "STOP: unresolved collisions in $file:" >&2
    printf '  %s\n' "${unresolved[@]}" >&2
    return $DAWN_STOP_JUDGMENT
  fi

  printf '%s' "$header"
  printf '%s' "$body" | jq --argjson ops "$ops" '
    reduce $ops[] as $o (.; if ($o.del // false) then delpaths([$o.p]) else setpath($o.p; $o.v) end)'
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_apply.sh`
Expected: `reconcile_apply ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_reconcile_apply.sh
git commit -m "feat(ops): dawn::reconcile_apply — materialise 3-way merge per file"
```

---

## Task 9: Rewrite `dawn-backflow/backflow.sh`

New flow: (1) direction-aware non-config partition — only **current-ahead** non-config files stop for classification; (2) if any collision has no decision, print all collisions and exit 21; (3) otherwise apply the reconcile to every target, amend the config snapshot, exit 0.

**Files:**
- Modify: `.claude/skills/dawn-backflow/backflow.sh` (full rewrite)
- Test: `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh`

- [ ] **Step 1: Write the failing test**

Create `test_backflow.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"

# staging-ahead only => nothing to fold, snapshot unchanged, exit 0
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"k":"base"}'
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
commit_on "$d" staging config/settings_data.json <<< '{"k":"base","new":true}' "config snapshot"
git -C "$d" checkout -q staging
( cd "$d" && DAWN_CURRENT_REF=current bash "$BF" ); rc=$?
assert_rc "$rc" 0 "staging-ahead backflow ok"
assert_eq "$(git -C "$d" show staging:config/settings_data.json | jq -r .new)" "true" "staging value preserved"

# current-ahead => folded into staging snapshot
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
commit_on "$d2" current config/settings_data.json <<< '{"k":"live"}'
git -C "$d2" checkout -q staging
( cd "$d2" && DAWN_CURRENT_REF=current bash "$BF" ); rc=$?
assert_rc "$rc" 0 "current-ahead backflow ok"
assert_eq "$(git -C "$d2" show staging:config/settings_data.json | jq -r .k)" "live" "current folded"

echo "  backflow ok"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_backflow.sh`
Expected: FAIL — behaviour mismatch (old backflow uses `checkout current` and the `origin/current` guard; assertions fail).

- [ ] **Step 3: Implement — rewrite `backflow.sh`**

Replace the entire contents of `.claude/skills/dawn-backflow/backflow.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

# Optional decisions file for collisions: --decisions <path>
DECISIONS=/dev/null
[ "${1:-}" = "--decisions" ] && { DECISIONS="${2:?}"; shift 2; }

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD
cur="$(dawn::current_ref)"
git fetch origin current --quiet 2>/dev/null || true
base="$(git merge-base staging "$cur" 2>/dev/null)" \
  || { echo "GUARD: no merge-base staging vs $cur" >&2; exit $DAWN_GUARD; }

# 1) Direction-aware non-config partition: only current-ahead non-config files need capture.
noncfg=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -n "$(dawn::config_class "$f")" ] && continue     # config target — handled by reconcile
  # current-ahead = changed on current relative to base
  git diff --quiet "$base" "$cur" -- "$f" && continue # not current-ahead (staging-only or same)
  noncfg+=("$f")
done < <(git diff --name-only staging "$cur" -- . ':(exclude)docs/' ':(exclude).claude/')

if [ "${#noncfg[@]}" -gt 0 ]; then
  echo "STOP: current-ahead non-config changes need classification (enrichment vs generic-L1 vs ignore):" >&2
  printf '  %s\n' "${noncfg[@]}" >&2
  echo "Decide per file: enrichment -> own L2 commit; generic -> dawn-harvest; churn -> ignore." >&2
  exit $DAWN_STOP_JUDGMENT
fi

# 2) Collisions without decisions -> stop and list.
scan="$(dawn::reconcile_scan)" || exit $DAWN_GUARD
collisions="$(grep $'\t' <<< "$scan" | grep -E '^collision'$'\t' || true)"
if [ -n "$collisions" ]; then
  missing=""
  while IFS=$'\t' read -r verdict f p b s c; do
    res="$(awk -F'\t' -v ff="$f" -v pp="$p" '$1==ff && $2==pp {print $3}' "$DECISIONS" 2>/dev/null | head -1)"
    [ -z "$res" ] && missing+="$f	$p	base=$b	staging=$s	current=$c"$'\n'
  done <<< "$collisions"
  if [ -n "$missing" ]; then
    echo "STOP: config collisions need decisions (keep staging / take current / enter value):" >&2
    printf '%s' "$missing" >&2
    exit $DAWN_STOP_JUDGMENT
  fi
fi

# 3) Apply reconcile to every target on staging, then amend the config snapshot.
dawn::with_branch staging || exit $DAWN_GUARD
changed=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  merged="$(dawn::reconcile_apply "$f" "$DECISIONS")" || exit $?
  [ -z "$merged" ] && continue
  if [ ! -f "$f" ] || [ "$(cat "$f")" != "$merged" ]; then
    mkdir -p "$(dirname "$f")"; printf '%s\n' "$merged" > "$f"; changed=1
  fi
done < <(dawn::config_targets)

if [ "$changed" = "0" ]; then
  echo "Nothing to backflow (no current-ahead config; staging-ahead values already present)."
  exit $DAWN_OK
fi

git add -A
last_msg="$(git log -1 --format=%s)"
case "$last_msg" in
  *config*|*snapshot*|*settings*) git commit -q --amend --no-edit ;;
  *) git commit -q -m "L2: store config snapshot (reconciled)" ;;
esac
echo "Backflow complete (config reconciled into the snapshot)."
exit $DAWN_OK
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_backflow.sh`
Expected: `backflow ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/dawn-backflow/backflow.sh .claude/skills/_dawn-ops-lib/tests/test_backflow.sh
git commit -m "feat(ops): backflow reconciles config 3-way; direction-aware non-config partition"
```

---

## Task 10: Point `dawn-promote` at the new guard

**Files:**
- Modify: `.claude/skills/dawn-promote/promote.sh:8`
- Test: `.claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh`

- [ ] **Step 1: Write the failing test**

Create `test_promote_guard.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
PROMOTE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-promote" && pwd)/promote.sh"

# staging-ahead only: guard must NOT block (should reach the STOP_LIVE confirm gate, rc 20).
d=$(dawn_test_repo)
commit_on "$d" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base"}}}}' "config snapshot"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
commit_on "$d" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base","new":true}}}}' "config snapshot"
git -C "$d" checkout -q staging
out=$( cd "$d" && DAWN_CURRENT_REF=current DAWN_PROMOTE_REF=refs/heads/current \
       DAWN_PUSH="git update-ref" bash "$PROMOTE" 2>&1 ); rc=$?
assert_rc "$rc" 20 "staging-ahead reaches confirm-live gate, not the backflow guard"
assert_not_contains "$out" "backflow first" "no false backflow guard"

echo "  promote_guard ok"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh`
Expected: FAIL — old `dawn::backflow_pending` sees any diff and blocks with "backflow first" (rc 10), not rc 20.

Note: after Task 7 aliased `backflow_pending` to `reconcile_pending`, this may already pass. If so, still make the edit in Step 3 for clarity and run again.

- [ ] **Step 3: Implement**

In `.claude/skills/dawn-promote/promote.sh`, line 8, change:

```bash
dawn::backflow_pending && { echo "GUARD: backflow first — origin/current has unsynced edits" >&2; exit $DAWN_GUARD; }
```

to:

```bash
dawn::reconcile_pending && { echo "GUARD: backflow first — origin/current has current-ahead edits or unresolved collisions" >&2; exit $DAWN_GUARD; }
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh`
Expected: `promote_guard ok`, exit 0.

- [ ] **Step 5: Run the whole suite + commit**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: every `test_*.sh` prints `ok`; overall exit 0.

```bash
git add .claude/skills/dawn-promote/promote.sh .claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh
git commit -m "feat(ops): promote guards on reconcile_pending (direction-aware)"
```

---

## Task 11: Update `dawn-backflow/SKILL.md` (collision flow)

**Files:**
- Modify: `.claude/skills/dawn-backflow/SKILL.md`

- [ ] **Step 1: Rewrite the Running + Exit-code sections**

Replace the `## Running` section and the Exit-0 / Exit-21 descriptions with content documenting the reconcile:

```markdown
## Running

```bash
bash .claude/skills/dawn-backflow/backflow.sh
```

Backflow now performs a **direction-aware 3-way reconcile** of the config files (see
`docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md`):

- **staging-ahead** settings (you changed them in staging's preview theme) are **kept** and will
  promote to `current`.
- **current-ahead** settings (edited in the live theme editor) are **folded** into staging's
  snapshot.
- **collisions** (both sides changed the same setting differently) stop for your decision.

### Exit 0 — reconciled (or nothing to do)

The config snapshot at the tip of `staging` was amended with the merged result (or left unchanged
if only staging-ahead values existed). Confirm with the user which settings were folded.

### Exit 21 — decisions or classification needed

Two possible causes:

1. **Config collisions.** The script prints each colliding `file → path` with its base / staging /
   current values. For each, ask the operator via `AskUserQuestion`:

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

2. **Current-ahead non-config files.** Classify each per the table below (enrichment → own L2
   commit; generic → `dawn-harvest`; churn → ignore), then re-run.
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/dawn-backflow/SKILL.md
git commit -m "docs(ops): backflow SKILL — reconcile + collision decisions flow"
```

---

## Task 12: Update `conventions.md`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/conventions.md` (§4 and the backflow-routing table)

- [ ] **Step 1: Replace the "regenerable = current" framing (lines ~71-75)**

Change:

```markdown
**`staging` always ends in exactly ONE config-snapshot commit at the tip.** That commit is
*regenerable* — its content is always "whatever `current`'s config files are right now." You can
drop and recreate it freely; the real source of truth is `current`.
```

to:

```markdown
**`staging` always ends in exactly ONE config-snapshot commit at the tip.** That commit is
*regenerable* — its content is the deterministic output of the **3-way config reconcile** of
`{base = git merge-base staging origin/current, staging, current}` (see
`docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md`). You can drop and recreate
it freely **by re-running the reconcile** (never by a blind "checkout current", which would lose
values authored on staging). `current` is the source of truth for values edited live; `staging` is
the source of truth for values you deliberately changed there.
```

- [ ] **Step 2: Replace the backflow-routing table (lines ~93-100)**

Change the table to:

```markdown
| Change type | Action |
|---|---|
| Config/settings divergence (either direction) | **Reconcile:** `dawn-backflow` runs the 3-way merge — staging-ahead kept, current-ahead folded, collisions prompted; amends the snapshot |
| New L2 enrichment (store-specific) | **Case B:** `reset --hard HEAD~1` (drop the regenerable snapshot), commit the enrichment, **recreate the snapshot by re-running the reconcile** |
| Generic code change (L1 candidate) | Route to `dawn-harvest`; rebase keeps the snapshot at the tip automatically |
| Locale / cosmetic churn | Ignore — Shopify re-serialization noise (the reconcile is value-based and ignores it automatically) |
```

- [ ] **Step 3: Add the verdict table to §5 (after the "three buckets" list)**

Insert:

```markdown
### Direction-aware config reconcile (verdict per setting)

For config-path files (all leaves) and suffix templates (`settings` leaves only), `dawn-backflow`
compares each setting at `base` / `staging` / `current`:

| base vs staging vs current | Meaning | Action |
|---|---|---|
| staging changed, current didn't | deliberate staging change | keep staging (promotes) |
| current changed, staging didn't | live editor change | fold into staging |
| both changed, same value | agree | no-op |
| both changed, different values | collision | prompt operator |

Suffix-template **skeleton** changes are excluded from the reconcile and continue to route to
`dawn-harvest` as L2 structure.
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/conventions.md
git commit -m "docs(ops): conventions — reconcile model, direction-aware snapshot"
```

---

## Task 13: Update both runbooks + harvest cross-ref

**Files:**
- Modify: `docs/superpowers/runbook/dawn-update-and-promote.md`
- Modify: `docs/superpowers/runbook/dawn-dev-and-release.md`
- Modify: `.claude/skills/dawn-harvest/SKILL.md`

- [ ] **Step 1: `dawn-update-and-promote.md`**

- Line ~38: replace *"regenerable — its content is always just 'whatever `current`'s config files are right now.'"* with: *"regenerable — its content is the output of the 3-way config reconcile of {base, staging, current}. Recreate it by re-running backflow, never by copying current verbatim (that would drop values authored on staging)."*
- Lines ~62-72 (Case B recreate): change the "recreate the config snapshot back at the tip" step from a `git checkout current -- <config>` style to: *"re-run `dawn-backflow` to recreate the snapshot via the reconcile."*
- Lines ~86 / ~119 (promote checklist + guard note): change *"no un-captured admin edits remain on `current`"* to *"no current-ahead config edits or unresolved collisions remain (the reconcile guard, `dawn::reconcile_pending`); staging-ahead values are expected and will promote."*

- [ ] **Step 2: `dawn-dev-and-release.md`**

Find the backflow/promote steps (grep `backflow`, `config snapshot`) and update any "current wins" / "whatever current" wording to reference the reconcile, matching the conventions §4 language from Task 12.

Run to locate: `grep -niE 'backflow|config snapshot|current wins|whatever current|regenerable' docs/superpowers/runbook/dawn-dev-and-release.md`

- [ ] **Step 3: `dawn-harvest/SKILL.md` cross-reference**

In the "Template JSON candidates" section (around line 75, the `Config (content only)` note), append a sentence:

```markdown
> Note: for **suffix templates**, these `settings` values are now actively reconciled by
> `dawn-backflow` (3-way merge), not merely left inert — see
> `docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md`. The skeleton still
> harvests as L2 here.
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/runbook/dawn-update-and-promote.md docs/superpowers/runbook/dawn-dev-and-release.md .claude/skills/dawn-harvest/SKILL.md
git commit -m "docs(ops): runbooks + harvest x-ref for config reconcile"
```

---

## Task 14: Documentation-consistency sweep

**Files:** none created; verification only.

- [ ] **Step 1: Grep the living-doc set for invalidated phrasing**

Run:

```bash
grep -rniE 'whatever .*current|current wins|checkout .*origin/current -- ' \
  .claude/skills/_dawn-ops-lib/conventions.md \
  .claude/skills/dawn-backflow/SKILL.md \
  docs/superpowers/runbook/
```

Expected: no matches in a canonical doc that describes *current behaviour*. (Historical dated
specs/plans under `docs/superpowers/{specs,plans,inventory}` are point-in-time and are NOT edited.)

- [ ] **Step 2: Confirm no lingering `backflow_pending` guard description**

Run: `grep -rniE 'backflow_pending' .claude/skills/ docs/superpowers/runbook/`
Expected: only the deprecated-alias definition in `dawn-ops.sh`; no doc still describes it as the promote guard.

- [ ] **Step 3: Full test suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all `ok`, exit 0.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A && git commit -m "docs(ops): consistency sweep for config reconcile" || echo "nothing to fix"
```

---

## Task 15: Field test — promote the withdrawal footer link

The real, in-flight case: `sections/footer-group.json` has three staging-ahead keys
(`show_withdrawal_link`, `withdrawal_page`, `policies_own_line`); `footer.liquid` and
`page.withdrawal.json` are also staging-ahead. This exercises the new flow end-to-end on live data.
**Live push happens only with explicit human approval** — never pass `--confirm-live` autonomously.

- [ ] **Step 1: Fetch + dry-run the scan on the real repo**

Run:

```bash
git fetch origin current --quiet
source .claude/skills/_dawn-ops-lib/dawn-ops.sh
dawn::reconcile_scan
```

Expected: the three footer keys appear as `staging_ahead`; **no** `current_ahead` or `collision`
lines (confirm with the operator).

- [ ] **Step 2: Confirm the guard now passes**

Run: `dawn::reconcile_pending; echo "pending rc=$?"`
Expected: `pending rc=1` (NOT pending — staging-ahead only).

- [ ] **Step 3: Run backflow**

Run: `bash .claude/skills/dawn-backflow/backflow.sh`
Expected: Exit 0 with "Nothing to backflow" **or** a clean reconcile. If it stops on a current-ahead
non-config file (e.g. `footer.liquid` should be staging-ahead and must NOT stop it), investigate
before proceeding.

- [ ] **Step 4: Promote — STOP at the confirm gate**

Run: `bash .claude/skills/dawn-promote/promote.sh`
Expected: Exit 20 — prints the diff stat of what will change on `current`. **Show it to the operator
and get explicit approval.** Do not proceed automatically.

- [ ] **Step 5: Promote for real (only after approval)**

Run: `bash .claude/skills/dawn-promote/promote.sh --confirm-live`
Expected: Exit 0; `current` now carries the withdrawal footer link. Verify on the live storefront
that the footer link renders, and record the `config-archive/<timestamp>` rollback tag.

- [ ] **Step 6: Commit any repo-side artifacts**

No code commit expected here (this task is operational). Note the outcome in the session summary.

---

## Self-Review notes (author)

- **Spec coverage:** §2 model → Tasks 4/6; §2.3 noise-immunity → value-based `config_leaves` (Task 4) + test 4 in Task 6; §2.4 arrays atomic → Task 4 test; §3 collisions incl. free-text → Task 8 (`value:`); §4 durability/Case B → Task 12 §2; §5 guard → Tasks 7/10; §6 scope (full/suffix + direction-aware non-config) → Tasks 3/9; §7 algorithm → Tasks 4-8; §8 surface → Tasks 9-13; §9 edges (no merge-base, absent file, entered value parse) → Tasks 6/8; §10 tests → the test matrix across tasks; §11 exit codes → preserved. All covered.
- **Type consistency:** `dawn::current_ref`, `dawn::config_class`, `dawn::config_leaves`, `dawn::config_targets`, `dawn::reconcile_scan`, `dawn::reconcile_pending`, `dawn::reconcile_apply` used with identical signatures throughout. Decisions-file format (`<file>\t<path-json>\t<staging|current|value:JSON>`) identical in Tasks 8, 9, 11.
- **No placeholders:** every code step shows full code; commands have expected output.
