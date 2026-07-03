#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

d=$(dawn_test_repo)

# get on an unset marker returns empty, not an error
out=$(in_repo "$d" 'dawn::sync_marker_get current')
assert_eq "$out" "" "unset marker reads as empty"

# set + get round-trips
sha=$(git -C "$d" rev-parse staging)
in_repo "$d" "dawn::sync_marker_set current $sha"
out=$(in_repo "$d" 'dawn::sync_marker_get current')
assert_eq "$out" "$sha" "marker round-trips"

# the local ref really exists under refs/dawn-sync/
ref_sha=$(git -C "$d" rev-parse refs/dawn-sync/current)
assert_eq "$ref_sha" "$sha" "marker is a real ref under refs/dawn-sync/"

# set with an empty sha is a no-op (defensive — callers must not clobber with garbage)
in_repo "$d" 'dawn::sync_marker_set current ""'
out=$(in_repo "$d" 'dawn::sync_marker_get current')
assert_eq "$out" "$sha" "empty-sha set is a no-op, marker unchanged"

# _sync_marker_name maps the two known "other" refs to their logical names
cur_name=$(in_repo "$d" 'dawn::_sync_marker_name "$(dawn::current_ref)"')
assert_eq "$cur_name" "current" "current_ref maps to the 'current' marker"
sr_name=$(in_repo "$d" 'dawn::_sync_marker_name "$(dawn::staging_remote_ref)"')
assert_eq "$sr_name" "staging-remote" "staging_remote_ref maps to the 'staging-remote' marker"
unknown_name=$(in_repo "$d" 'dawn::_sync_marker_name some-unrelated-ref')
assert_eq "$unknown_name" "" "an unrecognized ref maps to no marker"

echo "  sync_markers ok"
