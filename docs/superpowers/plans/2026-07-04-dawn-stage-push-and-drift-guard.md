# Dawn-ops: `dawn-stage-push` skill + shared origin/staging drift guard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close a real gap in `dawn-promote`'s drift guard (it only ever checks `origin/current`,
never `origin/staging`) and add a new `dawn-stage-push` skill so the release flow becomes
**backflow → stage-push → promote**, letting a reconciled `staging` be pushed to the preview theme
and tested live before it ever touches the published storefront.

**Architecture:** Generalize the existing `dawn::reconcile_pending` (already parametrized once for
`dawn::reconcile_scan`) to accept an optional `other` ref. Layer a new shared guard,
`dawn::assert_backflow_not_pending`, on top that checks BOTH remotes (`current` and
`staging_remote`) for config-class drift, plus `origin/staging`'s non-config drift
(`dawn::nonconfig_drift_scan`, already exists). `dawn-promote` and the new `dawn-stage-push` both
call this one shared guard. `dawn-stage-push` mirrors `dawn-promote`'s structure and test-seam
pattern, minus the live-confirm gate (it only pushes to the preview theme, never to `current`).

**Tech Stack:** Bash (`_dawn-ops-lib/dawn-ops.sh`), the repo's plain-bash test harness
(`_dawn-ops-lib/tests/helpers.sh`, no bats dependency), git plumbing (`refs/dawn-sync/*` sync
markers, `git merge-tree` for non-config 3-way merges).

**Read before starting:**
- `docs/superpowers/specs/2026-07-04-dawn-stage-push-and-drift-guard-design.md` — the approved
  design this plan implements.
- `docs/superpowers/specs/2026-07-03-dawn-backflow-staging-drift-and-plan-gate-design.md` and
  `docs/superpowers/specs/2026-07-03-dawn-backflow-sync-markers-design.md` — the two prior specs
  this design builds on (already shipped; `dawn::nonconfig_drift_scan`, the sync-marker mechanism,
  and `staging_remote`/`origin/staging` fetch/fold in `backflow.sh` all already exist).
- `.claude/skills/_dawn-ops-lib/conventions.md` — operating conventions all dawn-* skills follow.

---

## ⚠️ Safety protocol for every task below (implementer AND reviewer subagents)

Read this before touching anything. It applies to every task in this plan, without exception:

1. **Real git mutations in this working tree are limited to `git add` / `git commit` on the files
   actually listed as in-scope for the task you were dispatched to do.** Do not run any other git
   command (`checkout`, `merge`, `reset`, `rebase`, `branch`, `push`, etc.) against the real repo
   you are running in.
2. **All test fixtures MUST go through the existing helpers** in
   `.claude/skills/_dawn-ops-lib/tests/helpers.sh` — `dawn_test_repo` (creates a throwaway
   `mktemp -d` repo with `staging`/`current`/`staging_remote`/`customizations` branches),
   `commit_on`, and `in_repo`. Never `git checkout` a real branch (`staging`, `current`, `ops`) in
   this repo to build or exercise a test — every test operates on a disposable temp-dir repo the
   helper creates, never on the actual working tree.
3. **Never run `git push`, under any circumstances, without the human's own direct confirmation
   typed in this conversation** (not a summary or claim relayed by another subagent). None of the
   tasks in this plan require a real push — every test uses `DAWN_PUSH="git update-ref"` /
   `DAWN_STAGE_PUSH_REF` / `DAWN_PROMOTE_REF` test seams against the throwaway repo, exactly like
   the existing test suite already does.
4. If you are a reviewer subagent: verify by reading the actual diff (`git diff`) and by actually
   running `bash .claude/skills/_dawn-ops-lib/tests/run.sh` yourself. Do not trust an implementer's
   summary of "tests pass" — confirm it from real command output.

---

## File Structure

| File | Change |
|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | Generalize `dawn::reconcile_pending` (optional `other` param); add `dawn::assert_backflow_not_pending` |
| `.claude/skills/dawn-promote/promote.sh` | Replace single-remote guard with `dawn::assert_backflow_not_pending` |
| `.claude/skills/dawn-stage-push/stage-push.sh` (new) | New skill script |
| `.claude/skills/dawn-stage-push/SKILL.md` (new) | Skill doc: what it does, when to use it, exit codes |
| `.claude/skills/_dawn-ops-lib/tests/test_reconcile_pending.sh` | Add one case: generalized `other` param |
| `.claude/skills/_dawn-ops-lib/tests/test_assert_backflow_not_pending.sh` (new) | Unit coverage for the new shared guard |
| `.claude/skills/_dawn-ops-lib/tests/test_stage_push_flow.sh` (new) | The shared-fixture chain test from the design's §4 |
| `.claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh` | No change — its existing case must keep passing unmodified (regression signal) |
| `.claude/skills/_dawn-ops-lib/conventions.md` | Add `dawn-stage-push` to the skill list / release-mode table; note the guard now covers both remotes |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | Add `dawn-stage-push` row; update the standard workflow and decision tree to show backflow → stage-push → promote |

