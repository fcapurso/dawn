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
