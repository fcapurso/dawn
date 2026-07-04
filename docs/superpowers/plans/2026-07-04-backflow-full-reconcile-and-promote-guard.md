# Backflow Full Reconcile + Promote Stage-Push Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the direction-aware backflow reconcile with an explicit three-source comparison that asks the operator about every divergent key, and block `dawn-promote` unless staging was pushed to the preview theme and nothing has changed since.

**Architecture:** Two new library functions (`dawn::backflow_scan`, `dawn::backflow_apply`) replace backflow.sh's inner reconcile loop; a third (`dawn::assert_stage_push_current`) adds a promote guard. The existing `dawn::reconcile_scan` / `dawn::reconcile_apply` / `dawn::reconcile_pending` family is untouched — the guards still depend on them.

**Tech Stack:** bash, awk, jq — same as the rest of `dawn-ops.sh`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-04-backflow-full-reconcile-and-promote-guard-design.md`

---

## Safety protocol (required for every subagent working on this plan)

Real git mutations are limited to `git add` / `git commit` on the files listed in each task. All test fixtures must use the `dawn_test_repo` / `commit_on` / `in_repo` helpers from `.claude/skills/_dawn-ops-lib/tests/helpers.sh` (mktemp-d based). **No `git push` ever**, under any circumstances, without the human's direct confirmation in the conversation. Verify every subagent report by reading the actual diff and re-running the test suite yourself before moving to the next task.

---

## Background

### How the existing reconciler works (for contrast)

`dawn::reconcile_scan` compares staging vs ONE other ref using a three-way base (sync marker SHA → git merge-base fallback). It classifies every leaf key as `staging_ahead` (auto-keep), `current_ahead` (auto-fold), or `collision` (stop for decision). This direction inference silently folded live edits when staging happened to match the old base.

### What the new reconciler does

`dawn::backflow_scan` compares **staging vs origin/current vs origin/staging** with NO base, emitting a TSV row for every key where the three values do not all agree. The operator then explicitly decides the target value for each key; nothing folds automatically.

### What stays the same

- `dawn::reconcile_scan`, `dawn::reconcile_apply`, `dawn::reconcile_pending`, `dawn::assert_backflow_not_pending` — guard functions, unchanged.
- `dawn::nonconfig_drift_scan`, `dawn::nonconfig_drift_apply` — locale-file handling, unchanged.
- Sync-marker read/write — unchanged.
- Stage-push skill — unchanged.
- Test files for the old reconcile family — unchanged.

---

## File map

| File | Change |
|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | Add `dawn::backflow_scan`, `dawn::backflow_apply`, `dawn::assert_stage_push_current` |
| `.claude/skills/dawn-backflow/backflow.sh` | Rewrite inner reconcile loop to use new functions |
| `.claude/skills/dawn-promote/promote.sh` | Add `dawn::assert_stage_push_current` call before existing guard |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow_scan.sh` | New: unit tests for `dawn::backflow_scan` |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow_apply.sh` | New: unit tests for `dawn::backflow_apply` |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh` | Rewrite: update for new behaviour (decisions required everywhere) |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh` | Rewrite: update for new behaviour |
| `.claude/skills/_dawn-ops-lib/tests/test_promote_stage_push_guard.sh` | New: tests for `dawn::assert_stage_push_current` |
| `.claude/skills/dawn-backflow/SKILL.md` | Rewrite Exit 22 agent behaviour |
| `.claude/skills/dawn-promote/SKILL.md` | Add new Exit 10 cause |

---

## Important design note: staging-ahead keys now surface as questions

In the old design, a key that staging changed but neither remote had touched was `staging_ahead` — silently kept. In the new design, that key appears in `dawn::backflow_scan` with verdict `agree_cs` (both remotes agree on a value staging doesn't hold) and the operator must answer "keep staging." This is intentional: the operator wanted explicit control over every divergence. In the normal workflow (backflow → stage-push → promote), after promote all three sources agree and these questions disappear.

---

## Task 1: Add `dawn::backflow_scan` to dawn-ops.sh

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh` (after line ~213, after `dawn::reconcile_scan`)
- Create: `.claude/skills/_dawn-ops-lib/tests/test_backflow_scan.sh`

### What `dawn::backflow_scan` does

```
dawn::backflow_scan [<cur-ref> [<sr-ref>]]
```

Defaults: `dawn::current_ref` and `dawn::staging_remote_ref`.

For every config-class file that differs between staging and either remote (union of `dawn::config_targets "$cur"` and `dawn::config_targets "$sr"`), it reads all leaf keys from all three refs via `dawn::config_leaves` and emits one TSV row per key where the three values are not all identical:

```
<verdict>\t<file>\t<path-json>\t<staging-val>\t<cur-val>\t<sr-val>
```

Verdict:
- `agree_cs` — `cur==sr`, staging differs (staging intentionally changed; remotes agree on old value)
- `agree_sc` — `staging==cur`, sr differs (bot edit on preview theme)
- `agree_ss` — `staging==sr`, cur differs (live shop edit)
- `all_differ` — all three different

`DAWN_ABSENT` (`$DAWN_ABSENT`) is used for missing keys.

- [ ] **Step 1: Create the failing test file**