---

### Task 1: Generalize `dawn::reconcile_pending`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh:215-225`
- Test: `.claude/skills/_dawn-ops-lib/tests/test_reconcile_pending.sh`

- [ ] **Step 1: Write the failing test**

Append this case to the end of `test_reconcile_pending.sh`, before the final `echo`:

```bash
# Case: current-ahead-style drift on origin/staging (the "other" param) => pending against that
# ref specifically, while the default (current) call site is unaffected by it.
d4=$(dawn_test_repo)
commit_on "$d4" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base"}}}}'
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
commit_on "$d4" staging_remote sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"bot-edit"}}}}'
git -C "$d4" checkout -q staging
other=$(in_repo "$d4" 'dawn::staging_remote_ref')
in_repo "$d4" "dawn::reconcile_pending $other"; rc4=$?
assert_rc "$rc4" 0 "other-ref-ahead drift => pending against that ref"
in_repo "$d4" 'dawn::reconcile_pending'; rc4b=$?
assert_rc "$rc4b" 1 "default call site (current) unaffected by staging_remote's drift"
```

The full file's trailing `echo "  reconcile_pending ok"` stays where it is, after this new block.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_pending.sh`
Expected: FAIL — `dawn::reconcile_pending` today ignores any argument (it always calls
`dawn::reconcile_scan` with no ref), so `rc4` will be `1` instead of the expected `0`
("expected rc 0, got 1 (other-ref-ahead drift => pending against that ref)").

- [ ] **Step 3: Generalize the function**

In `.claude/skills/_dawn-ops-lib/dawn-ops.sh`, replace lines 215-225:

```bash
# rc 0 (pending) if any current-ahead leaf exists; else rc 1.
# Collisions are NOT counted here: they are decided at backflow time (backflow stops with
# exit 21 until every collision has a decision), and a collision resolved to staging is a
# deliberate staging-wins outcome that promote is meant to carry. Statelessly a
# resolved-to-staging collision is indistinguishable from an unresolved one (base absent,
# staging != current), so counting collisions here would block promote forever after you
# chose staging. A genuinely un-folded live edit shows up as current_ahead and does block.
dawn::reconcile_pending(){
  local scan; scan="$(dawn::reconcile_scan)" || return $DAWN_GUARD
  grep -qE '^current_ahead'$'\t' <<< "$scan"
}
```

with:

```bash
# rc 0 (pending) if any current-ahead leaf exists against <other> (default dawn::current_ref);
# else rc 1. Generalized exactly like dawn::reconcile_scan itself (optional `other` ref) so the
# existing call site (no arg) is unaffected — dawn::assert_backflow_not_pending is what actually
# passes dawn::staging_remote_ref.
# Collisions are NOT counted here: they are decided at backflow time (backflow stops with
# exit 21 until every collision has a decision), and a collision resolved to staging is a
# deliberate staging-wins outcome that promote is meant to carry. Statelessly a
# resolved-to-staging collision is indistinguishable from an unresolved one (base absent,
# staging != current), so counting collisions here would block promote forever after you
# chose staging. A genuinely un-folded live edit shows up as current_ahead and does block.
dawn::reconcile_pending(){
  local other="${1:-$(dawn::current_ref)}"
  local scan; scan="$(dawn::reconcile_scan "$other")" || return $DAWN_GUARD
  grep -qE '^current_ahead'$'\t' <<< "$scan"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_pending.sh`
Expected: PASS — all four cases (`d`, `d2`, `d3`, `d4`) print no `FAIL` line, ending with
`  reconcile_pending ok`.

- [ ] **Step 5: Run the full existing suite to check for regressions**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: every `test_*.sh` reports `ok`, none report `FAILED`. (`test_promote_guard.sh` and
`test_sync_markers_e2e.sh` both call `dawn::reconcile_pending` with no argument indirectly through
`promote.sh`; this step confirms the default-arg behavior really is unchanged.)

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_reconcile_pending.sh
git commit -m "feat(ops): generalize dawn::reconcile_pending to accept an other ref"
```

---

### Task 2: Add `dawn::assert_backflow_not_pending`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh` (insert after the `dawn::backflow_pending` alias, i.e. after the current line 228)
- Test: `.claude/skills/_dawn-ops-lib/tests/test_assert_backflow_not_pending.sh` (new)

