#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Shared setup: four keys, each side changes a different one; "d" changes on all three.
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json \
  <<< '{"a":"base","b":"base","c":"base","d":"base"}' "base"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
commit_on "$d" staging config/settings_data.json \
  <<< '{"a":"s-val","b":"base","c":"base","d":"s-val"}' "staging changes a,d"
commit_on "$d" current config/settings_data.json \
  <<< '{"a":"base","b":"c-val","c":"base","d":"c-val"}' "current changes b,d"
commit_on "$d" staging_remote config/settings_data.json \
  <<< '{"a":"base","b":"base","c":"r-val","d":"r-val"}' "sr changes c,d"
git -C "$d" checkout -q staging
dec="$d/dec.tsv"

# 1) All 'staging' verdicts → no change → empty output
printf '%s\t%s\t%s\n' \
  'config/settings_data.json' '["a"]' 'staging' \
  'config/settings_data.json' '["b"]' 'staging' \
  'config/settings_data.json' '["c"]' 'staging' \
  'config/settings_data.json' '["d"]' 'staging' > "$dec"
m1=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote")
assert_eq "$m1" "" "all-staging decisions → empty output (no rewrite)"

# 2) 'current' verdict → takes origin/current's value
printf '%s\t%s\t%s\n' \
  'config/settings_data.json' '["a"]' 'staging' \
  'config/settings_data.json' '["b"]' 'current' \
  'config/settings_data.json' '["c"]' 'staging' \
  'config/settings_data.json' '["d"]' 'staging' > "$dec"
m2=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote")
assert_eq "$(jq -r '.b' <<< "$m2")" "c-val" "current verdict takes current value"
assert_eq "$(jq -r '.a' <<< "$m2")" "s-val" "a unchanged"

# 3) 'staging_remote' verdict → takes origin/staging's value
printf '%s\t%s\t%s\n' \
  'config/settings_data.json' '["a"]' 'staging' \
  'config/settings_data.json' '["b"]' 'staging' \
  'config/settings_data.json' '["c"]' 'staging_remote' \
  'config/settings_data.json' '["d"]' 'staging' > "$dec"
m3=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote")
assert_eq "$(jq -r '.c' <<< "$m3")" "r-val" "staging_remote verdict takes preview value"

# 4) 'value:JSON' verdict → sets custom value
printf '%s\t%s\t%s\n' \
  'config/settings_data.json' '["a"]' 'staging' \
  'config/settings_data.json' '["b"]' 'staging' \
  'config/settings_data.json' '["c"]' 'staging' \
  'config/settings_data.json' '["d"]' 'value:"custom"' > "$dec"
m4=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote")
assert_eq "$(jq -r '.d' <<< "$m4")" "custom" "value: verdict sets custom value"

# 5) Missing decision → STOP_JUDGMENT (rc 21)
printf '%s\t%s\t%s\n' 'config/settings_data.json' '["a"]' 'staging' > "$dec"
out5=$(in_repo "$d" "dawn::backflow_apply config/settings_data.json '$dec' current staging_remote" 2>&1); rc5=$?
assert_rc "$rc5" 21 "missing decisions → rc 21"
assert_contains "$out5" "unresolved" "error mentions unresolved"

echo "  backflow_apply ok"