Create `.claude/skills/_dawn-ops-lib/tests/test_backflow_scan.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# 1) All agree → no rows
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"a":"v1","b":"v2"}' "base"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging
out=$(in_repo "$d" 'dawn::backflow_scan current staging_remote')
assert_eq "$out" "" "all agree → no output"

# 2) agree_cs: both remotes agree, staging differs
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"a":"base"}' "base"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
commit_on "$d2" staging config/settings_data.json <<< '{"a":"s-val"}' "staging changes"
git -C "$d2" checkout -q staging
out2=$(in_repo "$d2" 'dawn::backflow_scan current staging_remote')
assert_contains "$out2" "agree_cs" "agree_cs: staging differs, remotes agree"
assert_contains "$out2" '"s-val"' "staging value in output"
assert_contains "$out2" '"base"' "remote value in output"

# 3) agree_sc: staging==current, staging_remote differs (bot edit on preview)
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"a":"base"}' "base"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging_remote config/settings_data.json <<< '{"a":"preview-edit"}' "bot edit"
git -C "$d3" checkout -q staging
out3=$(in_repo "$d3" 'dawn::backflow_scan current staging_remote')
assert_contains "$out3" "agree_sc" "agree_sc: staging_remote differs"
assert_contains "$out3" '"preview-edit"' "sr value in output"

# 4) agree_ss: staging==staging_remote, current differs (live shop edit)
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"a":"base"}' "base"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
commit_on "$d4" current config/settings_data.json <<< '{"a":"live-edit"}' "live shop edit"
git -C "$d4" checkout -q staging
out4=$(in_repo "$d4" 'dawn::backflow_scan current staging_remote')
assert_contains "$out4" "agree_ss" "agree_ss: only current differs"
assert_contains "$out4" '"live-edit"' "current value in output"

# 5) all_differ: all three values different
d5=$(dawn_test_repo)
commit_on "$d5" staging config/settings_data.json <<< '{"a":"base"}' "base"
git -C "$d5" checkout -q current; git -C "$d5" merge -q staging -m sync
git -C "$d5" checkout -q staging_remote; git -C "$d5" merge -q staging -m sync
commit_on "$d5" staging config/settings_data.json <<< '{"a":"s-val"}' "staging"
commit_on "$d5" current config/settings_data.json <<< '{"a":"c-val"}' "current"
commit_on "$d5" staging_remote config/settings_data.json <<< '{"a":"r-val"}' "preview"
git -C "$d5" checkout -q staging
out5=$(in_repo "$d5" 'dawn::backflow_scan current staging_remote')
assert_contains "$out5" "all_differ" "all_differ: all three values different"
assert_contains "$out5" '"s-val"' "staging val"
assert_contains "$out5" '"c-val"' "current val"
assert_contains "$out5" '"r-val"' "sr val"

# 6) Key present only in staging (ABSENT on remotes) → appears in scan
d6=$(dawn_test_repo)
commit_on "$d6" staging config/settings_data.json <<< '{"a":"base"}' "base"
git -C "$d6" checkout -q current; git -C "$d6" merge -q staging -m sync
git -C "$d6" checkout -q staging_remote; git -C "$d6" merge -q staging -m sync
commit_on "$d6" staging config/settings_data.json <<< '{"a":"base","new_key":"staging-only"}' "add key"
git -C "$d6" checkout -q staging
out6=$(in_repo "$d6" 'dawn::backflow_scan current staging_remote')
assert_contains "$out6" '"new_key"' "staging-only key appears in scan"
assert_contains "$out6" "agree_cs" "staging-only key has agree_cs verdict"

echo "  backflow_scan ok"
```

- [ ] **Step 2: Run tests and verify the new test file fails**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh 2>&1 | tail -10
```

Expected: error loading `test_backflow_scan.sh` because `dawn::backflow_scan` is not defined yet.

- [ ] **Step 3: Add `dawn::backflow_scan` to dawn-ops.sh**

Add this block after `dawn::reconcile_scan` (after the closing `}` around line 213):

```bash
# 3-way value scan: compare staging vs <cur> vs <sr> for every config-class leaf.
# Unlike dawn::reconcile_scan, uses NO base reference — emits one row per key where
# the three values are not all identical, regardless of who changed what.
# Emits tab-separated: <verdict>\t<file>\t<path-json>\t<staging>\t<cur>\t<sr>
# Verdict: agree_cs (cur==sr, staging differs) | agree_sc (staging==cur, sr differs) |
#          agree_ss (staging==sr, cur differs) | all_differ (all three different).
# Absent keys use $DAWN_ABSENT. Files scanned = union of config_targets for both remotes.
dawn::backflow_scan(){
  local cur="${1:-$(dawn::current_ref)}"
  local sr="${2:-$(dawn::staging_remote_ref)}"
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    {
      dawn::config_leaves staging "$f" | awk '{print "S\t"$0}'
      dawn::config_leaves "$cur"     "$f" | awk '{print "C\t"$0}'
      dawn::config_leaves "$sr"      "$f" | awk '{print "R\t"$0}'
    } | awk -F'\t' -v file="$f" -v ABSENT="$DAWN_ABSENT" '
      { side=$1; path=$2; val=$3; seen[path]=1
        if(side=="S"){s[path]=val}
        else if(side=="C"){c[path]=val}
        else {r[path]=val} }
      END{
        for(p in seen){
          sv=(p in s)?s[p]:ABSENT
          cv=(p in c)?c[p]:ABSENT
          rv=(p in r)?r[p]:ABSENT
          if(sv==cv && sv==rv) continue
          if(cv==rv && sv!=cv)      v="agree_cs"
          else if(sv==cv && sv!=rv) v="agree_sc"
          else if(sv==rv && sv!=cv) v="agree_ss"
          else                      v="all_differ"
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", v, file, p, sv, cv, rv
        }
      }'
  done < <({ dawn::config_targets "$cur"; dawn::config_targets "$sr"; } | sort -u)
}
```

- [ ] **Step 4: Run the full test suite and confirm all tests pass**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh
```

Expected: all tests pass including `backflow_scan ok`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh \
        .claude/skills/_dawn-ops-lib/tests/test_backflow_scan.sh
git commit -m "feat(backflow): add dawn::backflow_scan — three-source value comparison, no direction inference"
```

---

## Task 2: Add `dawn::backflow_apply` to dawn-ops.sh

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh` (after `dawn::backflow_scan`)
- Create: `.claude/skills/_dawn-ops-lib/tests/test_backflow_apply.sh`

### What `dawn::backflow_apply` does

```
dawn::backflow_apply <file> <decisions-file> [<cur-ref> [<sr-ref>]]
```

Reads staging's current content of `<file>`, runs `dawn::backflow_scan` to find divergent keys, applies the operator's decision from the decisions TSV for each key, and emits the merged JSON to stdout (empty output = no change needed). Returns `$DAWN_STOP_JUDGMENT` (rc 21) if any divergent key has no decision.

Decisions TSV format: `<file>\t<path-json>\t<staging|current|staging_remote|value:JSON>`

| Verdict | Action |
|---|---|
| `staging` | keep staging's value — no-op |
| `current` | set to origin/current's value |
| `staging_remote` | set to origin/staging's value |
| `value:<json>` | set to the supplied JSON value |