This is the shared "is backflow needed?" check both `dawn-promote` and `dawn-stage-push` will call.
It checks, in order: config-class drift against `current`, config-class drift against
`staging_remote`, then non-config drift against `staging_remote` (conflict, then clean-but-unfolded).

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/_dawn-ops-lib/tests/test_assert_backflow_not_pending.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# A) Clean: staging, current, and staging_remote all agree — must pass (rc 0).
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging
in_repo "$d" 'dawn::assert_backflow_not_pending'; rc=$?
assert_rc "$rc" 0 "clean state: guard passes"

# B) current-ahead config drift (a live edit on the published theme, never backflowed) => GUARD,
#    message names origin/current.
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
commit_on "$d2" current config/settings_data.json <<< '{"k":"live-edit"}'
git -C "$d2" checkout -q staging
out2=$(in_repo "$d2" 'dawn::assert_backflow_not_pending' 2>&1); rc2=$?
assert_rc "$rc2" 10 "current-ahead drift: GUARD"
assert_contains "$out2" "origin/current" "message names origin/current"
assert_contains "$out2" "backflow first" "message says backflow first"

# C) current-ahead-style config drift against origin/staging (a live edit on the PREVIEW theme,
#    never backflowed) => GUARD, message names origin/staging specifically (not origin/current).
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging_remote config/settings_data.json <<< '{"k":"preview-live-edit"}'
git -C "$d3" checkout -q staging
out3=$(in_repo "$d3" 'dawn::assert_backflow_not_pending' 2>&1); rc3=$?
assert_rc "$rc3" 10 "origin/staging-ahead config drift: GUARD"
assert_contains "$out3" "origin/staging" "message names origin/staging"
assert_not_contains "$out3" "origin/current has current-ahead" "does not mis-blame origin/current"

# D) origin/staging non-config drift that CONFLICTS with local staging (same locale line edited
#    both places) => GUARD, message says to resolve manually.
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
commit_on "$d4" staging_remote locales/nl.json <<< '{"a":"bot-value"}'
git -C "$d4" checkout -q staging
commit_on "$d4" staging locales/nl.json <<< '{"a":"staging-value"}'
out4=$(in_repo "$d4" 'dawn::assert_backflow_not_pending' 2>&1); rc4=$?
assert_rc "$rc4" 10 "conflicting non-config drift: GUARD"
assert_contains "$out4" "non-config file" "message calls out the non-config conflict"
assert_contains "$out4" "resolve manually" "message tells the operator to resolve manually"

# E) origin/staging non-config drift that folds CLEANLY (no conflict) but hasn't been folded yet
#    => still GUARD (a clean fold is still a fold dawn-backflow must perform first).
d5=$(dawn_test_repo)
commit_on "$d5" staging locales/nl.json <<'JSON'
{
  "a": "base-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "base-e"
}
JSON
git -C "$d5" checkout -q staging_remote; git -C "$d5" merge -q staging -m sync
commit_on "$d5" staging locales/nl.json <<'JSON'
{
  "a": "staging-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "base-e"
}
JSON
commit_on "$d5" staging_remote locales/nl.json <<'JSON'
{
  "a": "base-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "bot-e"
}
JSON
git -C "$d5" checkout -q staging
out5=$(in_repo "$d5" 'dawn::assert_backflow_not_pending' 2>&1); rc5=$?
assert_rc "$rc5" 10 "clean-but-unfolded non-config drift: still GUARD"
assert_contains "$out5" "non-config drift" "message calls out the unfolded non-config drift"

echo "  assert_backflow_not_pending ok"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_assert_backflow_not_pending.sh`
Expected: FAIL immediately on case A with something like
`.../test_assert_backflow_not_pending.sh: line N: dawn::assert_backflow_not_pending: command not found`
— the function doesn't exist yet.

- [ ] **Step 3: Implement the function**

In `.claude/skills/_dawn-ops-lib/dawn-ops.sh`, insert immediately after the `dawn::backflow_pending`
deprecated-alias line (currently line 228, `dawn::backflow_pending(){ dawn::reconcile_pending; }`):

```bash

