#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"

# staging-ahead only => value preserved; config collapses to ONE snapshot at the tip
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"k":"base"}'
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
commit_on "$d" staging config/settings_data.json <<< '{"k":"base","new":true}' "config snapshot"
git -C "$d" checkout -q staging
( cd "$d" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote bash "$BF" ); rc=$?
assert_rc "$rc" 0 "staging-ahead backflow ok"
assert_eq "$(git -C "$d" show staging:config/settings_data.json | jq -r .new)" "true" "staging value preserved"
assert_eq "$(git -C "$d" rev-list --count customizations..staging)" "1" "collapsed to one snapshot commit"
assert_eq "$(git -C "$d" log -1 --format=%s staging | grep -c 'store config snapshot')" "1" "tip is the snapshot"

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

# multiple config commits (old snapshot + bot commits) collapse into ONE snapshot at the tip
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "L2: store config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base","a":1}' "Update from Shopify for theme dawn/staging"
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base","a":1,"new":true}' "Update from Shopify for theme dawn/staging"
( cd "$d4" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote bash "$BF" ); rc=$?
assert_rc "$rc" 0 "multi-commit collapse ok"
assert_eq "$(git -C "$d4" rev-list --count customizations..staging)" "1" "3 config commits collapsed to 1"
assert_eq "$(git -C "$d4" log -1 --format=%s staging | grep -c 'store config snapshot')" "1" "tip is the snapshot"
assert_eq "$(git -C "$d4" show staging:config/settings_data.json | jq -r .new)" "true" "staging-ahead value intact"

# enrichment (non-config) commit is the floor: preserved, never squashed; config above it -> ONE snapshot
d5=$(dawn_test_repo)
commit_on "$d5" staging snippets/foo.liquid <<< 'hello' "L2: enrichment snippet"
commit_on "$d5" staging config/settings_data.json <<< '{"a":1}' "L2: store config snapshot"
git -C "$d5" checkout -q current; git -C "$d5" merge -q staging -m sync
commit_on "$d5" staging config/settings_data.json <<< '{"a":1,"b":2}' "Update from Shopify for theme dawn/staging"
git -C "$d5" checkout -q staging
( cd "$d5" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote bash "$BF" ); rc=$?
assert_rc "$rc" 0 "enrichment-floor backflow ok"
assert_eq "$(git -C "$d5" log -1 --format=%s staging | grep -c 'store config snapshot')" "1" "tip is the snapshot"
assert_eq "$(git -C "$d5" log -1 --format=%s staging~1)" "L2: enrichment snippet" "enrichment preserved directly below the single snapshot"
assert_eq "$(git -C "$d5" cat-file -t staging:snippets/foo.liquid)" "blob" "enrichment file not squashed away"
assert_eq "$(git -C "$d5" show staging:config/settings_data.json | jq -r .b)" "2" "staging-ahead config carried through collapse"

echo "  backflow ok"

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

# The "nothing to report" fast path (staging-ahead only — nothing to fold from either remote, so
# there's nothing to review/approve) always collapses and commits regardless of --apply, matching
# the original pre-plan/apply backflow behavior for this one case. Because that persists
# regardless of the flag, the markers must ALSO update regardless of the flag here — otherwise a
# bare (no --apply) call that happens to hit this path would advance staging's ancestry (via the
# unconditional collapse) without the markers reflecting it, and the next call's merge-base
# fallback would compute against a now-stale reference point. (Found via the sync-markers
# end-to-end test: a plan-mode call followed by --apply, both landing on this exact fast path,
# produced a spurious collision before this was fixed.)
d7=$(dawn_test_repo)
commit_on "$d7" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d7" checkout -q current; git -C "$d7" merge -q staging -m sync
git -C "$d7" checkout -q staging_remote; git -C "$d7" merge -q staging -m sync
git -C "$d7" checkout -q staging
commit_on "$d7" staging config/settings_data.json <<< '{"k":"staging-ahead-value"}' "config snapshot"
cur_sha7=$(git -C "$d7" rev-parse current)
sr_sha7=$(git -C "$d7" rev-parse staging_remote)

( cd "$d7" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
  DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" ) >/dev/null; fastpath_rc=$?
assert_rc "$fastpath_rc" 0 "staging-ahead-only (nothing to report) is rc 0 even without --apply"
assert_eq "$(git -C "$d7" rev-parse refs/dawn-sync/current)" "$cur_sha7" "fast path writes the current marker even without --apply"
assert_eq "$(git -C "$d7" rev-parse refs/dawn-sync/staging-remote)" "$sr_sha7" "fast path writes the staging-remote marker even without --apply"

echo "  backflow sync-marker ok"