- [ ] **Step 1: Create the failing test file**

Create `.claude/skills/_dawn-ops-lib/tests/test_backflow_apply.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Shared setup: four keys, each side changes a different one; "d" changes on all three.
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json \
  <<< '{"a":"base","b":"base","c":"base","d":"base"}' "base"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
commit_on "$d" staging config/settings_data.json \
  <<< '{"a":"s-val","b":"base","c":"base","d":"s-val"}' "staging changes a,d"
commit_on "$d" current config/settings_data.json \
  <<< '{"a":"base","b":"c-val","c":"base","d":"c-val"}' "current changes b,d"
commit_on "$d" staging_remote config/settings_data.json \
  <<< '{"a":"base","b":"base","c":"r-val","d":"r-val"}' "sr changes c,d"
git -C "$d" checkout -q staging
dec="$d/dec.tsv"

# 1) All 'staging' verdicts → no change → empty output
printf '%s\t%s\t%s\n' \
  'config/settings_data.json' '["a"]' 'staging' \
  'config/settings_data.json' '["b"]' 'staging' \
  'config/settings_data.json' '["c"]' 'staging' \
  'config/settings_data.json' '["d"]' 'staging' > "$dec"
m1=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote")
assert_eq "$m1" "" "all-staging decisions → empty output (no rewrite)"

# 2) 'current' verdict → takes origin/current's value
printf '%s\t%s\t%s\n' \
  'config/settings_data.json' '["a"]' 'staging' \
  'config/settings_data.json' '["b"]' 'current' \
  'config/settings_data.json' '["c"]' 'staging' \
  'config/settings_data.json' '["d"]' 'staging' > "$dec"
m2=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote")
assert_eq "$(jq -r '.b' <<< "$m2")" "c-val" "current verdict takes current value"
assert_eq "$(jq -r '.a' <<< "$m2")" "s-val" "a unchanged"

# 3) 'staging_remote' verdict → takes origin/staging's value
printf '%s\t%s\t%s\n' \
  'config/settings_data.json' '["a"]' 'staging' \
  'config/settings_data.json' '["b"]' 'staging' \
  'config/settings_data.json' '["c"]' 'staging_remote' \
  'config/settings_data.json' '["d"]' 'staging' > "$dec"
m3=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote")
assert_eq "$(jq -r '.c' <<< "$m3")" "r-val" "staging_remote verdict takes preview value"

# 4) 'value:JSON' verdict → sets custom value
printf '%s\t%s\t%s\n' \
  'config/settings_data.json' '["a"]' 'staging' \
  'config/settings_data.json' '["b"]' 'staging' \
  'config/settings_data.json' '["c"]' 'staging' \
  'config/settings_data.json' '["d"]' 'value:"custom"' > "$dec"
m4=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote")
assert_eq "$(jq -r '.d' <<< "$m4")" "custom" "value: verdict sets custom value"

# 5) Missing decision → STOP_JUDGMENT (rc 21)
printf '%s\t%s\t%s\n' 'config/settings_data.json' '["a"]' 'staging' > "$dec"
out5=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote" 2>&1); rc5=$?
assert_rc "$rc5" 21 "missing decisions → rc 21"
assert_contains "$out5" "unresolved" "error mentions unresolved"

echo "  backflow_apply ok"
```

- [ ] **Step 2: Run tests and verify the new test file fails**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh 2>&1 | tail -10
```

Expected: error loading `test_backflow_apply.sh` because `dawn::backflow_apply` is not defined yet.

- [ ] **Step 3: Add `dawn::backflow_apply` to dawn-ops.sh**

Add this block immediately after `dawn::backflow_scan` (the function just added in Task 1):

```bash
# Apply operator decisions from a decisions TSV to staging's copy of <file>.
# Args: <file> <decisions-file> [<cur-ref> [<sr-ref>]]
# Decisions line: <file>\t<path-json>\t<staging|current|staging_remote|value:JSON>
# Returns empty output if no changes needed (caller skips rewriting the file).
# Returns DAWN_STOP_JUDGMENT (rc 21) if any divergent key has no decision.
dawn::backflow_apply(){
  local file="$1" decisions="$2"
  local cur="${3:-$(dawn::current_ref)}"
  local sr="${4:-$(dawn::staging_remote_ref)}"

  local raw header body
  raw="$(git show "staging:$file" 2>/dev/null)"
  [ -z "$raw" ] && return 0
  header="$(printf '%s' "$raw" | perl -0ne 'print $1 if m{\A(\s*/\*.*?\*/\s*)}s')"
  body="$(printf '%s' "$raw" | dawn::_strip_jsonc)"

  local ops='[]' verdict f p sv cv rv res
  local -a unresolved=()
  _dawn_bfa_fold(){
    if [ "$1" = "$DAWN_ABSENT" ]; then
      ops="$(jq -c --argjson p "$p" '. + [{p:$p,del:true}]' <<< "$ops")"
    else
      ops="$(jq -c --argjson p "$p" --argjson v "$1" '. + [{p:$p,v:$v}]' <<< "$ops")"
    fi
  }

  while IFS=$'\t' read -r verdict f p sv cv rv; do
    [ "$f" = "$file" ] || continue
    res="$(awk -F'\t' -v ff="$file" -v pp="$p" '$1==ff && $2==pp {print $3}' "$decisions" 2>/dev/null | head -1)"
    case "$res" in
      staging)        : ;;
      current)        _dawn_bfa_fold "$cv" ;;
      staging_remote) _dawn_bfa_fold "$rv" ;;
      value:*)        _dawn_bfa_fold "${res#value:}" ;;
      *)              unresolved+=("$p") ;;
    esac
  done < <(dawn::backflow_scan "$cur" "$sr")

  if [ "${#unresolved[@]}" -gt 0 ]; then
    echo "STOP: unresolved decisions in $file:" >&2
    printf '  %s\n' "${unresolved[@]}" >&2
    return $DAWN_STOP_JUDGMENT
  fi

  [ "$ops" = "[]" ] && return 0

  [ -n "$header" ] && printf '%s\n' "$header"
  printf '%s' "$body" | jq --argjson ops "$ops" '
    reduce $ops[] as $o (.; if ($o.del // false) then delpaths([$o.p]) else setpath($o.p; $o.v) end)'
}
```

- [ ] **Step 4: Run the full test suite and confirm all tests pass**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh
```

Expected: all tests pass including `backflow_apply ok`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh \
        .claude/skills/_dawn-ops-lib/tests/test_backflow_apply.sh
git commit -m "feat(backflow): add dawn::backflow_apply — three-source decisions-driven value apply"
```

---

## Task 3: Rewrite backflow.sh and update tests

**Files:**
- Rewrite: `.claude/skills/dawn-backflow/backflow.sh`
- Rewrite: `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh`
- Rewrite: `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh`

### Overview of the new backflow.sh

The `--apply` / `--decisions` flags and the plan-mode gate are kept. The inner reconcile loop is replaced:

```
1. assert_not_current, assert_clean_tree
2. fetch remotes + sync markers
3. Detect non-config files on origin/current (still needs human classification — keep Step 0)
4. dawn::backflow_scan → all divergent config keys
5. dawn::nonconfig_drift_scan → locale drift
6. If scan empty AND nc_out empty → exit 0 (nothing to fold)
7. [plan mode] print per-key report, exit 22
8. [apply mode] verify all decisions present, apply per file, collapse snapshot, write markers, exit 0
```

- [ ] **Step 1: Write the new test_backflow.sh**

**Replace the entire content** of `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"
run(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
         DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" "${@:2}" ); }

# 1) All agree → exit 0 without decisions
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"k":"v"}' "base"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging
run "$d"; assert_rc "$?" 0 "all agree → exit 0"
assert_eq "$(git -C "$d" rev-list --count customizations..staging)" "1" "collapsed to one snapshot"

# 2) Any divergence without decisions → exit 22 (plan mode), staging unchanged
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"k":"base"}' "base"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
commit_on "$d2" current config/settings_data.json <<< '{"k":"live"}' "live edit"
git -C "$d2" checkout -q staging
before2=$(git -C "$d2" rev-parse staging)
run "$d2"; assert_rc "$?" 22 "divergence without decisions → exit 22"
assert_eq "$(git -C "$d2" rev-parse staging)" "$before2" "plan mode leaves staging unchanged"