# Combined guard: is there ANY unfolded drift — config-class or non-config — against `current` OR
# `staging_remote` that dawn-backflow would need to fold first? Both dawn-promote and
# dawn-stage-push require staging to already reflect everything live before pushing further.
dawn::assert_backflow_not_pending(){
  dawn::reconcile_pending && { echo "GUARD: backflow first — origin/current has current-ahead edits not yet folded into staging" >&2; return $DAWN_GUARD; }
  dawn::reconcile_pending "$(dawn::staging_remote_ref)" && { echo "GUARD: backflow first — origin/staging has current-ahead edits not yet folded into staging" >&2; return $DAWN_GUARD; }
  local nc; nc="$(dawn::nonconfig_drift_scan)"; local rc=$?
  [ "$rc" = "1" ] && { echo "GUARD: origin/staging conflicts with local staging (non-config file) — resolve manually and re-run dawn-backflow first" >&2; return $DAWN_GUARD; }
  [ -n "$nc" ] && { echo "GUARD: backflow first — origin/staging has non-config drift (e.g. locale files) not yet folded into staging" >&2; return $DAWN_GUARD; }
  return 0
}
```

`dawn::nonconfig_drift_scan` already exists (used by `dawn-backflow`) — reused as-is here, not
modified.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_assert_backflow_not_pending.sh`
Expected: PASS — all five cases pass, ending with `  assert_backflow_not_pending ok`.

- [ ] **Step 5: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all tests `ok`, none `FAILED`.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_assert_backflow_not_pending.sh
git commit -m "feat(ops): add dawn::assert_backflow_not_pending — checks both remotes"
```

---

### Task 3: Fix `dawn-promote`'s guard gap

**Files:**
- Modify: `.claude/skills/dawn-promote/promote.sh:8`

This is the actual bug fix from the design: promote today only checks `origin/current`. A live
edit made in the preview theme's admin editor, never backflowed, would silently survive an
untouched `dawn-promote` run and be destroyed by its force-push. No new test file is needed here —
`test_promote_guard.sh`'s existing case (a regression check that staging-ahead-only reaches the
confirm-live gate, not a false guard) must keep passing unmodified, and the new shared-fixture test
in Task 5 is what actually proves both remotes now block promote.

- [ ] **Step 1: Confirm the current (still-buggy) behavior with the existing test**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh`
Expected: PASS (this test doesn't yet exercise the `origin/staging` gap — that's exactly the bug;
it will get real coverage in Task 5). This step is just a baseline snapshot before changing
`promote.sh`.

- [ ] **Step 2: Replace the guard**

In `.claude/skills/dawn-promote/promote.sh`, replace line 8:

```bash
dawn::reconcile_pending && { echo "GUARD: backflow first — origin/current has current-ahead edits not yet folded into staging" >&2; exit $DAWN_GUARD; }
```

with:

```bash
dawn::assert_backflow_not_pending || exit $DAWN_GUARD
```

- [ ] **Step 3: Run `test_promote_guard.sh` again to confirm no regression**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh`
Expected: PASS — still `  promote_guard ok` and `  promote sync-marker ok`. The staging-ahead-only
case must still reach the confirm-live gate (rc 20), not the backflow guard, and the confirm-live
promote must still update both sync markers.

- [ ] **Step 4: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all tests `ok`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/dawn-promote/promote.sh
git commit -m "fix(ops): dawn-promote now guards against origin/staging drift too"
```

---

### Task 4: New `dawn-stage-push` skill

**Files:**
- Create: `.claude/skills/dawn-stage-push/stage-push.sh`
- Create: `.claude/skills/dawn-stage-push/SKILL.md`

- [ ] **Step 1: Create the directory and script**

```bash
mkdir -p .claude/skills/dawn-stage-push
```

Write `.claude/skills/dawn-stage-push/stage-push.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
PUSH="${DAWN_PUSH:-git push --force-with-lease}"
REMOTE="${DAWN_REMOTE:-origin}"

dawn::assert_backflow_not_pending || exit $DAWN_GUARD
dawn::assert_staging_clean || exit $DAWN_GUARD

if [ -n "${DAWN_STAGE_PUSH_REF:-}" ]; then      # test path: move local ref
  git update-ref "$DAWN_STAGE_PUSH_REF" staging
else                                             # real path: force-push staging onto origin/staging
  $PUSH "$REMOTE" staging || { echo "GUARD: push to $REMOTE staging failed; marker not updated" >&2; exit $DAWN_GUARD; }
fi
sha="$(git rev-parse staging)"
dawn::sync_marker_set staging-remote "$sha"
echo "Pushed staging -> origin/staging (preview theme). Test it there; run dawn-promote when ready to go live."
exit $DAWN_OK
```

Make it executable to match the sibling skill scripts:

