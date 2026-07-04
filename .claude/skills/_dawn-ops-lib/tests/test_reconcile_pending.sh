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

# Case: collision only (both changed the same key differently) => NOT pending (rc 1).
# Collisions are decided at backflow time, not blocked at the promote gate. A resolved-to-staging
# collision is indistinguishable from an unresolved one statelessly, so it must not block promote.
d3=$(dawn_test_repo)
commit_on "$d3" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base"}}}}'
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging  sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"S"}}}}'
commit_on "$d3" current  sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"C"}}}}'
in_repo "$d3" 'dawn::reconcile_pending'; rc=$?
assert_rc "$rc" 1 "collision only => not pending (decided at backflow, not blocked at promote)"

# Case: current-ahead-style drift on origin/staging (the "other" param) => pending against that
# ref specifically, while the default (current) call site is unaffected by it.
d4=$(dawn_test_repo)
commit_on "$d4" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"base"}}}}'
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
commit_on "$d4" staging_remote sections/footer-group.json <<< '{"sections":{"f":{"settings":{"k":"bot-edit"}}}}'
git -C "$d4" checkout -q staging
other=$(in_repo "$d4" 'dawn::staging_remote_ref')
in_repo "$d4" "dawn::reconcile_pending $other"; rc4=$?
assert_rc "$rc4" 0 "other-ref-ahead drift => pending against that ref"
in_repo "$d4" 'dawn::reconcile_pending'; rc4b=$?
assert_rc "$rc4b" 1 "default call site (current) unaffected by staging_remote's drift"

echo "  reconcile_pending ok"