# 3) Divergence + decision 'staging' → apply keeps staging's value
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"s-val"}' "base"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" current config/settings_data.json <<< '{"k":"c-val"}' "live"
git -C "$d3" checkout -q staging
dec3=$(mktemp)
printf 'config/settings_data.json\t["k"]\tstaging\n' > "$dec3"
run "$d3" --apply --decisions "$dec3"; assert_rc "$?" 0 "staging verdict → exit 0"
assert_eq "$(git -C "$d3" show staging:config/settings_data.json | jq -r .k)" "s-val" "k stays at staging value"
assert_eq "$(git -C "$d3" rev-list --count customizations..staging)" "1" "collapsed to one snapshot"
rm -f "$dec3"

# 4) Divergence + decision 'current' → apply takes current's value
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "base"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
commit_on "$d4" current config/settings_data.json <<< '{"k":"live"}' "live"
git -C "$d4" checkout -q staging
dec4=$(mktemp)
printf 'config/settings_data.json\t["k"]\tcurrent\n' > "$dec4"
run "$d4" --apply --decisions "$dec4"; assert_rc "$?" 0 "current verdict → exit 0"
assert_eq "$(git -C "$d4" show staging:config/settings_data.json | jq -r .k)" "live" "k takes current value"
assert_eq "$(git -C "$d4" rev-list --count customizations..staging)" "1" "collapsed to one snapshot"
rm -f "$dec4"

# 5) --apply without decisions when divergence exists → GUARD (exit 10)
d5=$(dawn_test_repo)
commit_on "$d5" staging config/settings_data.json <<< '{"k":"base"}' "base"
git -C "$d5" checkout -q current; git -C "$d5" merge -q staging -m sync
git -C "$d5" checkout -q staging_remote; git -C "$d5" merge -q staging -m sync
commit_on "$d5" current config/settings_data.json <<< '{"k":"live"}' "live"
git -C "$d5" checkout -q staging
before5=$(git -C "$d5" rev-parse staging)
run "$d5" --apply; assert_rc "$?" 10 "apply without decisions → GUARD"
assert_eq "$(git -C "$d5" rev-parse staging)" "$before5" "GUARD leaves staging unchanged"

# 6) Enrichment commit is the floor — preserved, never squashed
d6=$(dawn_test_repo)
commit_on "$d6" staging snippets/foo.liquid <<< 'hello' "L2: enrichment snippet"
commit_on "$d6" staging config/settings_data.json <<< '{"a":1}' "L2: store config snapshot"
git -C "$d6" checkout -q current; git -C "$d6" merge -q staging -m sync
git -C "$d6" checkout -q staging_remote; git -C "$d6" merge -q staging -m sync
git -C "$d6" checkout -q staging
run "$d6"; assert_rc "$?" 0 "enrichment-floor: all agree → exit 0"
assert_eq "$(git -C "$d6" log -1 --format=%s staging | grep -c 'store config snapshot')" "1" "tip is the snapshot"
assert_eq "$(git -C "$d6" log -1 --format=%s staging~1)" "L2: enrichment snippet" "enrichment preserved below snapshot"

echo "  backflow ok"

# --- sync markers ---

# plan-mode: no marker write
d7=$(dawn_test_repo)
commit_on "$d7" staging config/settings_data.json <<< '{"k":"base"}' "base"
git -C "$d7" checkout -q current; git -C "$d7" merge -q staging -m sync
git -C "$d7" checkout -q staging_remote; git -C "$d7" merge -q staging -m sync
commit_on "$d7" current config/settings_data.json <<< '{"k":"live"}' "live"
git -C "$d7" checkout -q staging
run "$d7" >/dev/null
marker_after_plan=$(git -C "$d7" rev-parse --verify -q refs/dawn-sync/current 2>/dev/null || echo "MISSING")
assert_eq "$marker_after_plan" "MISSING" "plan-mode does not write the marker"