```bash
chmod +x .claude/skills/dawn-stage-push/stage-push.sh
```

- [ ] **Step 2: Sanity-check it runs and guards correctly against a throwaway repo**

```bash
bash -c '
source .claude/skills/_dawn-ops-lib/tests/helpers.sh
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< "{\"k\":\"base\"}" "config snapshot"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging
out=$( cd "$d" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
       DAWN_STAGE_PUSH_REF=refs/heads/staging_remote DAWN_SYNC_MARKER_NOPUSH=1 \
       bash "$(pwd)/.claude/skills/dawn-stage-push/stage-push.sh" 2>&1 ); rc=$?
echo "rc=$rc"; echo "$out"
'
```

Expected: `rc=0`, output contains `Pushed staging -> origin/staging`. This is a manual smoke check,
not a unit test — Task 5 adds the real automated coverage as part of the shared-fixture chain.

- [ ] **Step 3: Write `SKILL.md`**

Write `.claude/skills/dawn-stage-push/SKILL.md`:

```markdown
---
name: dawn-stage-push
description: Push the reconciled staging branch to the preview theme (origin/staging) so it can be tested live before promote. Use when the user says stage-push, push to staging, push to preview, or test staging before going live.
---

## dawn-stage-push

This skill operates from a checked-out `ops` branch. See `../_dawn-ops-lib/conventions.md` for the
layer model (L0 vanilla / L1 customizations / L2 staging / current live) and the three-stage
release flow (`backflow → stage-push → promote`).

Pushes local `staging` to `origin/staging` (the preview theme) only. Nothing touches `current` —
this is not a live release, so there is no `--confirm-live` gate. It is still a force-push, so the
same drift guard and staging-cleanliness check that `dawn-promote` uses apply here first.

### Running

```bash
bash .claude/skills/dawn-stage-push/stage-push.sh
```

### Exit codes and required responses

**Exit 10 (GUARD)**

Either:
- **Backflow pending** — `origin/current` or `origin/staging` has edits not yet folded into
  staging (config-class or non-config drift). Tell the user:
  > "There are unsynced live edits that must be merged back into staging first. Run the
  > `dawn-backflow` skill, then retry stage-push."
- **Staging not clean** — `assert_staging_clean` failed (staging has diverged from
  `customizations`, or its tip isn't a config-snapshot commit). Report the guard message printed
  to stderr and follow its instructions (rebase onto `customizations`, or re-run `dawn-backflow`
  to recreate the snapshot).

Do NOT proceed until the guard condition is resolved — re-run `dawn-backflow` (or fix staging) and
retry `dawn-stage-push` from the top.

**Exit 0 (success)**

Tell the user:
> "staging has been pushed to origin/staging (the preview theme). Test it there, then run
> dawn-promote when you're ready to go live."

No live-confirm step is required here — nothing customer-facing changes until `dawn-promote` runs.
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/dawn-stage-push/stage-push.sh .claude/skills/dawn-stage-push/SKILL.md
git commit -m "feat(ops): add dawn-stage-push skill"
```

---

### Task 5: Shared-fixture chain test

**Files:**
- Create: `.claude/skills/_dawn-ops-lib/tests/test_stage_push_flow.sh`

One fixture, reused across every assertion (per the design's frugality note — no per-skill
duplicate tests). Exercises the full backflow → stage-push → promote chain end to end, proving the
guard is symmetric (checked on every call, not just once).

- [ ] **Step 1: Write the test**

