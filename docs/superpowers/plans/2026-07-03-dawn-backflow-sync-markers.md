# Dawn-ops sync markers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `git merge-base`-inferred "base" in the config reconciler with explicit, pushed marker refs (`refs/dawn-sync/current`, `refs/dawn-sync/staging-remote`) that `dawn-backflow` and `dawn-promote` keep current, so a genuine live edit is never misclassified as "no change" just because backflow's own history-collapsing behavior made git ancestry an unreliable reference point.

**Architecture:** Three small library primitives (`dawn::sync_marker_get`/`set`/`_sync_marker_name`) in `dawn-ops.sh`. `dawn::reconcile_scan`'s existing `base` computation tries the relevant marker first, falling back to today's `git merge-base` only when no marker exists yet (first run / bootstrap). `backflow.sh` fetches both marker refs up front and writes them back (pushed) on every successful `--apply` completion. `promote.sh` writes both markers (pushed) after its force-pushes to `current` and `origin/staging` succeed, since promote makes all three branches agree at once.

**Tech Stack:** bash, git (plain refs via `git update-ref`/`git push <ref>:<ref>`, no new git features required). Existing test harness: `.claude/skills/_dawn-ops-lib/tests/*.sh`.

**Design doc:** `docs/superpowers/specs/2026-07-03-dawn-backflow-sync-markers-design.md` — read §2 and §3 before starting; they define the exact update/read triggers this plan implements.

---

## File structure

| File | Role |
|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | Add `dawn::_sync_marker_name`, `dawn::sync_marker_get`, `dawn::sync_marker_set`. Change `dawn::reconcile_scan`'s `base` computation to try the marker first, merge-base as fallback. |
| `.claude/skills/_dawn-ops-lib/tests/helpers.sh` | `in_repo` gains `DAWN_SYNC_MARKER_NOPUSH=1` in its env (test fixtures have no real `origin` remote to push to). |
| `.claude/skills/_dawn-ops-lib/tests/test_sync_markers.sh` (new) | Covers the 3 new primitives directly. |
| `.claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh` | Extended with marker-present / marker-absent / stale-ancestry-doesn't-matter cases (the direct regression test for today's incident). |
| `.claude/skills/dawn-backflow/backflow.sh` | Fetch both marker refs up front; capture the fetched SHAs; write+push both markers (gated on `--apply`) at both `exit $DAWN_OK` sites. |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh` | Extended: apply run updates both markers; plan-mode-only run does not. |
| `.claude/skills/dawn-promote/promote.sh` | After both force-pushes succeed, write+push both markers to the new shared (staging's) SHA. |
| `.claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh` | Extended: a real (confirm-live) promote updates both markers. |
| `.claude/skills/_dawn-ops-lib/tests/test_sync_markers_e2e.sh` (new) | The end-to-end "post-promote regression" scenario from the design doc's discussion: a staging-ahead leaf gets promoted everywhere, a later live edit to that same leaf on `current` folds cleanly instead of colliding. |
| `.claude/skills/_dawn-ops-lib/conventions.md` | Document the marker refs and who's responsible for keeping them current. |

---

## Task 1: Sync-marker primitives

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh` (add before `dawn::reconcile_scan`, currently starting around line 143)
- Modify: `.claude/skills/_dawn-ops-lib/tests/helpers.sh` (`in_repo`)
- Test: `.claude/skills/_dawn-ops-lib/tests/test_sync_markers.sh` (new)

- [ ] **Step 1: Add the test seam to `in_repo`**

In `.claude/skills/_dawn-ops-lib/tests/helpers.sh`, change:

```bash
in_repo(){
  local d="$1"; shift
  ( cd "$d" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
    bash -c "source '$DAWN_LIB_SRC'; $*" )
}
```

to:

```bash
in_repo(){
  local d="$1"; shift
  ( cd "$d" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
    DAWN_SYNC_MARKER_NOPUSH=1 bash -c "source '$DAWN_LIB_SRC'; $*" )
}
```

Test fixture repos (`dawn_test_repo()`) have no real `origin` remote to push a ref to — `DAWN_SYNC_MARKER_NOPUSH=1` skips the push step of `dawn::sync_marker_set` (added in Step 3 below) so tests only exercise the local `git update-ref` half, which is exactly what `dawn::sync_marker_get` reads back from anyway.

