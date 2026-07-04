#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# 1) No staging-remote marker → GUARD with "never been pushed" message
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"k":"v"}' "config snapshot"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging
out1=$(in_repo "$d" 'dawn::assert_stage_push_current current staging_remote' 2>&1); rc1=$?
assert_rc "$rc1" 10 "no marker → GUARD"
assert_contains "$out1" "never been pushed" "message: never been pushed"

# 2) Marker set but staging has a new commit → GUARD
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"k":"v"}' "base"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging
staging_sha2=$(git -C "$d2" rev-parse staging)
git -C "$d2" update-ref refs/dawn-sync/staging-remote "$staging_sha2"
commit_on "$d2" staging config/settings_data.json <<< '{"k":"v2"}' "new backflow commit"
git -C "$d2" checkout -q staging
out2=$(in_repo "$d2" 'dawn::assert_stage_push_current current staging_remote' 2>&1); rc2=$?
assert_rc "$rc2" 10 "staging advanced past marker → GUARD"
assert_contains "$out2" "staging has changed" "message: staging changed since push"

# 3) Marker and staging match, but staging_remote advanced → GUARD
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"v"}' "base"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging
staging_sha3=$(git -C "$d3" rev-parse staging)
git -C "$d3" update-ref refs/dawn-sync/staging-remote "$staging_sha3"
git -C "$d3" update-ref refs/dawn-sync/current "$(git -C "$d3" rev-parse current)"
# Advance staging_remote (simulate Shopify bot commit on preview)
commit_on "$d3" staging_remote config/settings_data.json <<< '{"k":"bot"}' "bot edit"
git -C "$d3" checkout -q staging
out3=$(in_repo "$d3" 'dawn::assert_stage_push_current current staging_remote' 2>&1); rc3=$?
assert_rc "$rc3" 10 "staging_remote advanced → GUARD"
assert_contains "$out3" "preview theme has changed" "message: preview changed since push"

# 4) All match → guard passes (exits 0)
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"v"}' "config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging
sha4=$(git -C "$d4" rev-parse staging)
git -C "$d4" update-ref refs/dawn-sync/staging-remote "$sha4"
git -C "$d4" update-ref refs/heads/staging_remote "$sha4"
git -C "$d4" update-ref refs/dawn-sync/current "$(git -C "$d4" rev-parse current)"
rc4=$(in_repo "$d4" 'dawn::assert_stage_push_current current staging_remote' 2>&1); rc4_exit=$?
assert_rc "$rc4_exit" 0 "all match → guard passes"

echo "  promote_stage_push_guard ok"