# apply-mode: writes both markers
cur_sha7=$(git -C "$d7" rev-parse current); sr_sha7=$(git -C "$d7" rev-parse staging_remote)
dec7=$(mktemp); printf 'config/settings_data.json\t["k"]\tcurrent\n' > "$dec7"
run "$d7" --apply --decisions "$dec7" >/dev/null
assert_eq "$(git -C "$d7" rev-parse refs/dawn-sync/current)" "$cur_sha7" "apply writes current marker"
assert_eq "$(git -C "$d7" rev-parse refs/dawn-sync/staging-remote)" "$sr_sha7" "apply writes sr marker"
rm -f "$dec7"

# nothing-to-fold (all agree): always writes markers even without --apply
d8=$(dawn_test_repo)
commit_on "$d8" staging config/settings_data.json <<< '{"k":"v"}' "base"
git -C "$d8" checkout -q current; git -C "$d8" merge -q staging -m sync
git -C "$d8" checkout -q staging_remote; git -C "$d8" merge -q staging -m sync
git -C "$d8" checkout -q staging
cur_sha8=$(git -C "$d8" rev-parse current); sr_sha8=$(git -C "$d8" rev-parse staging_remote)
run "$d8" >/dev/null; assert_rc "$?" 0 "nothing to fold: exit 0"
assert_eq "$(git -C "$d8" rev-parse refs/dawn-sync/current)" "$cur_sha8" "nothing-to-fold writes current marker"
assert_eq "$(git -C "$d8" rev-parse refs/dawn-sync/staging-remote)" "$sr_sha8" "nothing-to-fold writes sr marker"

echo "  backflow sync-marker ok"
```

- [ ] **Step 2: Write the new test_backflow_drift.sh**

**Replace the entire content** of `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"
run(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
         DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" "${@:2}" ); }

# 1) origin/staging drift requires explicit decision; plan shows key detail
d=$(dawn_test_repo)
commit_on "$d" staging templates/page.withdrawal.json \
  <<< '{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":36}}}}' "base"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
commit_on "$d" staging_remote templates/page.withdrawal.json \
  <<< '{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":0}}}}' "bot edit"
git -C "$d" checkout -q staging
before=$(git -C "$d" rev-parse staging)
plan_out=$(run "$d" 2>&1); assert_rc "$?" 22 "staging_remote drift: plan stops for approval"
assert_eq "$(git -C "$d" rev-parse staging)" "$before" "plan-only run leaves staging untouched"
assert_contains "$plan_out" '"padding_bottom"' "plan report names the key"
assert_contains "$plan_out" 'staging_remote' "plan output mentions staging_remote verdict option"

# 2) staging_remote drift with 'staging_remote' verdict → folds preview value
dec=$(mktemp)
printf 'templates/page.withdrawal.json\t["sections","wf","settings","padding_bottom"]\tstaging_remote\n' > "$dec"
run "$d" --apply --decisions "$dec"; assert_rc "$?" 0 "staging_remote verdict: apply ok"
assert_eq "$(git -C "$d" show staging:templates/page.withdrawal.json \
  | jq -r .sections.wf.settings.padding_bottom)" "0" "preview value folded in"
rm -f "$dec"

# 3) staging_remote drift with 'staging' verdict → keeps staging's value
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"col":"base"}' "base"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging_remote config/settings_data.json <<< '{"col":"red"}' "bot edit"
git -C "$d3" checkout -q staging
dec3=$(mktemp)
printf 'config/settings_data.json\t["col"]\tstaging\n' > "$dec3"
run "$d3" --apply --decisions "$dec3"; assert_rc "$?" 0 "staging verdict: apply ok"
assert_eq "$(git -C "$d3" show staging:config/settings_data.json | jq -r .col)" "base" "staging value kept (bot edit rejected)"
rm -f "$dec3"

# 4) Non-config drift conflict (locale file, same line edited both places) → GUARD
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
commit_on "$d4" staging_remote locales/nl.json <<< '{"a":"bot-value","b":"base"}'
git -C "$d4" checkout -q staging
commit_on "$d4" staging locales/nl.json <<< '{"a":"staging-value","b":"base"}'
before4=$(git -C "$d4" rev-parse staging)
run "$d4"; assert_rc "$?" 10 "non-config drift conflict: GUARD"
assert_eq "$(git -C "$d4" rev-parse staging)" "$before4" "GUARD leaves staging untouched"

# 5) Plan report shows per-key detail for all divergent keys
d5=$(dawn_test_repo)
commit_on "$d5" staging config/settings_data.json <<< '{"col":"base","img":"base"}' "base"
git -C "$d5" checkout -q current; git -C "$d5" merge -q staging -m sync
git -C "$d5" checkout -q staging_remote; git -C "$d5" merge -q staging -m sync
commit_on "$d5" staging_remote config/settings_data.json <<< '{"col":"red","img":"abc"}' "preview edits"
git -C "$d5" checkout -q staging
plan5=$(run "$d5" 2>&1); assert_rc "$?" 22 "plan stops for approval"
assert_contains "$plan5" '"col"' "plan shows col key"
assert_contains "$plan5" '"img"' "plan shows img key"

echo "  backflow_drift ok"
```

- [ ] **Step 3: Run tests and confirm BOTH test files fail**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh 2>&1 | tail -20
```

Expected: `test_backflow.sh` and `test_backflow_drift.sh` fail (old behaviour no longer matches). The new test files test the new expected behaviour.

- [ ] **Step 4: Rewrite backflow.sh**