- [ ] **Step 2: Write the failing test**

Create `.claude/skills/_dawn-ops-lib/tests/test_sync_markers.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

d=$(dawn_test_repo)

# get on an unset marker returns empty, not an error
out=$(in_repo "$d" 'dawn::sync_marker_get current')
assert_eq "$out" "" "unset marker reads as empty"

# set + get round-trips
sha=$(git -C "$d" rev-parse staging)
in_repo "$d" "dawn::sync_marker_set current $sha"
out=$(in_repo "$d" 'dawn::sync_marker_get current')
assert_eq "$out" "$sha" "marker round-trips"

# the local ref really exists under refs/dawn-sync/
ref_sha=$(git -C "$d" rev-parse refs/dawn-sync/current)
assert_eq "$ref_sha" "$sha" "marker is a real ref under refs/dawn-sync/"

# set with an empty sha is a no-op (defensive — callers must not clobber with garbage)
in_repo "$d" 'dawn::sync_marker_set current ""'
out=$(in_repo "$d" 'dawn::sync_marker_get current')
assert_eq "$out" "$sha" "empty-sha set is a no-op, marker unchanged"

# _sync_marker_name maps the two known "other" refs to their logical names
cur_name=$(in_repo "$d" 'dawn::_sync_marker_name "$(dawn::current_ref)"')
assert_eq "$cur_name" "current" "current_ref maps to the 'current' marker"
sr_name=$(in_repo "$d" 'dawn::_sync_marker_name "$(dawn::staging_remote_ref)"')
assert_eq "$sr_name" "staging-remote" "staging_remote_ref maps to the 'staging-remote' marker"
unknown_name=$(in_repo "$d" 'dawn::_sync_marker_name some-unrelated-ref')
assert_eq "$unknown_name" "" "an unrecognized ref maps to no marker"

echo "  sync_markers ok"
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_sync_markers.sh`
Expected: FAIL — `dawn::sync_marker_get: command not found`

- [ ] **Step 4: Add the three functions**

In `.claude/skills/_dawn-ops-lib/dawn-ops.sh`, immediately before `dawn::reconcile_scan` (before the
comment block starting `# 3-way classify every leaf...`, currently around line 134):

```bash
# Map a reconcile "other" ref value to its logical sync-marker name ("current" or
# "staging-remote"), or empty if it matches neither resolver's current output. Used so
# dawn::reconcile_scan can look up the right persisted marker without every caller having to
# pass a second, easy-to-get-out-of-sync parameter.
dawn::_sync_marker_name(){
  local other="$1"
  [ "$other" = "$(dawn::current_ref)" ] && { echo current; return 0; }
  [ "$other" = "$(dawn::staging_remote_ref)" ] && { echo staging-remote; return 0; }
  echo ""
}

# Read the commit refs/dawn-sync/<name> points at, or empty if the marker doesn't exist yet.
dawn::sync_marker_get(){
  local name="$1"
  git rev-parse --verify -q "refs/dawn-sync/$name" 2>/dev/null || true
}

# Point refs/dawn-sync/<name> at <sha> and push it (a plain ref, not a branch — this is what
# keeps that specific commit's content reachable and nameable after the branch it came from has
# moved on). A ref, not a text file, because only a ref actually protects the commit from
# garbage collection. Test seam: DAWN_SYNC_MARKER_NOPUSH — test fixtures have no real "origin"
# to push to; dawn::sync_marker_get reads the local ref regardless, so skipping the push is safe
# for tests. A missing/empty <sha> is a no-op (never clobber a marker with garbage).
dawn::sync_marker_set(){
  local name="$1" sha="$2"
  [ -z "$sha" ] && return 0
  git update-ref "refs/dawn-sync/$name" "$sha"
  [ -n "${DAWN_SYNC_MARKER_NOPUSH:-}" ] && return 0
  git push -q origin "refs/dawn-sync/$name:refs/dawn-sync/$name" 2>/dev/null || true
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_sync_markers.sh`
Expected: PASS (`sync_markers ok`)

