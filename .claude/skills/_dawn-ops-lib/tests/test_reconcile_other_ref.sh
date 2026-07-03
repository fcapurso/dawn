#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

d=$(dawn_test_repo)
# base
commit_on "$d" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"base","fold_remote":"base","collide":"base"}}}}
JSON
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
# staging edits keep_staging + collide
commit_on "$d" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"S","fold_remote":"base","collide":"S"}}}}
JSON
# staging_remote (the bot) edits fold_remote + collide
commit_on "$d" staging_remote sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep_staging":"base","fold_remote":"R","collide":"R"}}}}
JSON

other=$(in_repo "$d" 'dawn::staging_remote_ref')
scan=$(in_repo "$d" "dawn::reconcile_scan $other")
assert_contains "$scan" 'staging_ahead	sections/footer-group.json	["sections","f","settings","keep_staging"]' "staging_ahead vs other ref"
assert_contains "$scan" 'current_ahead	sections/footer-group.json	["sections","f","settings","fold_remote"]' "other-ref-ahead reuses current_ahead verdict name"
assert_contains "$scan" 'collision	sections/footer-group.json	["sections","f","settings","collide"]' "collision vs other ref"

# default (no arg) must be unaffected — still compares against dawn::current_ref, which never
# saw staging_remote's fold_remote/collide edits, so no current_ahead verdict should appear
# (fold_remote legitimately shows as staging_ahead here since 'current' never touched the file).
default_scan=$(in_repo "$d" 'dawn::reconcile_scan')
assert_not_contains "$default_scan" "current_ahead" "default call site untouched by the new param"

# dawn::reconcile_apply against the other ref folds fold_remote and leaves keep_staging alone
decisions_file="$(mktemp)"
printf 'sections/footer-group.json\t["sections","f","settings","collide"]\tvalue:"R"\n' > "$decisions_file"
merged=$(in_repo "$d" "dawn::reconcile_apply sections/footer-group.json $decisions_file $other")
assert_contains "$merged" '"fold_remote": "R"' "reconcile_apply folds other-ref-ahead value"
assert_contains "$merged" '"keep_staging": "S"' "reconcile_apply keeps staging value"
assert_contains "$merged" '"collide": "R"' "reconcile_apply applies the collision decision"
rm -f "$decisions_file"

echo "  reconcile_other_ref ok"