**Replace the entire content** of `.claude/skills/dawn-backflow/backflow.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

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
sr="$(dawn::staging_remote_ref)"

git fetch origin current --quiet 2>/dev/null || true
git fetch origin staging --quiet 2>/dev/null || true
git fetch origin refs/dawn-sync/current:refs/dawn-sync/current --quiet 2>/dev/null || true
git fetch origin refs/dawn-sync/staging-remote:refs/dawn-sync/staging-remote --quiet 2>/dev/null || true

cur_sha="$(git rev-parse "$cur" 2>/dev/null || true)"
sr_sha="$(git rev-parse "$sr" 2>/dev/null || true)"

orig_sha="$(git rev-parse staging)"
dawn::with_branch staging || exit $DAWN_GUARD

_dawn_bf_abort(){ git reset -q --hard "$orig_sha" 2>/dev/null || true; exit "$1"; }

_dawn_bf_sync_markers(){
  [ "${1:-}" = "force" ] || [ "$APPLY" = "1" ] || return 0
  dawn::sync_marker_set current "$cur_sha"
  dawn::sync_marker_set staging-remote "$sr_sha"
}

# --- Step 0: detect non-config files on origin/current (need human classification) ---
noncfg=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -n "$(dawn::config_class "$f")" ] && continue
  noncfg+=("$f")
done < <(git diff --name-only staging "$cur" -- . ':(exclude)docs/' ':(exclude).claude/')
if [ "${#noncfg[@]}" -gt 0 ]; then
  echo "STOP: origin/current has non-config changes that need classification:" >&2
  printf '  %s\n' "${noncfg[@]}" >&2
  echo "Decide per file: enrichment -> own L2 commit; generic -> dawn-harvest; churn -> ignore." >&2
  _dawn_bf_abort $DAWN_STOP_JUDGMENT
fi

# --- Step 1: scan config-class divergences across all three sources ---
scan="$(dawn::backflow_scan "$cur" "$sr")" || _dawn_bf_abort $DAWN_GUARD

# --- Step 2: non-config drift from origin/staging ---
nc_out="$(dawn::nonconfig_drift_scan)"; nc_rc=$?
if [ "$nc_rc" = "1" ]; then
  echo "GUARD: origin/staging conflicts with local staging in:" >&2
  sed 's/^/  /' <<< "$nc_out" >&2
  echo "Resolve manually and re-run." >&2
  _dawn_bf_abort $DAWN_GUARD
fi

# --- Nothing to do? ---
if [ -z "$scan" ] && [ -z "$nc_out" ]; then
  echo "Nothing to reconcile; staging is in sync with origin/current and origin/staging."
  _dawn_bf_sync_markers force
  exit $DAWN_OK
fi

# --- Plan mode ---
if [ "$APPLY" != "1" ]; then
  if [ -n "$scan" ]; then
    echo "Config settings that differ between staging, origin/current, and origin/staging:"
    echo
    while IFS=$'\t' read -r verdict f p sv cv rv; do
      printf '  %s  %s\n    staging=%s  origin/current=%s  origin/staging=%s\n' \
        "$f" "$p" "$sv" "$cv" "$rv"
    done <<< "$scan"
    echo
    printf 'Decisions TSV format: <file>\\t<path-json>\\t<staging|current|staging_remote|value:JSON>\n'
    echo
  fi
  if [ -n "$nc_out" ]; then
    echo "Non-config drift from origin/staging (folded automatically on apply):"
    sed 's/^/  /' <<< "$nc_out"
    echo
  fi
  rerun="bash .claude/skills/dawn-backflow/backflow.sh --apply"
  [ "$DECISIONS" != "/dev/null" ] && rerun="$rerun --decisions $DECISIONS"
  echo "Proceed? re-run with: $rerun"
  _dawn_bf_abort $DAWN_STOP_APPROVAL
fi

# --- Apply mode: verify all decisions are present ---
if [ -n "$scan" ]; then
  missing=""
  while IFS=$'\t' read -r verdict f p sv cv rv; do
    res="$(awk -F'\t' -v ff="$f" -v pp="$p" '$1==ff && $2==pp {print $3}' "$DECISIONS" 2>/dev/null | head -1)"
    [ -z "$res" ] && missing+="  $f $p"$'\n'
  done <<< "$scan"
  if [ -n "$missing" ]; then
    echo "GUARD: missing decisions — re-run in plan mode first, then provide decisions:" >&2
    printf '%s' "$missing" >&2
    _dawn_bf_abort $DAWN_GUARD
  fi
fi

# --- Apply config changes ---
config_changed=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  merged="$(dawn::backflow_apply "$f" "$DECISIONS" "$cur" "$sr")" || _dawn_bf_abort $?
  [ -z "$merged" ] && continue
  if [ ! -f "$f" ] || [ "$(cat "$f")" != "$merged" ]; then
    mkdir -p "$(dirname "$f")"; printf '%s\n' "$merged" > "$f"
    config_changed=1
  fi
done < <({ dawn::config_targets "$cur"; dawn::config_targets "$sr"; } | sort -u)

if [ "$config_changed" = "1" ]; then
  git add -A
  git commit -q -m "fold config (backflow)"
fi

# --- Apply non-config drift ---
if [ -n "$nc_out" ]; then
  dawn::nonconfig_drift_apply
  git add -A
  git commit -q -m "fold origin/staging (other)"
fi

# --- Collapse config snapshot ---
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

echo "Backflow complete: staging config collapsed into one snapshot at the tip."
_dawn_bf_sync_markers
exit $DAWN_OK
```

- [ ] **Step 5: Run the full test suite and confirm all tests pass**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh
```

Expected: all tests pass. Pay specific attention to `backflow ok`, `backflow_drift ok`, and all reconcile/guard tests that must remain untouched.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/dawn-backflow/backflow.sh \
        .claude/skills/_dawn-ops-lib/tests/test_backflow.sh \
        .claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh
git commit -m "feat(backflow): rewrite reconcile loop — three-source comparison, all decisions explicit"
```

---

## Task 4: Add `dawn::assert_stage_push_current` + promote guard

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh` (add function before `dawn::assert_backflow_not_pending`)
- Modify: `.claude/skills/dawn-promote/promote.sh` (add guard call at line 8)
- Create: `.claude/skills/_dawn-ops-lib/tests/test_promote_stage_push_guard.sh`

### What `dawn::assert_stage_push_current` does

Checks that the exact staging SHA was pushed to origin/staging via `dawn-stage-push` and neither has moved since:

1. `refs/dawn-sync/staging-remote` exists — stage-push was run at least once
2. `git rev-parse staging` == marker — staging hasn't gained new commits since the push
3. `git rev-parse origin/staging` (after fetch) == marker — preview theme hasn't received bot commits since the push

- [ ] **Step 1: Create the failing test file**

Create `.claude/skills/_dawn-ops-lib/tests/test_promote_stage_push_guard.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
PROMOTE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-promote" && pwd)/promote.sh"
run(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
         DAWN_PROMOTE_REF=refs/heads/current DAWN_PUSH="git update-ref" \
         DAWN_SYNC_MARKER_NOPUSH=1 bash "$PROMOTE" "${@:2}" ); }

