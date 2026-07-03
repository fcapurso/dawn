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