Create `.claude/skills/_dawn-ops-lib/tests/test_stage_push_flow.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"
PROMOTE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-promote" && pwd)/promote.sh"
STAGE_PUSH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-stage-push" && pwd)/stage-push.sh"

bfrun(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
           DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" "${@:2}" ); }
promoterun(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
           DAWN_PROMOTE_REF=refs/heads/current DAWN_PUSH="git update-ref" \
           DAWN_SYNC_MARKER_NOPUSH=1 bash "$PROMOTE" "${@:2}" ); }
stagepushrun(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
           DAWN_STAGE_PUSH_REF=refs/heads/staging_remote DAWN_SYNC_MARKER_NOPUSH=1 \
           bash "$STAGE_PUSH" "${@:2}" ); }

d=$(dawn_test_repo)

# --- Setup: establish a shared baseline across staging / current / staging_remote ---
# Two independent keys: `k` carries the origin/staging-side drift (steps 1-3), `k2` carries the
# origin/current-side drift (steps 4-6). Keeping them independent matters: if step 4 edited `k`
# again, current's edit would land on a key staging had *already* moved (via the step-2/3 fold),
# producing a genuine 3-way collision rather than a clean current_ahead case — collisions are
# deliberately NOT counted as pending (see dawn::reconcile_pending's doc comment), so that would
# falsely look like the guard failing to block a "fresh" drift when it's actually correctly
# recognizing an already-resolved-by-staging value. `k2` stays untouched by every side until step
# 4, so its current-ahead classification there is unambiguous.
commit_on "$d" staging config/settings_data.json <<< '{"k":"base","k2":"base2"}' "config snapshot"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging

# 1) Drift on origin/staging (config-class): a live edit in the preview theme's admin editor,
#    never backflowed. Blocks BOTH dawn-stage-push and dawn-promote with the same GUARD shape.
commit_on "$d" staging_remote config/settings_data.json <<< '{"k":"preview-live-edit","k2":"base2"}'
git -C "$d" checkout -q staging

out1=$(stagepushrun "$d" 2>&1); assert_rc "$?" 10 "stage-push blocked: origin/staging has unfolded drift"
assert_contains "$out1" "backflow first" "stage-push guard message"
assert_contains "$out1" "origin/staging" "stage-push guard names origin/staging"

out1b=$(promoterun "$d" 2>&1); assert_rc "$?" 10 "promote blocked with the same drift"
assert_contains "$out1b" "backflow first" "promote guard message"
assert_contains "$out1b" "origin/staging" "promote guard names origin/staging"

# 2) dawn-backflow (--apply) clears it.
bfrun "$d" >/dev/null 2>&1; assert_rc "$?" 22 "backflow plan: needs approval to fold origin/staging edit"
bfrun "$d" --apply >/dev/null 2>&1; assert_rc "$?" 0 "backflow apply: folds origin/staging edit"

# 3) dawn-stage-push now succeeds; origin/staging (test double: staging_remote) and the
#    staging-remote marker both land on staging's tip.
git -C "$d" checkout -q staging
staging_sha=$(git -C "$d" rev-parse staging)
out3=$(stagepushrun "$d" 2>&1); assert_rc "$?" 0 "stage-push succeeds after backflow"
assert_contains "$out3" "Pushed staging" "stage-push success message"
assert_eq "$(git -C "$d" rev-parse staging_remote)" "$staging_sha" "stage-push moves the test-double remote to staging's tip"
assert_eq "$(git -C "$d" rev-parse refs/dawn-sync/staging-remote)" "$staging_sha" "stage-push updates the staging-remote marker"
# current's branch/marker must be untouched by stage-push — nothing about current changed.
assert_not_contains "$(git -C "$d" rev-parse current)" "$staging_sha" "stage-push never touches current"

# 4) A fresh drift lands on origin/current (on the untouched k2 key) — blocks dawn-promote (proving
#    the guard is symmetric, not just checked once and forgotten). Same guard function also blocks
#    stage-push. k reverts to "base" on current here (matching the sync marker's base value for k),
#    so k classifies as staging_ahead (staging's post-fold value differs from base, current's
#    doesn't) — not a collision, not current_ahead — leaving k2 as the only current_ahead leaf and
#    keeping this an unambiguous case.
commit_on "$d" current config/settings_data.json <<< '{"k":"base","k2":"live-edit-on-current"}'
git -C "$d" checkout -q staging

out4=$(promoterun "$d" 2>&1); assert_rc "$?" 10 "fresh origin/current drift blocks promote"
assert_contains "$out4" "origin/current" "promote guard names origin/current for this fresh drift"

out4b=$(stagepushrun "$d" 2>&1); assert_rc "$?" 10 "fresh origin/current drift also blocks stage-push"
assert_contains "$out4b" "origin/current" "stage-push guard names origin/current too"

# 5) dawn-backflow clears it again.
bfrun "$d" >/dev/null 2>&1; assert_rc "$?" 22 "backflow plan: needs approval to fold current's live edit"
bfrun "$d" --apply >/dev/null 2>&1; assert_rc "$?" 0 "backflow apply: folds current's live edit"

# 6) dawn-promote --confirm-live succeeds.
git -C "$d" checkout -q staging
promoterun "$d" --confirm-live >/dev/null 2>&1; assert_rc "$?" 0 "promote succeeds after final backflow"
final_sha=$(git -C "$d" rev-parse staging)
assert_eq "$(git -C "$d" rev-parse current)" "$final_sha" "promote lands current on staging's tip"

echo "  stage_push_flow ok"
```

- [ ] **Step 2: Run test to verify it fails first**

