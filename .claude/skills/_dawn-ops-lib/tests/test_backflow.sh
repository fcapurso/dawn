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

# amend heuristic must NOT fold config into an unrelated feature-tip commit
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"base"}' "L2: store config snapshot"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
commit_on "$d3" current config/settings_data.json <<< '{"k":"live"}'   # current-ahead => a fold will happen
git -C "$d3" checkout -q staging
# Feature commit touches a non-config file. Subject contains "settings" to trigger the OLD loose
# pattern (*settings*) but must NOT match the new anchored pattern ("L2: store config snapshot"*).
commit_on "$d3" staging layout/theme.liquid <<< '<html></html>' "feat: redesign settings panel"
n_before=$(git -C "$d3" rev-list --count staging)
( cd "$d3" && DAWN_CURRENT_REF=current bash "$BF" ); rc=$?
assert_rc "$rc" 0 "backflow ok with feature tip"
n_after=$(git -C "$d3" rev-list --count staging)
assert_eq "$n_after" "$((n_before+1))" "new snapshot commit added, feature tip NOT amended"
assert_eq "$(git -C "$d3" log -1 --format=%s staging | grep -c 'store config snapshot')" "1" "tip is a fresh snapshot commit"
assert_eq "$(git -C "$d3" log -1 --format=%s 'staging~1')" "feat: redesign settings panel" "feature commit intact below"

# no folds (staging-ahead only) + non-snapshot tip => establish empty snapshot marker for promote
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "L2: store config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base","new":true}' "Update from Shopify for theme dawn/staging"
n_before=$(git -C "$d4" rev-list --count staging)
( cd "$d4" && DAWN_CURRENT_REF=current bash "$BF" ); rc=$?
assert_rc "$rc" 0 "backflow ok (marker path)"
n_after=$(git -C "$d4" rev-list --count staging)
assert_eq "$n_after" "$((n_before+1))" "empty snapshot marker commit added"
assert_eq "$(git -C "$d4" log -1 --format=%s staging | grep -c 'store config snapshot')" "1" "tip is now a snapshot commit"
assert_eq "$(git -C "$d4" show staging:config/settings_data.json | jq -r .new)" "true" "staging-ahead value still intact"

echo "  backflow ok"
