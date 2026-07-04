# Backflow Selective Reject Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the operator pin specific "other-ahead" keys to staging's value during backflow, instead of all other-ahead keys folding unconditionally.

**Architecture:** Two coordinated changes: (1) `dawn::reconcile_apply` checks the decisions TSV for `current_ahead` rows and skips the fold when the verdict is `staging`; (2) backflow's plan-mode report gains per-key detail for every other-ahead fold (file + path + old → new), plus a ready-to-paste decisions-file stub so the operator can pin any key before running `--apply`. No new data structures or files — the decisions TSV already has the right shape, we just extend it to cover a new case.

**Tech Stack:** bash, awk, jq — same as the rest of dawn-ops.sh; no new dependencies.

---

## Safety protocol (required for every subagent working on this plan)

Real git mutations are limited to `git add` / `git commit` on the files actually in scope. All test fixtures must use the `dawn_test_repo` / `commit_on` / `in_repo` helpers from `.claude/skills/_dawn-ops-lib/tests/helpers.sh` (mktemp-d based). **No `git push` ever**, under any circumstances, without the human's direct confirmation in the conversation. Verify every subagent report by reading the actual diff and re-running the test suite yourself before moving to the next task.

---

## File map

| File | Change |
|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | Extend `dawn::reconcile_apply`: check decisions for `current_ahead` rows, skip fold when verdict is `staging` |
| `.claude/skills/_dawn-ops-lib/tests/test_reconcile_apply.sh` | Add test: `staging` verdict on an other-ahead key leaves it at staging's value |
| `.claude/skills/dawn-backflow/backflow.sh` | Capture per-key scan detail during plan mode; print it in the report with decisions-stub hints |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh` | Add test: plan output contains per-key detail; decisions-pinned key is not folded on `--apply` |
| `.claude/skills/dawn-backflow/SKILL.md` | Document `staging` verdict for other-ahead keys; explain per-key report format and decisions-stub workflow |

---

## Background: how the existing reconciler works

`dawn::reconcile_scan` compares staging vs an "other" ref (default `origin/current`, or `origin/staging` when called with `dawn::staging_remote_ref`) key-by-key and emits TSV rows:

```
<verdict>\t<file>\t<path-json>\t<base>\t<staging>\t<other>
```

Verdicts: `staging_ahead` (only staging changed), `current_ahead` (only other changed — **these are what fold automatically**), `collision` (both changed differently).

`dawn::reconcile_apply` processes those rows. Today the `current_ahead` case folds unconditionally (`_dawn_fold "$c"`). The decisions TSV is only checked for `collision` rows. The fix extends the `current_ahead` case to also consult the decisions TSV — if the operator wrote a `staging` verdict for that file+path, the fold is skipped.

Decisions TSV line format (existing): `<file>\t<path-json>\t<staging|current|value:JSON>`

---

## Task 1: Extend `dawn::reconcile_apply` to honour `staging` verdict for other-ahead keys

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh:278-292`
- Test: `.claude/skills/_dawn-ops-lib/tests/test_reconcile_apply.sh`

- [ ] **Step 1: Write the failing test**

Append to `.claude/skills/_dawn-ops-lib/tests/test_reconcile_apply.sh` (before the final `echo "  reconcile_apply ok"`):

```bash
# staging verdict on current_ahead key => key NOT folded, stays at staging's value
pin=$(dawn_test_repo)
commit_on "$pin" staging config/settings_data.json <<< '{"a":"base","b":"base"}' "base"
git -C "$pin" checkout -q current; git -C "$pin" merge -q staging -m sync
commit_on "$pin" current config/settings_data.json <<< '{"a":"live-a","b":"live-b"}' "live edits"
git -C "$pin" checkout -q staging
pin_dec="$pin/pin.tsv"
# Pin key "a" to staging (reject the live edit); let key "b" fold normally
printf 'config/settings_data.json\t["a"]\tstaging\n' > "$pin_dec"
pin_merged=$(in_repo "$pin" "dawn::reconcile_apply config/settings_data.json '$pin_dec'"); rc=$?
assert_rc "$rc" 0 "staging-verdict-on-other-ahead exits 0"
assert_eq "$(jq -r '.a' <<< "$pin_merged")" "base" "pinned key stays at staging value"
assert_eq "$(jq -r '.b' <<< "$pin_merged")" "live-b" "unpinned key still folded"
```

