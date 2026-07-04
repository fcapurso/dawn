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
#    stage-push. k stays at its post-fold value ("preview-live-edit") on all three sides here, so
#    this is an unambiguous current_ahead on k2, not a collision.
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
