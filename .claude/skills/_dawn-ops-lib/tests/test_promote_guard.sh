#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
PROMOTE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-promote" && pwd)/promote.sh"

# staging-ahead only: guard must NOT block (should reach the STOP_LIVE confirm gate, rc 20).
d=$(dawn_test_repo)
# promote's assert_staging_clean requires a 'customizations' branch that staging is not behind.
commit_on "$d" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base"}}}}' "config snapshot"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
commit_on "$d" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base","new":true}}}}' "config snapshot"
git -C "$d" checkout -q staging
out=$( cd "$d" && DAWN_CURRENT_REF=current DAWN_PROMOTE_REF=refs/heads/current \
       DAWN_PUSH="git update-ref" bash "$PROMOTE" 2>&1 ); rc=$?
assert_rc "$rc" 20 "staging-ahead reaches confirm-live gate, not the backflow guard"
assert_not_contains "$out" "backflow first" "no false backflow guard"

echo "  promote_guard ok"

# A real (confirm-live) promote updates both sync markers to staging's new tip.
d2=$(dawn_test_repo)
commit_on "$d2" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base"}}}}' "config snapshot"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging
staging_sha=$(git -C "$d2" rev-parse staging)

out2=$( cd "$d2" && DAWN_CURRENT_REF=current DAWN_PROMOTE_REF=refs/heads/current \
        DAWN_PUSH="git update-ref" DAWN_SYNC_MARKER_NOPUSH=1 \
        bash "$PROMOTE" --confirm-live 2>&1 ); rc2=$?
assert_rc "$rc2" 0 "confirm-live promote ok"
assert_eq "$(git -C "$d2" rev-parse refs/dawn-sync/current)" "$staging_sha" "promote writes the current marker to staging's tip"
assert_eq "$(git -C "$d2" rev-parse refs/dawn-sync/staging-remote)" "$staging_sha" "promote writes the staging-remote marker to staging's tip"

echo "  promote sync-marker ok"
