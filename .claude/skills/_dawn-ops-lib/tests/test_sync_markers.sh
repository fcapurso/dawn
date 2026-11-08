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

# --- Remote round-trip: markers jump between unrelated histories (promote force-resets current,
# backflow rewrites staging's snapshot), so push and fetch must overwrite, not fast-forward.
origin=$(mktemp -d); git -C "$origin" init -q --bare
git -C "$d" remote add origin "$origin"
git -C "$d" checkout -q staging
git -C "$d" commit -q --allow-empty -m "line A"; sha_a=$(git -C "$d" rev-parse HEAD)
git -C "$d" checkout -q --orphan rewritten; git -C "$d" commit -q --allow-empty -m "line B"
sha_b=$(git -C "$d" rev-parse HEAD)
git -C "$d" checkout -q staging

( cd "$d" && bash -c "source '$DAWN_LIB_SRC'; dawn::sync_marker_set current $sha_a" )
assert_eq "$(git -C "$origin" rev-parse refs/dawn-sync/current)" "$sha_a" "first marker push lands"
err=$( cd "$d" && bash -c "source '$DAWN_LIB_SRC'; dawn::sync_marker_set current $sha_b" 2>&1 )
assert_eq "$(git -C "$origin" rev-parse refs/dawn-sync/current)" "$sha_b" "non-fast-forward marker push overwrites the remote"
assert_eq "$err" "" "successful push prints nothing"

# A second checkout holding a stale marker picks up the remote one on fetch
c=$(mktemp -d); git clone -q "$origin" "$c" 2>/dev/null
git -C "$c" config user.email t@t.t; git -C "$c" config user.name t
git -C "$c" fetch -q origin "+refs/dawn-sync/*:refs/dawn-sync/*"
git -C "$c" update-ref refs/dawn-sync/current "$sha_a"
( cd "$c" && bash -c "source '$DAWN_LIB_SRC'; dawn::sync_markers_fetch" )
assert_eq "$(git -C "$c" rev-parse refs/dawn-sync/current)" "$sha_b" "fetch overwrites a stale local marker"

# A failed push warns instead of failing silently, and still sets the local marker
git -C "$d" remote set-url origin /nonexistent/repo
err=$( cd "$d" && bash -c "source '$DAWN_LIB_SRC'; dawn::sync_marker_set staging-remote $sha_a" 2>&1 ); rc=$?
assert_rc "$rc" 0 "failed push does not fail the caller"
assert_contains "$err" "WARN" "failed push prints a warning"
assert_eq "$(git -C "$d" rev-parse refs/dawn-sync/staging-remote)" "$sha_a" "local marker set despite failed push"

echo "  sync_markers ok"
