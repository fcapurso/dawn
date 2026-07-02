#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Case: staging-ahead only => NOT pending (rc 1)
d=$(dawn_test_repo)
commit_on "$d" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"base_key":"base"}}}}'
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
commit_on "$d" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"base_key":"base","new_key":true}}}}'
in_repo "$d" 'dawn::reconcile_pending'; rc=$?
assert_rc "$rc" 1 "staging-ahead only => not pending"

# Case: current-ahead => pending (rc 0)
d2=$(dawn_test_repo)
commit_on "$d2" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base"}}}}'
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
commit_on "$d2" current sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"live-edit"}}}}'
in_repo "$d2" 'dawn::reconcile_pending'; rc=$?
assert_rc "$rc" 0 "current-ahead => pending"

echo "  reconcile_pending ok"
