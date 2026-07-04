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
# The DAWN_PROMOTE_REF test seam only stands in for the real push to `current` — real promote
# also force-pushes staging onto origin/staging (conventions.md §4), which the seam has no
# equivalent for. Simulate that second push directly so staging_remote (this fixture's stand-in
# for origin/staging) reflects reality; otherwise Step 0a's fold-from-staging_remote would see
# staging_remote's untouched pre-promote content as "changed" relative to the marker (which Task
# 4 correctly updated) and spuriously re-fold the OLD value back over the just-promoted one.
git -C "$d" update-ref refs/heads/staging_remote staging

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
