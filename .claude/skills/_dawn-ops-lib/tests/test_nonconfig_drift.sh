#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Clean fold: staging and staging_remote each change a different, non-adjacent key in a locale file.
d=$(dawn_test_repo)
commit_on "$d" staging locales/nl.json <<'JSON'
{
  "a": "base-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "base-e"
}
JSON
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
commit_on "$d" staging locales/nl.json <<'JSON'
{
  "a": "staging-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "base-e"
}
JSON
commit_on "$d" staging_remote locales/nl.json <<'JSON'
{
  "a": "base-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "bot-e"
}
JSON
git -C "$d" checkout -q staging

out=$(in_repo "$d" 'dawn::nonconfig_drift_scan'); rc=$?
assert_rc "$rc" 0 "clean non-config drift scan ok"
assert_contains "$out" "locales/nl.json" "changed file reported"

in_repo "$d" 'dawn::nonconfig_drift_apply'
folded=$(cat "$d/locales/nl.json")
assert_contains "$folded" '"e": "bot-e"' "bot edit folded into working tree"
assert_contains "$folded" '"a": "staging-a"' "staging's own edit preserved"

# No drift: staging_remote unchanged since merge-base
d2=$(dawn_test_repo)
commit_on "$d2" staging locales/nl.json <<< '{"a":"x"}'
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging
out2=$(in_repo "$d2" 'dawn::nonconfig_drift_scan'); rc2=$?
assert_rc "$rc2" 0 "no-drift scan ok"
assert_eq "$out2" "" "no-drift scan reports nothing"

# Conflict: both sides change the exact same line
d3=$(dawn_test_repo)
commit_on "$d3" staging locales/nl.json <<< '{"a":"base"}'
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging locales/nl.json <<< '{"a":"staging-value"}'
commit_on "$d3" staging_remote locales/nl.json <<< '{"a":"bot-value"}'
git -C "$d3" checkout -q staging
out3=$(in_repo "$d3" 'dawn::nonconfig_drift_scan'); rc3=$?
assert_rc "$rc3" 1 "conflicting drift scan returns 1"
assert_contains "$out3" "locales/nl.json" "conflicting file named"

# Deletion: staging_remote deletes a file that both merge-base and staging still have,
# with no conflicting edit on staging's side — clean fold should remove it from disk.
d4=$(dawn_test_repo)
commit_on "$d4" staging locales/nl.json <<< '{"a":"base"}'
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
git -C "$d4" rm -q locales/nl.json
git -C "$d4" commit -q -m "delete nl.json"
git -C "$d4" checkout -q staging
out4=$(in_repo "$d4" 'dawn::nonconfig_drift_scan'); rc4=$?
assert_rc "$rc4" 0 "deletion drift scan ok"
assert_contains "$out4" "locales/nl.json" "deleted file reported"

in_repo "$d4" 'dawn::nonconfig_drift_apply'
[ -f "$d4/locales/nl.json" ] && _dawn_fail "deleted file still present on disk after apply"

# Config-class file, clean (non-conflicting) drift: must NEVER surface here — it's the leaf
# reconciler's territory, not this function's, regardless of whether it also changed.
d5=$(dawn_test_repo)
commit_on "$d5" staging config/settings_data.json <<< '{"z":"base"}'
git -C "$d5" checkout -q staging_remote; git -C "$d5" merge -q staging -m sync
commit_on "$d5" staging_remote config/settings_data.json <<< '{"z":"bot-value"}'
git -C "$d5" checkout -q staging
out5=$(in_repo "$d5" 'dawn::nonconfig_drift_scan'); rc5=$?
assert_rc "$rc5" 0 "config-class-only drift scan ok"
assert_eq "$out5" "" "config-class file never reported by nonconfig scan"

# Bug 2 repro: config-class file where staging and staging_remote each change the exact same
# line to different values (the shape that raw-text-conflicts in git merge-tree) — this simulates
# a Step-0a collision already resolved (staging's committed value differs literally from
# staging_remote's raw serialization). Must NOT be treated as a conflict by this function: it's
# out of scope, already-resolved-elsewhere territory, so scan must return 0 and report nothing.
d6=$(dawn_test_repo)
commit_on "$d6" staging config/settings_data.json <<< '{"z":"base"}'
git -C "$d6" checkout -q staging_remote; git -C "$d6" merge -q staging -m sync
commit_on "$d6" staging config/settings_data.json <<< '{"z":"staging-resolved"}'
commit_on "$d6" staging_remote config/settings_data.json <<< '{"z":"bot-value"}'
git -C "$d6" checkout -q staging
out6=$(in_repo "$d6" 'dawn::nonconfig_drift_scan'); rc6=$?
assert_rc "$rc6" 0 "config-class same-line conflict is out of scope, scan still returns 0"
assert_eq "$out6" "" "config-class file not reported even though it would raw-text-conflict"

echo "  nonconfig_drift ok"