# Shared helper: set up a clean repo with markers in place (backflow done, stage-push done)
setup_clean_promote(){
  local d; d=$(dawn_test_repo)
  commit_on "$d" staging config/settings_data.json <<< '{"k":"v"}' "config snapshot"
  git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
  git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
  git -C "$d" checkout -q staging
  # Set backflow markers (simulate completed backflow)
  git -C "$d" update-ref refs/dawn-sync/current "$(git -C "$d" rev-parse current)"
  git -C "$d" update-ref refs/dawn-sync/staging-remote "$(git -C "$d" rev-parse staging_remote)"
  # Set stage-push marker (simulate completed stage-push)
  git -C "$d" update-ref refs/dawn-sync/staging-remote "$(git -C "$d" rev-parse staging)"
  git -C "$d" update-ref refs/dawn-sync/staging-remote "$(git -C "$d" rev-parse staging)"
  # staging_remote branch must match staging SHA for the guard to pass
  git -C "$d" update-ref refs/heads/staging_remote "$(git -C "$d" rev-parse staging)"
  echo "$d"
}

# 1) No staging-remote marker → GUARD with "never been pushed" message
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"k":"v"}' "config snapshot"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging
out1=$(run "$d" --confirm-live 2>&1); assert_rc "$?" 10 "no marker → GUARD"
assert_contains "$out1" "never been pushed" "message: never been pushed"

# 2) Marker set but staging has a new commit → GUARD
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"k":"v"}' "base"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging
staging_sha2=$(git -C "$d2" rev-parse staging)
git -C "$d2" update-ref refs/dawn-sync/staging-remote "$staging_sha2"
commit_on "$d2" staging config/settings_data.json <<< '{"k":"v2"}' "new backflow commit"
git -C "$d2" checkout -q staging
out2=$(run "$d2" --confirm-live 2>&1); assert_rc "$?" 10 "staging advanced past marker → GUARD"
assert_contains "$out2" "staging has changed" "message: staging changed since push"

# 3) Marker and staging match, but staging_remote advanced → GUARD
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"v"}' "base"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging
staging_sha3=$(git -C "$d3" rev-parse staging)
git -C "$d3" update-ref refs/dawn-sync/staging-remote "$staging_sha3"
git -C "$d3" update-ref refs/dawn-sync/current "$(git -C "$d3" rev-parse current)"
# Advance staging_remote (simulate Shopify bot commit on preview)
commit_on "$d3" staging_remote config/settings_data.json <<< '{"k":"bot"}' "bot edit"
git -C "$d3" checkout -q staging
out3=$(run "$d3" --confirm-live 2>&1); assert_rc "$?" 10 "staging_remote advanced → GUARD"
assert_contains "$out3" "preview theme has changed" "message: preview changed since push"

# 4) All three match → stage-push guard passes (proceeds to backflow-pending guard)
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"v"}' "config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging
sha4=$(git -C "$d4" rev-parse staging)
git -C "$d4" update-ref refs/dawn-sync/staging-remote "$sha4"
git -C "$d4" update-ref refs/heads/staging_remote "$sha4"
git -C "$d4" update-ref refs/dawn-sync/current "$(git -C "$d4" rev-parse current)"
# With all markers set and everything matching, promote should get past stage-push guard.
# It will hit exit 20 (confirm-live gate) since staging is clean.
out4=$(run "$d4" --confirm-live 2>&1); rc4=$?
# rc may be 0 (success) or 10 from some other guard — but must NOT be 10 with "never been pushed"
assert_not_contains "$out4" "never been pushed" "no false alarm from stage-push guard"
assert_not_contains "$out4" "staging has changed" "no false alarm: staging matches marker"
assert_not_contains "$out4" "preview theme has changed" "no false alarm: preview matches marker"

echo "  promote_stage_push_guard ok"
```

- [ ] **Step 2: Run tests and verify the new test file fails**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh 2>&1 | tail -10
```

Expected: `test_promote_stage_push_guard.sh` fails because `dawn::assert_stage_push_current` is not defined.

- [ ] **Step 3: Add `dawn::assert_stage_push_current` to dawn-ops.sh**

Find `dawn::assert_backflow_not_pending` in `dawn-ops.sh` (around line 360). Add the following block **immediately before** it:

```bash
# Guard: staging must have been pushed to origin/staging via dawn-stage-push and neither
# staging nor origin/staging may have changed since that push. The sync marker
# refs/dawn-sync/staging-remote records staging's exact SHA at the last stage-push.
dawn::assert_stage_push_current(){
  local marker; marker="$(dawn::sync_marker_get staging-remote 2>/dev/null || true)"
  if [ -z "$marker" ]; then
    echo "GUARD: stage-push first — staging has never been pushed to the preview theme" >&2
    return $DAWN_GUARD
  fi
  local staging_sha; staging_sha="$(git rev-parse staging 2>/dev/null || true)"
  if [ "$staging_sha" != "$marker" ]; then
    echo "GUARD: stage-push first — staging has changed since the last preview push" >&2
    return $DAWN_GUARD
  fi
  git fetch origin staging --quiet 2>/dev/null || true
  local remote_sha; remote_sha="$(git rev-parse "${DAWN_STAGING_REMOTE_REF:-origin/staging}" 2>/dev/null || true)"
  if [ "$remote_sha" != "$marker" ]; then
    echo "GUARD: stage-push first — the preview theme has changed since the last push (run backflow then stage-push again)" >&2
    return $DAWN_GUARD
  fi
  return 0
}
```

- [ ] **Step 4: Add the guard call to promote.sh**

Read `.claude/skills/dawn-promote/promote.sh`. Find the existing guard line:

```bash
dawn::assert_backflow_not_pending || exit $DAWN_GUARD
```

Insert `dawn::assert_stage_push_current` **before** it:

```bash
dawn::assert_stage_push_current || exit $DAWN_GUARD
dawn::assert_backflow_not_pending || exit $DAWN_GUARD
```

