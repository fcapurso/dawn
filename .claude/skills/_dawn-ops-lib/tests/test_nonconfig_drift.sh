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

echo "  nonconfig_drift ok"
