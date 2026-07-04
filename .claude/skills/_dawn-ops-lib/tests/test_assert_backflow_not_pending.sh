#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# A) Clean: staging, current, and staging_remote all agree — must pass (rc 0).
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging
in_repo "$d" 'dawn::assert_backflow_not_pending'; rc=$?
assert_rc "$rc" 0 "clean state: guard passes"

# B) current-ahead config drift (a live edit on the published theme, never backflowed) => GUARD,
#    message names origin/current.
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
commit_on "$d2" current config/settings_data.json <<< '{"k":"live-edit"}'
git -C "$d2" checkout -q staging
out2=$(in_repo "$d2" 'dawn::assert_backflow_not_pending' 2>&1); rc2=$?
assert_rc "$rc2" 10 "current-ahead drift: GUARD"
assert_contains "$out2" "origin/current" "message names origin/current"
assert_contains "$out2" "backflow first" "message says backflow first"

# C) current-ahead-style config drift against origin/staging (a live edit on the PREVIEW theme,
#    never backflowed) => GUARD, message names origin/staging specifically (not origin/current).
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging_remote config/settings_data.json <<< '{"k":"preview-live-edit"}'
git -C "$d3" checkout -q staging
out3=$(in_repo "$d3" 'dawn::assert_backflow_not_pending' 2>&1); rc3=$?
assert_rc "$rc3" 10 "origin/staging-ahead config drift: GUARD"
assert_contains "$out3" "origin/staging" "message names origin/staging"
assert_not_contains "$out3" "origin/current has current-ahead" "does not mis-blame origin/current"

# D) origin/staging non-config drift that CONFLICTS with local staging (same locale line edited
#    both places) => GUARD, message says to resolve manually.
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
commit_on "$d4" staging_remote locales/nl.json <<< '{"a":"bot-value"}'
git -C "$d4" checkout -q staging
commit_on "$d4" staging locales/nl.json <<< '{"a":"staging-value"}'
out4=$(in_repo "$d4" 'dawn::assert_backflow_not_pending' 2>&1); rc4=$?
assert_rc "$rc4" 10 "conflicting non-config drift: GUARD"
assert_contains "$out4" "non-config file" "message calls out the non-config conflict"
assert_contains "$out4" "resolve manually" "message tells the operator to resolve manually"

# E) origin/staging non-config drift that folds CLEANLY (no conflict) but hasn't been folded yet
#    => still GUARD (a clean fold is still a fold dawn-backflow must perform first).
d5=$(dawn_test_repo)
commit_on "$d5" staging locales/nl.json <<'JSON'
{
  "a": "base-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "base-e"
}
JSON
git -C "$d5" checkout -q staging_remote; git -C "$d5" merge -q staging -m sync
commit_on "$d5" staging locales/nl.json <<'JSON'
{
  "a": "staging-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "base-e"
}
JSON
commit_on "$d5" staging_remote locales/nl.json <<'JSON'
{
  "a": "base-a",
  "b": "base-b",
  "c": "base-c",
  "d": "base-d",
  "e": "bot-e"
}
JSON
git -C "$d5" checkout -q staging
out5=$(in_repo "$d5" 'dawn::assert_backflow_not_pending' 2>&1); rc5=$?
assert_rc "$rc5" 10 "clean-but-unfolded non-config drift: still GUARD"
assert_contains "$out5" "non-config drift" "message calls out the unfolded non-config drift"

echo "  assert_backflow_not_pending ok"