- [ ] **Step 5: Run the full test suite and confirm all tests pass**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh
```

Expected: all tests pass including `promote_stage_push_guard ok`. The existing `test_promote_guard.sh` must also still pass.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh \
        .claude/skills/dawn-promote/promote.sh \
        .claude/skills/_dawn-ops-lib/tests/test_promote_stage_push_guard.sh
git commit -m "feat(promote): guard — staging must match the last stage-push before promoting"
```

---

## Task 5: Update SKILL.md files and docs

**Files:**
- Rewrite: `.claude/skills/dawn-backflow/SKILL.md`
- Modify: `.claude/skills/dawn-promote/SKILL.md`

No tests needed (doc-only).

- [ ] **Step 1: Rewrite `.claude/skills/dawn-backflow/SKILL.md`**

Replace the entire file with:

```markdown
---
name: dawn-backflow
description: Pull live Shopify admin/config edits from the current branch back into staging. Use when the user says backflow, capture admin changes, sync config from live, or before a promote.
---

## Overview

The `dawn-backflow` skill compares config settings across **three sources** — your local `staging`
branch, the live published theme (`origin/current`), and the preview theme (`origin/staging`) — and
asks the operator to choose the target value for every setting where the three sources do not all
agree. Nothing folds automatically; every divergence surfaces as an explicit decision.

## Prerequisites

- Be checked out on the `ops` branch (never on `current`).
- Conventions reference: `.claude/skills/_dawn-ops-lib/conventions.md`

## Running

```bash
bash .claude/skills/dawn-backflow/backflow.sh
```

This is **plan mode** (the default) — fetches both remotes, scans for divergences, prints a
per-key report, then stops for decisions and approval. No lasting commit is made until you re-run
with `--apply --decisions`.

### Exit 0 — nothing to reconcile, or apply completed

Either all three sources agree on every key (nothing to do), or you ran with `--apply` and the
config snapshot at the tip of `staging` now holds the reconciled result.

### Exit 10 — guard triggered

Report the guard message from stderr. Common causes:

- **Dirty working tree** — commit or stash local changes first.
- **Staging tip is not the config snapshot** — fix branch ordering first.
- **`origin/staging` conflicts with local staging** in a non-config file — resolve by hand and
  re-run.
- **`--apply` called without decisions** when divergences exist — run plan mode first.

### Exit 21 — classification needed

`origin/current` has non-config file changes (rare). Classify each per the table:

| Classification | Action |
|---|---|
| **Enrichment** (L2 store-specific logic) | Create its own L2 commit on `staging` |
| **Generic L1 improvement** | Use the `dawn-harvest` skill |
| **Churn / noise** | Ignore |

### Exit 22 — plan ready: per-key decisions needed, then approval

The plan report lists every divergent config key:

```
  <file>  <path-json>
    staging=<val>  origin/current=<val>  origin/staging=<val>
```

**Step 1 — Per-key decisions**

For each key in the report, ask a single `AskUserQuestion` with `multiSelect: false`:

- **Keep staging** `<staging-val>` — no change to staging
- **Take origin/current** `<cur-val>` *(skip if same as another option)*
- **Take origin/staging** `<sr-val>` *(skip if same as another option)*
- **Enter a custom value** — follow-up open-text prompt

If two options have the same value, collapse them into one label (e.g. "Keep staging /
origin/current agree on `<val>`"). Build the decisions TSV at `/tmp/backflow-decisions.tsv`:

```
<file>\t<path-json>\t<staging|current|staging_remote|value:JSON>
```

**Step 2 — Approval gate**

Relay the plan report to the user and ask one `AskUserQuestion` (Approve / Abort). On approval:

```bash
bash .claude/skills/dawn-backflow/backflow.sh --apply --decisions /tmp/backflow-decisions.tsv
```

On abort, stop — nothing was written; `staging` is exactly as it was.
```

- [ ] **Step 2: Update `.claude/skills/dawn-promote/SKILL.md`**

Read the file. Find the `**Exit 10 (GUARD — backflow pending)**` section. Replace its heading and body with:

```markdown
**Exit 10 (GUARD)**

Two possible causes — the message printed to stderr names which:

1. **Stage-push not current.** Either staging was never pushed to the preview theme, staging has
   changed since the last push, or the preview theme received a new bot commit since the push. In
   all cases: run `dawn-stage-push` (after `dawn-backflow` if needed), then retry promote.

2. **Backflow pending.** Either `origin/current` or `origin/staging` has config edits not yet
   folded into staging. Report the guard message, then tell the user:
   > "There are unsynced live edits that must be merged back into staging first. Run the
   > `dawn-backflow` skill, then retry stage-push and promote."
```

- [ ] **Step 3: Run the full test suite to confirm nothing broke**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/dawn-backflow/SKILL.md \
        .claude/skills/dawn-promote/SKILL.md
git commit -m "docs(backflow/promote): update SKILL.md for three-source reconcile and stage-push guard"
```

---

## Self-review

**Spec coverage:**
- ✅ `dawn::backflow_scan` — no-base three-source comparison → Task 1
- ✅ `dawn::backflow_apply` — decisions-driven apply, `staging_remote` verdict → Task 2
- ✅ `backflow.sh` rewritten to use new functions → Task 3
- ✅ Old `reconcile_scan` / `reconcile_apply` / `reconcile_pending` untouched → Tasks 1–3 (only add, don't modify)
- ✅ `dawn::assert_stage_push_current` function → Task 4
- ✅ promote.sh: new guard before existing guard → Task 4
- ✅ SKILL.md for backflow: per-key AskUserQuestion flow → Task 5
- ✅ SKILL.md for promote: new Exit 10 causes → Task 5

**Placeholder scan:** No TBD, no "add error handling", no forward references — all code is complete.

**Type consistency:**
- `dawn::backflow_scan` called with `"$cur" "$sr"` in Task 1, in Task 2's internal call, and in backflow.sh Task 3. ✓
- `dawn::backflow_apply` signature `<file> <decisions> <cur> <sr>` consistent across Task 2 definition and Task 3 call site. ✓
- `dawn::assert_stage_push_current` defined in Task 4, called in promote.sh in Task 4. ✓
- `staging_remote` verdict (string) used in Task 2 decisions TSV, Task 2 test, Task 3 test, and Task 5 SKILL.md. ✓