Before Tasks 1-4 are applied, this test cannot pass (`dawn::assert_backflow_not_pending` doesn't
exist yet, and `dawn-stage-push/stage-push.sh` doesn't exist yet). Since this plan is executed
task-by-task in order, by the time you reach this task Tasks 1-4 are already done — so instead of
proving failure against old code, prove it fails against a deliberately broken guard as a sanity
check that the test actually exercises the guard:

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_stage_push_flow.sh`
Expected at this point (Tasks 1-4 already applied): PASS. If it fails, do NOT weaken the test —
debug whether Task 1, 2, 3, or 4 was applied incorrectly (see Step 3).

- [ ] **Step 3: If it fails, debug against the real implementation**

Common causes if a case fails:
- `out1`/`out1b` don't contain "origin/staging" → Task 2's `dawn::assert_backflow_not_pending` or
  Task 3's `promote.sh` edit is missing or wrong.
- Case 2's rc isn't 22 → an unrelated collision or classification is being triggered; verify the
  fixture setup lines match exactly (this mirrors `test_sync_markers_e2e.sh`'s proven fixture
  shape).
- Case 3's `staging_remote` ref doesn't move → `stage-push.sh`'s `DAWN_STAGE_PUSH_REF` handling is
  missing (Task 4).
- Case 4's stage-push isn't blocked by `origin/current` drift → `dawn::assert_backflow_not_pending`
  is missing its first check (`dawn::reconcile_pending` with no arg).

- [ ] **Step 4: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: every test `ok`, none `FAILED`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/tests/test_stage_push_flow.sh
git commit -m "test(ops): end-to-end backflow -> stage-push -> promote drift-guard chain"
```

---

### Task 6: Update `conventions.md`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/conventions.md`

- [ ] **Step 1: Update the skill count/list in the header**

Replace line 3-4:

```markdown
Single source of truth for all five skills (`dawn-backflow`, `dawn-promote`, `dawn-upgrade`,
`dawn-harvest`, `dawn-ship`). Full depth: runbook at
```

with:

```markdown
Single source of truth for all six skills (`dawn-backflow`, `dawn-promote`, `dawn-stage-push`,
`dawn-upgrade`, `dawn-harvest`, `dawn-ship`). Full depth: runbook at
```

- [ ] **Step 2: Expand §3a into a three-mode table**

Replace the `## 3a. Two promote modes` section (current lines 65-73):

```markdown
## 3a. Two promote modes

| Mode | Skill | What it does | When to use |
|---|---|---|---|
| **Ship** (incremental) | `dawn-ship` | Cherry-picks a classified commit from `customizations` onto `current`. Append-only. Classifier gates: ALL_INERT → light confirm; HAS_ACTIVE → full confirm + smoke test; NEEDS_JUDGMENT → stop. | Ship dormant building blocks early (to unblock shop-global activation like a page binding), or ship tested-active changes incrementally. |
| **Promote** (release) | `dawn-promote` | Force-pushes `staging` onto `current` (the authoritative reset). Yields `current == staging`. Guarded: staging must be clean. | Full release after rebuild, backflow, and testing. |

The two modes are complementary: `dawn-ship` ships pieces incrementally between releases; `dawn-promote` resets `current` to the authoritative tested `staging` at each release, reconciling any divergence.
```

with:

```markdown
## 3a. Three release modes

| Mode | Skill | What it does | When to use |
|---|---|---|---|
| **Ship** (incremental) | `dawn-ship` | Cherry-picks a classified commit from `customizations` onto `current`. Append-only. Classifier gates: ALL_INERT → light confirm; HAS_ACTIVE → full confirm + smoke test; NEEDS_JUDGMENT → stop. | Ship dormant building blocks early (to unblock shop-global activation like a page binding), or ship tested-active changes incrementally. |
| **Stage-push** (preview) | `dawn-stage-push` | Force-pushes `staging` onto `origin/staging` only (the preview theme). Nothing touches `current`; no live-confirm gate. Guarded identically to promote's first two checks. | After `dawn-backflow`, before `dawn-promote` — test the reconciled staging on the preview theme before it goes live. |
| **Promote** (release) | `dawn-promote` | Force-pushes `staging` onto `current` (the authoritative reset). Yields `current == staging`. Guarded: staging must be clean. | Full release after rebuild, backflow, and testing. |

The three modes are complementary: `dawn-ship` ships pieces incrementally between releases;
`dawn-stage-push` lets you test a fully reconciled `staging` on the preview theme before it's live;
`dawn-promote` resets `current` to the authoritative tested `staging` at each release, reconciling
any divergence. Standard release order: `dawn-backflow` → `dawn-stage-push` → `dawn-promote`.

**The drift guard covers both remotes.** `dawn::assert_backflow_not_pending` (used by both
`dawn-stage-push` and `dawn-promote`) refuses to run if `origin/current` OR `origin/staging` has
config-class or non-config drift dawn-backflow hasn't folded into staging yet — a live edit made in
either theme's admin editor, never backflowed, must never survive a stage-push or promote run.
```

- [ ] **Step 2: Verify no other section references "Two promote modes" or "five skills"**

Run: `grep -rn "Two promote modes\|five skills" .claude/ docs/`
Expected: no matches remain (aside from this plan file and the design spec, which are historical
records and are not edited).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/conventions.md
git commit -m "docs(ops): conventions — add dawn-stage-push, document dual-remote drift guard"
```

---

### Task 7: Update the runbook

**Files:**
- Modify: `docs/superpowers/runbook/dawn-dev-and-release.md`

- [ ] **Step 1: Add a `dawn-stage-push` row to the skill reference table**

In the table under `## Skill reference` (lines 23-30), insert a new row between `dawn-backflow` and
`dawn-promote`:

```markdown
| `dawn-stage-push` | Force-pushes `staging` → `origin/staging` (the preview theme) only. No live-confirm gate — nothing customer-facing changes. Guarded identically to promote's first two checks. | After backflow, before promote — test the reconciled staging on the preview theme before it goes live |
```

- [ ] **Step 2: Update the "Release" workflow step**

Replace the `### 5. Release` section (current lines 97-116):

```markdown
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
```

with:

```markdown
### 5. Release

When the feature is complete and tested:

```bash
# a) Capture any live admin edits back into staging
bash .claude/skills/dawn-backflow/backflow.sh

# b) Push the reconciled staging to the preview theme and test it there
bash .claude/skills/dawn-stage-push/stage-push.sh

# c) Verify staging is clean (all harvested, config snapshot at tip)
# dawn-promote will check this automatically; if it fails, rebase staging onto customizations
# and recreate the config snapshot.

# d) Promote
bash .claude/skills/dawn-promote/promote.sh
# Agent will stop at the live-confirm gate and show you the full diff.
# After reviewing, confirm with --confirm-live.
bash .claude/skills/dawn-promote/promote.sh --confirm-live
```

`dawn-stage-push` and `dawn-promote` share the same drift guard: if either `origin/current` or
`origin/staging` has a live edit dawn-backflow hasn't folded in yet, both steps refuse to run —
re-run `dawn-backflow` first.

After promote, `current == staging` exactly. Any interim `dawn-ship` cherry-picks are superseded.
```

- [ ] **Step 3: Update the decision tree**

Replace this line in `## Decision tree` (current lines 126-127):

```markdown
Want to publish a full tested release?
  → dawn-backflow → dawn-promote (promote guards staging cleanliness automatically)
```

with:

```markdown
Want to publish a full tested release?
  → dawn-backflow → dawn-stage-push (test on the preview theme) → dawn-promote (promote guards staging cleanliness automatically)
```

- [ ] **Step 4: Update rule 1**

Replace this line in `## Rules (never break these)` (current line 143):

```markdown
1. **Never force-push `staging` or `current`** except the guarded reset in `dawn-promote`.
```

with:

```markdown
1. **Never force-push `staging` or `current`** except the guarded resets in `dawn-stage-push`
   (`staging` → `origin/staging` only) and `dawn-promote` (`staging` → `current`).
```

- [ ] **Step 5: Proofread the whole file**

Run: `cat docs/superpowers/runbook/dawn-dev-and-release.md`
Confirm: the branch-roles diagram, skill table, workflow steps 1-5, decision tree, and rules list
all read coherently end to end with `dawn-stage-push` now included in the right places, and no
leftover references to the old two-step "backflow → promote" release order remain.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/runbook/dawn-dev-and-release.md
git commit -m "docs(ops): runbook — document backflow -> stage-push -> promote release order"
```

---

## Final verification

- [ ] Run the entire test suite one more time end to end:

```bash
bash .claude/skills/_dawn-ops-lib/tests/run.sh
```

Expected: every `test_*.sh` file reports `ok`; the script's own exit code is `0`.

- [ ] Confirm the full set of changed/created files matches the File Structure table at the top of
  this plan exactly (`git log --stat` across the commits from this plan, or `git diff
  <first-commit>^..HEAD --stat`).

- [ ] Do NOT run any real `git push`. This plan's scope ends at local commits on `ops`; pushing is
  a separate, explicitly human-confirmed step outside this plan.