- [ ] **Step 2: Run the new test case to verify it fails**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh 2>&1 | grep -A2 "staging-verdict-on-other-ahead"
```

Expected: the test fails — `a` comes back as `"live-a"` instead of `"base"` because the current code folds unconditionally.

- [ ] **Step 3: Implement the fix in `dawn-ops.sh`**

Find the `while IFS=$'\t' read -r verdict f p b s c` loop inside `dawn::reconcile_apply` (around line 278). The relevant case is:

```bash
current_ahead) _dawn_fold "$c" ;;
```

Replace it with:

```bash
current_ahead)
  res="$(awk -F'\t' -v f="$file" -v pp="$p" '$1==f && $2==pp {print $3}' "$decisions" 2>/dev/null | head -1)"
  [ "$res" = "staging" ] || _dawn_fold "$c" ;;
```

The `awk` expression is identical to the one already used for `collision` rows — same decisions file, same lookup key. The only new behaviour: if the operator explicitly wrote `staging` for an other-ahead key, the fold is skipped. Any other value in `$res` (empty, `current`, `value:*`) falls through to the existing fold.

- [ ] **Step 4: Run the full test suite and confirm all tests pass**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh
```

Expected: all tests pass, including the new `staging-verdict-on-other-ahead` case.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh \
        .claude/skills/_dawn-ops-lib/tests/test_reconcile_apply.sh
git commit -m "feat(backflow): honour 'staging' verdict on other-ahead keys in reconcile_apply"
```

---

## Task 2: Enhance backflow plan report with per-key detail and decisions-stub hints

**Files:**
- Modify: `.claude/skills/dawn-backflow/backflow.sh:50-99` (scan capture) and `162-191` (plan report)
- Test: `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh`

- [ ] **Step 1: Write the failing tests**

Append to `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh` (before the final `echo "  backflow_drift ok"`):

```bash
# 5) Plan report includes per-key detail for other-ahead folds.
d5=$(dawn_test_repo)
commit_on "$d5" staging config/settings_data.json <<< '{"col":"base","img":"base"}' "config snapshot"
git -C "$d5" checkout -q current; git -C "$d5" merge -q staging -m sync
git -C "$d5" checkout -q staging_remote; git -C "$d5" merge -q staging -m sync
commit_on "$d5" staging_remote config/settings_data.json <<< '{"col":"red","img":"abc"}' "preview live edits"
git -C "$d5" checkout -q staging
plan5=$(run "$d5" 2>&1); assert_rc "$?" 22 "per-key report: plan stops for approval"
assert_contains "$plan5" '"col"' "plan report includes key path col"
assert_contains "$plan5" '"img"' "plan report includes key path img"
assert_contains "$plan5" 'staging' "plan report mentions staging verdict hint"

# 6) Decisions-pinned other-ahead key is NOT folded on --apply.
d6=$(dawn_test_repo)
commit_on "$d6" staging config/settings_data.json <<< '{"col":"base","img":"base"}' "config snapshot"
git -C "$d6" checkout -q current; git -C "$d6" merge -q staging -m sync
git -C "$d6" checkout -q staging_remote; git -C "$d6" merge -q staging -m sync
commit_on "$d6" staging_remote config/settings_data.json <<< '{"col":"red","img":"abc"}' "preview live edits"
git -C "$d6" checkout -q staging
dec6=$(mktemp)
# Pin "col" to staging (reject the live edit), let "img" fold
printf 'config/settings_data.json\t["col"]\tstaging\n' > "$dec6"
run "$d6" --apply --decisions "$dec6"; assert_rc "$?" 0 "pinned apply ok"
assert_eq "$(git -C "$d6" show staging:config/settings_data.json | jq -r .col)" "base" "pinned key not folded"
assert_eq "$(git -C "$d6" show staging:config/settings_data.json | jq -r .img)" "abc"  "unpinned key folded"
rm -f "$dec6"
```

- [ ] **Step 2: Run the new tests to verify they fail**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh 2>&1 | grep -E "per-key report|pinned apply|FAIL"
```

Expected: test 5 fails (no key paths in plan output), test 6 fails (col gets folded to "red").

- [ ] **Step 3: Capture per-key detail in backflow.sh**

In `backflow.sh`, right after line 54 (`sr_scan="$(dawn::reconcile_scan "$staging_remote")" || _dawn_bf_abort $DAWN_GUARD`), add:

```bash
sr_key_detail="$(grep -E '^current_ahead\t' <<< "$sr_scan" || true)"
```

And right after line 118 (`scan="$(dawn::reconcile_scan)" || _dawn_bf_abort $DAWN_GUARD`), add:

```bash
cur_key_detail="$(grep -E '^current_ahead\t' <<< "$scan" || true)"
```

These capture the `current_ahead` rows we need for the report. Both variables need to be declared near the top of the file alongside `report_staging_remote` and `report_current`:

