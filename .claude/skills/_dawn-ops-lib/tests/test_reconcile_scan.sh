#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
d=$(dawn_test_repo)

# config-paths.txt files must be listed even if unchanged; provide one on all branches.
commit_on "$d" staging config/settings_data.json <<< '{"a":1}'
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m merge   # give current the same file too

# A differing suffix template only on staging
commit_on "$d" staging templates/page.withdrawal.json <<< '{"sections":{"wf":{"settings":{"heading":"x"}}}}'

targets=$(in_repo "$d" 'dawn::config_targets')
assert_contains "$targets" "config/settings_data.json" "full-config listed"
assert_contains "$targets" "templates/page.withdrawal.json" "differing suffix listed"
assert_not_contains "$targets" "templates/product.json" "absent default not listed"

d2=$(dawn_test_repo)
# base
commit_on "$d2" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"base","fold_current":"base","collide":"base","agree":"base"}}}}
JSON
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
# staging edits: keep_staging + collide + agree
commit_on "$d2" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"S","fold_current":"base","collide":"S","agree":"same"}}}}
JSON
# current edits: fold_current + collide + agree
commit_on "$d2" current sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"base","fold_current":"C","collide":"C","agree":"same"}}}}
JSON

scan=$(in_repo "$d2" 'dawn::reconcile_scan')
assert_contains "$scan" "staging_ahead	sections/footer-group.json	[\"sections\",\"f\",\"settings\",\"keep_staging\"]" "staging_ahead"
assert_contains "$scan" "current_ahead	sections/footer-group.json	[\"sections\",\"f\",\"settings\",\"fold_current\"]" "current_ahead"
assert_contains "$scan" "collision	sections/footer-group.json	[\"sections\",\"f\",\"settings\",\"collide\"]" "collision"
assert_not_contains "$scan" '"agree"' "agree not emitted"

echo "  config_targets ok"

# --- sync-marker base (replaces merge-base) ---

# No marker set -> falls back to merge-base, exactly today's behavior.
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"base"}'
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
commit_on "$d3" current config/settings_data.json <<< '{"k":"live"}'
scan=$(in_repo "$d3" 'dawn::reconcile_scan')
assert_contains "$scan" 'current_ahead	config/settings_data.json	["k"]	"base"	"base"	"live"' "no marker: falls back to merge-base"

# Marker set, remote hasn't moved since -> no drift, even if git ancestry would say otherwise.
# This directly reproduces the 2026-07-03 incident. The key mechanic: staging's collapse must
# ACTUALLY discard an intermediate commit from its own ancestry (via a real `reset --soft` back
# to a shared floor, exactly mirroring dawn-backflow's real collapse), not just add commits on
# top of each other — otherwise merge-base and the marker trivially agree and the test proves
# nothing.
d4=$(dawn_test_repo)
# floor: the one commit BOTH staging's collapsed tip and staging_remote's chain will still share.
commit_on "$d4" staging config/settings_data.json <<< '{"padding":36}' "floor"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
floor_sha=$(git -C "$d4" rev-parse staging)

# origin/staging independently syncs to padding:0 at some point (e.g. an earlier live-editor
# fold) — this is the state a prior successful backflow run would have frozen as the marker.
commit_on "$d4" staging_remote config/settings_data.json <<< '{"padding":0}' "staging_remote synced to 0"
sr_synced_sha=$(git -C "$d4" rev-parse staging_remote)
in_repo "$d4" "dawn::sync_marker_set staging-remote $sr_synced_sha"

# staging separately collapses to padding:0 too, but via ITS OWN chain off floor: commit an
# intermediate, then reset --soft back to floor and recommit — mirroring dawn-backflow's real
# collapse mechanism. staging's new tip shares history with floor only, NOT with sr_synced_sha.
git -C "$d4" checkout -q staging
commit_on "$d4" staging config/settings_data.json <<< '{"padding":0}' "intermediate (later discarded)"
git -C "$d4" reset -q --soft "$floor_sha"
git -C "$d4" commit -q -m "config snapshot (collapsed)"

# now the operator reverts the live preview theme back to padding:36 — a new commit on TOP of
# sr_synced_sha (origin/staging's real history), unrelated to staging's discarded intermediate.
git -C "$d4" checkout -q staging_remote
commit_on "$d4" staging_remote config/settings_data.json <<< '{"padding":36}' "operator reverts on live preview theme"
git -C "$d4" checkout -q staging

# Sanity-check the fixture's own precondition: naive merge-base must have regressed all the way
# to floor (padding:36) — that's exactly what would make the old code misclassify the operator's
# revert as "staging_ahead" (silently ignored) instead of a real change.
naive_base=$(git -C "$d4" merge-base staging staging_remote)
assert_eq "$naive_base" "$floor_sha" "sanity: naive merge-base regresses to floor, reproducing the bug's precondition"

other=$(in_repo "$d4" 'dawn::staging_remote_ref')
scan4=$(in_repo "$d4" "dawn::reconcile_scan $other")
assert_contains "$scan4" 'current_ahead	config/settings_data.json	["padding"]	0	0	36' "marker (not stale ancestry) correctly detects the revert as a real change"
assert_not_contains "$scan4" 'staging_ahead	config/settings_data.json	["padding"]' "must NOT be misclassified as staging_ahead (the old bug)"

echo "  reconcile_scan sync-marker ok"