- [ ] **Step 6: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all pass (these functions have no callers yet, so nothing else should be affected).

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/helpers.sh .claude/skills/_dawn-ops-lib/tests/test_sync_markers.sh
git commit -m "feat(ops): add sync-marker primitives (get/set/name-mapping)"
```

---

## Task 2: Wire markers into `dawn::reconcile_scan`'s base computation

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh:143-171` (`dawn::reconcile_scan`)
- Modify: `.claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh`

- [ ] **Step 1: Write the failing tests**

Append to `.claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh`:

```bash

# --- sync-marker base (replaces merge-base) ---

# No marker set -> falls back to merge-base, exactly today's behavior.
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"base"}'
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
commit_on "$d3" current config/settings_data.json <<< '{"k":"live"}'
scan=$(in_repo "$d3" 'dawn::reconcile_scan')
assert_contains "$scan" 'current_ahead	config/settings_data.json	["k"]	"base"	"base"	"live"' "no marker: falls back to merge-base"

# Marker set, remote hasn't moved since -> no drift, even if git ancestry would say otherwise.
# This directly reproduces the 2026-07-03 incident. The key mechanic: staging's collapse must
# ACTUALLY discard an intermediate commit from its own ancestry (via a real `reset --soft` back
# to a shared floor, exactly mirroring dawn-backflow's real collapse), not just add commits on
# top of each other — otherwise merge-base and the marker trivially agree and the test proves
# nothing. (An earlier draft of this fixture made exactly that mistake — see the implementer's
# BLOCKED report on this task for the full trace of why a straight-line-history fixture doesn't
# reproduce the bug.)
d4=$(dawn_test_repo)
# floor: the one commit BOTH staging's collapsed tip and staging_remote's chain will still share.
commit_on "$d4" staging config/settings_data.json <<< '{"padding":36}' "floor"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
floor_sha=$(git -C "$d4" rev-parse staging)

# origin/staging independently syncs to padding:0 at some point (e.g. an earlier live-editor
# fold) — this is the state a prior successful backflow run would have frozen as the marker.
commit_on "$d4" staging_remote config/settings_data.json <<< '{"padding":0}' "staging_remote synced to 0"
sr_synced_sha=$(git -C "$d4" rev-parse staging_remote)
in_repo "$d4" "dawn::sync_marker_set staging-remote $sr_synced_sha"

# staging separately collapses to padding:0 too, but via ITS OWN chain off floor: commit an
# intermediate, then reset --soft back to floor and recommit — mirroring dawn-backflow's real
# collapse mechanism. staging's new tip shares history with floor only, NOT with sr_synced_sha.
git -C "$d4" checkout -q staging
commit_on "$d4" staging config/settings_data.json <<< '{"padding":0}' "intermediate (later discarded)"
git -C "$d4" reset -q --soft "$floor_sha"
git -C "$d4" commit -q -m "config snapshot (collapsed)"

# now the operator reverts the live preview theme back to padding:36 — a new commit on TOP of
# sr_synced_sha (origin/staging's real history), unrelated to staging's discarded intermediate.
git -C "$d4" checkout -q staging_remote
commit_on "$d4" staging_remote config/settings_data.json <<< '{"padding":36}' "operator reverts on live preview theme"
git -C "$d4" checkout -q staging

# Sanity-check the fixture's own precondition: naive merge-base must have regressed all the way
# to floor (padding:36) — that's exactly what would make the old code misclassify the operator's
# revert as "staging_ahead" (silently ignored) instead of a real change.
naive_base=$(git -C "$d4" merge-base staging staging_remote)
assert_eq "$naive_base" "$floor_sha" "sanity: naive merge-base regresses to floor, reproducing the bug's precondition"

other=$(in_repo "$d4" 'dawn::staging_remote_ref')
scan4=$(in_repo "$d4" "dawn::reconcile_scan $other")
assert_contains "$scan4" 'current_ahead	config/settings_data.json	["padding"]	0	0	36' "marker (not stale ancestry) correctly detects the revert as a real change"
assert_not_contains "$scan4" 'staging_ahead	config/settings_data.json	["padding"]' "must NOT be misclassified as staging_ahead (the old bug)"

echo "  reconcile_scan sync-marker ok"
```