After the existing lines:
```bash
report_staging_remote=()
report_current=()
```

Add:
```bash
sr_key_detail=""
cur_key_detail=""
```

- [ ] **Step 4: Print per-key detail in the plan report**

Find the plan-mode report block (around line 174 — the `if [ "$APPLY" != "1" ]` block). Replace the existing file-listing section with this expanded version:

```bash
if [ "$APPLY" != "1" ]; then
  echo "Backflow plan:"
  echo

  _print_key_detail(){   # $1 = TSV string of current_ahead rows, $2 = "other" label
    local rows="$1" label="$2"
    [ -z "$rows" ] && return
    echo "  Per-key detail (add '<file>\\t<path>\\tstaging' to a decisions file to pin any key):"
    while IFS=$'\t' read -r verdict f p b s c; do
      printf '    %s  %s  staging=%s → %s=%s\n' "$f" "$p" "$s" "$label" "$c"
    done <<< "$rows"
    echo
  }

  if [ "${#report_staging_remote[@]}" -gt 0 ]; then
    echo "Pulling in from the live preview theme ($staging_remote) — your local copy didn't have these:"
    printf '  - %s\n' "${report_staging_remote[@]}"
    echo
    _print_key_detail "$sr_key_detail" "origin/staging"
  fi
  if [ "${#report_current[@]}" -gt 0 ]; then
    echo "Folding in from the live published theme ($cur):"
    printf '  - %s\n' "${report_current[@]}"
    echo
    _print_key_detail "$cur_key_detail" "origin/current"
  fi
  rerun="bash .claude/skills/dawn-backflow/backflow.sh --apply"
  [ "$DECISIONS" != "/dev/null" ] && rerun="$rerun --decisions $DECISIONS"
  echo "Proceed? re-run with: $rerun"
  _dawn_bf_abort $DAWN_STOP_APPROVAL
fi
```

- [ ] **Step 5: Run the full test suite and confirm all tests pass**

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh
```

Expected: all tests pass including the new test 5 (plan output includes key paths) and test 6 (pinned key not folded).

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/dawn-backflow/backflow.sh \
        .claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh
git commit -m "feat(backflow): plan report shows per-key detail + decisions-stub hint for other-ahead folds"
```

---

## Task 3: Update `SKILL.md` to document selective reject

**Files:**
- Modify: `.claude/skills/dawn-backflow/SKILL.md`

- [ ] **Step 1: Update the Exit 22 section**

Find the `### Exit 22 — plan ready, needs approval` section. After the first paragraph ("Every collision and classification above is resolved..."), add a new paragraph:

```markdown
The plan report also lists each individual key being folded (file, JSON path, staging value, and
live value) for both `origin/staging` and `origin/current`. If you want to **reject** a specific
live edit — keeping staging's value instead of folding the live one — you do not need to stage
a collision: add a `staging` verdict for that key to a decisions TSV before running `--apply`:

```
<file>\t<path-json>\tstaging
```

Any key not listed in the decisions file folds normally. `current` (explicit fold) and
`value:<json>` (custom value) remain valid for other-ahead keys too, though they are rarely needed.
```

- [ ] **Step 2: Update the collision decisions table**

In `### Exit 21 — decisions or classification needed`, item 3 ("Config collisions"), update the options table to note that `staging` is also valid for other-ahead keys (not just collisions):

Add a row note below the table:

```markdown
> **Note:** `staging` is also accepted for `current_ahead` / other-ahead keys in the decisions
> file — this pins the key to staging's value instead of taking the live edit. The plan report
> (exit 22) lists all other-ahead keys to make it easy to identify which paths to pin.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/dawn-backflow/SKILL.md
git commit -m "docs(backflow): document staging verdict for other-ahead keys + per-key plan report"
```

---

## Self-review

**Spec coverage:**
- ✅ `staging` verdict on other-ahead key skips fold → Task 1
- ✅ Plan report shows per-key detail → Task 2
- ✅ Decisions-stub hint in plan output → Task 2
- ✅ End-to-end test: pin key, apply, verify → Task 2 test 6
- ✅ SKILL.md documents new capability → Task 3

**Placeholder scan:** No TBD, no "add appropriate error handling", no forward references — all code is complete.

**Type consistency:** `sr_key_detail` / `cur_key_detail` declared at top of backflow.sh, populated immediately after the two `reconcile_scan` calls, consumed in the plan report — no name drift across tasks.

**Guard note:** `_print_key_detail` is defined inside the `if [ "$APPLY" != "1" ]` block (local to plan mode only). It uses a local function name that cannot conflict with any `dawn::*` namespace.
