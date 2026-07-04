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