- [ ] **Step 2: Run it to verify the second case fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh`
Expected: the first new assertion (no-marker fallback) passes (current behavior already does
this); the second (`scan4` / "marker correctly detects the revert") FAILS, since
`dawn::reconcile_scan` doesn't consult the marker yet — it'll report no drift instead, exactly
reproducing today's incident.

- [ ] **Step 3: Change `dawn::reconcile_scan`'s base computation**

In `.claude/skills/_dawn-ops-lib/dawn-ops.sh`, replace:

```bash
dawn::reconcile_scan(){
  local other="${1:-$(dawn::current_ref)}"
  local base f
  base="$(git merge-base staging "$other" 2>/dev/null)" \
    || { echo "GUARD: no merge-base for staging vs $other" >&2; return $DAWN_GUARD; }
  [ -z "$base" ] && { echo "GUARD: no merge-base for staging vs $other" >&2; return $DAWN_GUARD; }
```

with:

```bash
dawn::reconcile_scan(){
  local other="${1:-$(dawn::current_ref)}"
  local base f marker
  marker="$(dawn::_sync_marker_name "$other")"
  base=""
  [ -n "$marker" ] && base="$(dawn::sync_marker_get "$marker")"
  if [ -z "$base" ]; then
    base="$(git merge-base staging "$other" 2>/dev/null)" \
      || { echo "GUARD: no merge-base for staging vs $other" >&2; return $DAWN_GUARD; }
  fi
  [ -z "$base" ] && { echo "GUARD: no merge-base for staging vs $other" >&2; return $DAWN_GUARD; }
```

The rest of the function (the `while` loop reading `dawn::config_targets "$other"` and the awk
classification) is unchanged — it already just uses `$base` as a value, indifferent to where it
came from.

Also update the function's doc comment. Change:

```bash
# 3-way classify every leaf of every reconcile target against <other> (default dawn::current_ref).
```

to:

```bash
# 3-way classify every leaf of every reconcile target against <other> (default dawn::current_ref).
# "base" is read from the persisted sync marker for <other> (see dawn::sync_marker_get) when one
# exists, falling back to git merge-base only on the very first run before a marker is
# established. The marker exists specifically because git ancestry is NOT a reliable "last
# agreed" reference here: dawn-backflow collapses staging's own history on every run, which
# makes a merge-base search regress further into the past each time, potentially past several
# already-reconciled changes (see docs/superpowers/specs/2026-07-03-dawn-backflow-sync-markers-design.md).
```

- [ ] **Step 4: Run the tests to verify both pass**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh`
Expected: PASS, including `reconcile_scan sync-marker ok`.

- [ ] **Step 5: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all pass — every existing test runs with no marker set (fresh fixtures each time), so
they all exercise the bootstrap/fallback path and should be completely unaffected.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh .claude/skills/_dawn-ops-lib/tests/test_reconcile_scan.sh
git commit -m "fix(ops): reconcile_scan reads base from the sync marker, not merge-base"
```

---

## Task 3: `backflow.sh` fetches and writes the markers

**Files:**
- Modify: `.claude/skills/dawn-backflow/backflow.sh`
- Modify: `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh`

- [ ] **Step 1: Read the current file**

Read `.claude/skills/dawn-backflow/backflow.sh` in full to confirm its current exact shape (it was
last rewritten in the previous plan — `feat(ops): backflow folds origin/staging drift + gates on a
plan/approve report`, then had one message-wording fix on top). Confirm the two `exit $DAWN_OK`
sites: one in the "nothing folded" fast path (right after the `if [ "${#report_staging_remote[@]}"
... ]` check), one at the very end of the file (after the `--apply` branch's `echo "Backflow
complete..."`).

- [ ] **Step 2: Add the marker fetch + SHA capture near the top**

Find:

```bash
git fetch origin current --quiet 2>/dev/null || true
git fetch origin staging --quiet 2>/dev/null || true
base="$(git merge-base staging "$cur" 2>/dev/null)" \
  || { echo "GUARD: no merge-base staging vs $cur" >&2; exit $DAWN_GUARD; }
```

Replace with:

```bash
git fetch origin current --quiet 2>/dev/null || true
git fetch origin staging --quiet 2>/dev/null || true
git fetch origin refs/dawn-sync/current:refs/dawn-sync/current --quiet 2>/dev/null || true
git fetch origin refs/dawn-sync/staging-remote:refs/dawn-sync/staging-remote --quiet 2>/dev/null || true
base="$(git merge-base staging "$cur" 2>/dev/null)" \
  || { echo "GUARD: no merge-base staging vs $cur" >&2; exit $DAWN_GUARD; }
cur_sha="$(git rev-parse "$cur" 2>/dev/null || true)"
staging_remote_sha="$(git rev-parse "$staging_remote" 2>/dev/null || true)"
```

(`$base` here is `backflow.sh`'s own separate `base` variable, used only for the non-config
partition in Step 1 further down — unrelated to `dawn::reconcile_scan`'s internal `base`, and not
touched by this plan. `$cur_sha`/`$staging_remote_sha` capture the exact commits fetched this run,
so the eventual marker write reflects precisely what was reconciled against, not whatever the refs
might resolve to later if something else moves them mid-run.)

- [ ] **Step 3: Add a marker-sync helper and call it at both success exits**

Right after the `_dawn_bf_abort` helper definition:

```bash
_dawn_bf_abort(){ git reset -q --hard "$orig_sha" 2>/dev/null || true; exit "$1"; }
```

add:

```bash
# Only a completed --apply run counts as "fully reconciled" — advance both markers to the exact
# commits fetched this run, even if nothing needed folding (a clean "nothing to do" verdict is
# still a complete, correct pass over the remote's current state).
_dawn_bf_sync_markers(){
  [ "$APPLY" = "1" ] || return 0
  dawn::sync_marker_set current "$cur_sha"
  dawn::sync_marker_set staging-remote "$staging_remote_sha"
}
```

Then find the "nothing folded" fast path:

```bash
if [ "${#report_staging_remote[@]}" = "0" ] && [ "${#report_current[@]}" = "0" ]; then
  if git diff --quiet "$floor" HEAD -- .; then
    echo "Nothing to reconcile; staging config collapsed to one empty snapshot at the tip."
  else
    echo "Backflow complete: staging config collapsed into one snapshot at the tip."
  fi
  exit $DAWN_OK
fi
```

and add the sync call right before `exit $DAWN_OK`:

```bash
if [ "${#report_staging_remote[@]}" = "0" ] && [ "${#report_current[@]}" = "0" ]; then
  if git diff --quiet "$floor" HEAD -- .; then
    echo "Nothing to reconcile; staging config collapsed to one empty snapshot at the tip."
  else
    echo "Backflow complete: staging config collapsed into one snapshot at the tip."
  fi
  _dawn_bf_sync_markers
  exit $DAWN_OK
fi
```

Finally, find the very last lines of the file:

```bash
echo "Backflow complete: staging config collapsed into one snapshot at the tip."
exit $DAWN_OK
```

and change to:

```bash
echo "Backflow complete: staging config collapsed into one snapshot at the tip."
_dawn_bf_sync_markers
exit $DAWN_OK
```

(This final site is only ever reached when `$APPLY = 1` already — the plan-mode branch above it
always ends in `_dawn_bf_abort $DAWN_STOP_APPROVAL`, which exits before reaching here. The
`_dawn_bf_sync_markers` guard is defensive/self-documenting rather than load-bearing at this
specific call site, but keeping the same guarded helper at both sites means the "only on apply"
rule lives in exactly one place.)

- [ ] **Step 4: Manually sanity-check with a scratch fixture**

Per the SAFETY PROTOCOL used throughout this whole effort: build a fixture with `mktemp -d`, run
`backflow.sh` via a subshell `cd` with `DAWN_CURRENT_REF`/`DAWN_STAGING_REMOTE_REF` set, confirm:
(a) a plan-mode run (no `--apply`) does NOT create `refs/dawn-sync/*` in the fixture repo; (b) an
`--apply` run does. `bash -n .claude/skills/dawn-backflow/backflow.sh` for a syntax check first.

- [ ] **Step 5: Write the test additions**

Append to `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh`:

```bash

# --- sync markers ---

# --apply updates both markers to the fetched SHAs; plan-mode does not.
d6=$(dawn_test_repo)
commit_on "$d6" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d6" checkout -q current; git -C "$d6" merge -q staging -m sync
commit_on "$d6" current config/settings_data.json <<< '{"k":"live"}'
git -C "$d6" checkout -q staging_remote; git -C "$d6" merge -q staging -m sync
git -C "$d6" checkout -q staging
cur_sha_expected=$(git -C "$d6" rev-parse current)
sr_sha_expected=$(git -C "$d6" rev-parse staging_remote)

( cd "$d6" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
  DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" ) >/dev/null; plan_rc=$?
assert_rc "$plan_rc" 22 "plan-mode stops for approval"
marker_after_plan=$(git -C "$d6" rev-parse --verify -q refs/dawn-sync/current 2>/dev/null || echo "MISSING")
assert_eq "$marker_after_plan" "MISSING" "plan-mode does not write the marker"

( cd "$d6" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
  DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" --apply ) >/dev/null; apply_rc=$?
assert_rc "$apply_rc" 0 "apply ok"
assert_eq "$(git -C "$d6" rev-parse refs/dawn-sync/current)" "$cur_sha_expected" "apply writes the current marker"
assert_eq "$(git -C "$d6" rev-parse refs/dawn-sync/staging-remote)" "$sr_sha_expected" "apply writes the staging-remote marker"

# a "nothing to fold" --apply run still advances the markers
( cd "$d6" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
  DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" --apply ) >/dev/null; noop_apply_rc=$?
assert_rc "$noop_apply_rc" 0 "second (no-op) apply ok"
assert_eq "$(git -C "$d6" rev-parse refs/dawn-sync/current)" "$cur_sha_expected" "marker still correct after a no-op apply"

echo "  backflow sync-marker ok"
```

- [ ] **Step 6: Run it, debug if needed**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_backflow.sh`
Expected: PASS. If it fails, check the exact placement of `_dawn_bf_sync_markers` calls against
Step 3 — a common mistake is placing the call after `exit` (dead code) rather than before.

- [ ] **Step 7: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add .claude/skills/dawn-backflow/backflow.sh .claude/skills/_dawn-ops-lib/tests/test_backflow.sh
git commit -m "feat(ops): backflow fetches and writes the sync markers on successful apply"
```

---

## Task 4: `promote.sh` writes the markers after a successful promote

**Files:**
- Modify: `.claude/skills/dawn-promote/promote.sh`
- Modify: `.claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh`

- [ ] **Step 1: Write the failing test**

Append to `.claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh`:

```bash

# A real (confirm-live) promote updates both sync markers to staging's new tip.
d2=$(dawn_test_repo)
commit_on "$d2" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base"}}}}' "config snapshot"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging
staging_sha=$(git -C "$d2" rev-parse staging)

out2=$( cd "$d2" && DAWN_CURRENT_REF=current DAWN_PROMOTE_REF=refs/heads/current \
        DAWN_PUSH="git update-ref" DAWN_SYNC_MARKER_NOPUSH=1 \
        bash "$PROMOTE" --confirm-live 2>&1 ); rc2=$?
assert_rc "$rc2" 0 "confirm-live promote ok"
assert_eq "$(git -C "$d2" rev-parse refs/dawn-sync/current)" "$staging_sha" "promote writes the current marker to staging's tip"
assert_eq "$(git -C "$d2" rev-parse refs/dawn-sync/staging-remote)" "$staging_sha" "promote writes the staging-remote marker to staging's tip"

echo "  promote sync-marker ok"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh`
Expected: FAIL — `refs/dawn-sync/current` doesn't exist (`git rev-parse` errors).

- [ ] **Step 3: Add the marker write to `promote.sh`**

In `.claude/skills/dawn-promote/promote.sh`, find:

```bash
if [ -n "${DAWN_PROMOTE_REF:-}" ]; then         # test path: move local ref
  git update-ref "$DAWN_PROMOTE_REF" staging; git update-ref refs/remotes/origin/current staging
else                                            # real path: force-push staging onto current
  $PUSH "$REMOTE" staging
  $PUSH "$REMOTE" staging:current
fi
echo "Promoted staging -> current."
exit $DAWN_OK
```

Replace with:

```bash
if [ -n "${DAWN_PROMOTE_REF:-}" ]; then         # test path: move local ref
  git update-ref "$DAWN_PROMOTE_REF" staging; git update-ref refs/remotes/origin/current staging
else                                            # real path: force-push staging onto current
  $PUSH "$REMOTE" staging || { echo "GUARD: push to $REMOTE staging failed; markers not updated" >&2; exit $DAWN_GUARD; }
  $PUSH "$REMOTE" staging:current || { echo "GUARD: push to $REMOTE staging:current failed; markers not updated" >&2; exit $DAWN_GUARD; }
fi
# After promote, staging / origin/staging / origin/current are all identical — both sync markers
# (used by dawn::reconcile_scan's base computation) must reflect that new shared state, or the
# next backflow run reasons from a stale pre-promote base (see the design doc's "post-promote
# regression" scenario: a value promote just pushed everywhere can look like an unresolved
# collision the next time it's genuinely edited on just one side). Only reached once both pushes
# above have actually succeeded — a partial-failure promote must not advance the markers past
# what's really live (this script has no `set -e`, so without the explicit `|| exit` above, a
# failed push wouldn't have stopped execution before reaching this point).
promoted_sha="$(git rev-parse staging)"
dawn::sync_marker_set current "$promoted_sha"
dawn::sync_marker_set staging-remote "$promoted_sha"
echo "Promoted staging -> current."
exit $DAWN_OK
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh`
Expected: PASS, including `promote sync-marker ok`.

- [ ] **Step 5: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/dawn-promote/promote.sh .claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh
git commit -m "feat(ops): promote writes both sync markers after a successful push"
```

---

## Task 5: End-to-end post-promote regression test

**Files:**
- Test: `.claude/skills/_dawn-ops-lib/tests/test_sync_markers_e2e.sh` (new)

This is the scenario from the design doc's discussion, made concrete: a staging-ahead setting gets
promoted everywhere; a later, unrelated live edit to that *same* setting on `current` must fold
cleanly (current-ahead), not misclassify as a collision against staging. This is the test that
proves Task 4's promote-side marker write is actually necessary, not just tidy.

- [ ] **Step 1: Write the test**

Create `.claude/skills/_dawn-ops-lib/tests/test_sync_markers_e2e.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"
PROMOTE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-promote" && pwd)/promote.sh"
bfrun(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
           DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" "${@:2}" ); }

d=$(dawn_test_repo)

# 1) A staging-ahead setting exists: staging deliberately differs from current.
commit_on "$d" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging
commit_on "$d" staging config/settings_data.json <<< '{"k":"staging-ahead-value"}' "config snapshot"

# 2) Backflow --apply: nothing to fold from either remote (staging is simply ahead), but this
#    still establishes both markers.
bfrun "$d"; plan_rc=$?
assert_rc "$plan_rc" 0 "staging-ahead-only: plan is a no-op fast path"
bfrun "$d" --apply; apply_rc=$?
assert_rc "$apply_rc" 0 "staging-ahead-only: apply ok"

# 3) Promote: pushes staging's value everywhere, and (per Task 4) refreshes both markers.
git -C "$d" checkout -q staging
out=$( cd "$d" && DAWN_CURRENT_REF=current DAWN_PROMOTE_REF=refs/heads/current \
       DAWN_PUSH="git update-ref" DAWN_SYNC_MARKER_NOPUSH=1 \
       bash "$PROMOTE" --confirm-live 2>&1 ); promote_rc=$?
assert_rc "$promote_rc" 0 "promote ok"
assert_eq "$(git -C "$d" show current:config/settings_data.json | jq -r .k)" "staging-ahead-value" "promote pushed the staging-ahead value to current"

# 4) Now a fresh, unrelated live edit lands on current for that SAME key, after the promote.
commit_on "$d" current config/settings_data.json <<< '{"k":"fresh-live-edit"}'

# 5) The next backflow run must fold this cleanly (current-ahead) — NOT report it as a collision.
#    Before Task 4's fix, the "current" marker would still be frozen at its PRE-promote value, so
#    staging's already-promoted value would look "ahead" of a base it isn't actually ahead of
#    anymore, and this fresh edit would collide against it.
git -C "$d" checkout -q staging
out2=$(bfrun "$d"); rc2=$?
assert_rc "$rc2" 22 "post-promote live edit: clean fold, not a collision (rc 22 = plan/approve, not 21 = STOP)"
assert_contains "$out2" "config/settings_data.json" "plan report names the folded file"
bfrun "$d" --apply; apply2_rc=$?
assert_rc "$apply2_rc" 0 "post-promote live edit: apply ok"
assert_eq "$(git -C "$d" show staging:config/settings_data.json | jq -r .k)" "fresh-live-edit" "fresh live edit folded correctly, no false collision"

echo "  sync_markers_e2e ok"
```

- [ ] **Step 2: Run it**

Run: `bash .claude/skills/_dawn-ops-lib/tests/test_sync_markers_e2e.sh`
Expected: PASS. If step 5's assertion gets `rc2=21` (collision) instead of `22`, Task 4's promote
marker write isn't wired correctly — re-check Task 4 before touching this test file.

- [ ] **Step 3: Run the full suite**

Run: `bash .claude/skills/_dawn-ops-lib/tests/run.sh`
Expected: all pass, including this new file.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/tests/test_sync_markers_e2e.sh
git commit -m "test(ops): end-to-end post-promote sync-marker regression"
```

---

## Task 6: Update `conventions.md`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/conventions.md` §4 (around the paragraph added by the
  previous plan, ending "...A plan-only run never leaves `staging` changed.")

- [ ] **Step 1: Add the marker documentation**

Read the current `.claude/skills/_dawn-ops-lib/conventions.md` §4 to find the paragraph ending "...A
plan-only run never leaves `staging` changed." (added by the prior backflow-drift plan). Immediately
after it, add:

```markdown

**How "did anything change" is actually decided:** the reconcile's "base" (the reference point for
"has staging or the remote changed since we last agreed?") comes from two persisted git refs —
`refs/dawn-sync/current` and `refs/dawn-sync/staging-remote` — not from `git merge-base`. Ancestry
alone isn't reliable here, because the config-snapshot-collapse invariant above (staging always
ends in ONE commit) deliberately discards staging's own recent history on every run, which would
otherwise make a merge-base search regress further into the past each time. Both `dawn-backflow`
(on every successful `--apply`) and `dawn-promote` (after every successful push) are responsible
for keeping these markers current — promote's responsibility exists because promote also pushes
`staging`'s content to both `current` and `origin/staging` at once, which the markers must reflect
or a later genuine edit can look like a false collision against a value staging isn't actually
"ahead" on anymore. See
`docs/superpowers/specs/2026-07-03-dawn-backflow-sync-markers-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/conventions.md
git commit -m "docs(ops): conventions — sync markers replace merge-base for reconcile base"
```

---

## Task 7: Establish the markers for real

**Files:** none (operational task against the real repo)

This is a bootstrap step: the real repo has never had `refs/dawn-sync/*` before this plan. Running
backflow once (even a no-op run) establishes both markers for real, closing the loop this whole
design exists for.

- [ ] **Step 1: Confirm a clean tree on `ops`**

Run: `git status --short --branch`
Expected: clean, `ops` ahead of `origin/ops` by this plan's commits (not yet pushed).

- [ ] **Step 2: Run backflow in plan mode**

Run: `bash .claude/skills/dawn-backflow/backflow.sh`
Expected: since Task 10 of the previous plan already resolved the real divergence, this should be
a fast no-op — `exit 0`, "Nothing to reconcile" or a small residual fold if anything drifted since.
If it stops for a decision or approval, resolve/approve per the `dawn-backflow` skill's documented
flow (unrelated to this plan — just normal operation).

- [ ] **Step 3: Re-run with `--apply` if step 2 reported anything to fold**

Only if step 2 exited `22` (plan ready): `bash .claude/skills/dawn-backflow/backflow.sh --apply
[--decisions ...]`. If step 2 exited `0` directly, skip this step — a plan-mode-only run
deliberately does not write the markers (Task 3), so an explicit `--apply` run is required at least
once to actually establish `refs/dawn-sync/*` for real.

- [ ] **Step 4: Verify the markers exist**

Run: `git ls-remote origin 'refs/dawn-sync/*'` (after whichever of step 2/3 actually ran `--apply`
and pushed) — or, if nothing needed applying and you skipped step 3, run
`bash .claude/skills/dawn-backflow/backflow.sh --apply` once anyway purely to establish the
markers, then verify:

```bash
git fetch origin 'refs/dawn-sync/*:refs/dawn-sync/*' --quiet
git rev-parse refs/dawn-sync/current refs/dawn-sync/staging-remote
```

Expected: both resolve to real commit SHAs (no error).
