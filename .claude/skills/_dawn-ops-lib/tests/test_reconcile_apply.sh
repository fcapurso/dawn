#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
d=$(dawn_test_repo)
commit_on "$d" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep":"base","fold":"base","collide":"base"}}}}
JSON
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
commit_on "$d" staging sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep":"S","fold":"base","collide":"S"}}}}
JSON
commit_on "$d" current sections/footer-group.json <<'JSON'
{"sections":{"f":{"settings":{"keep":"base","fold":"C","collide":"C"}}}}
JSON

# Without a decision for the collision => STOP_JUDGMENT (rc 21)
out=$(in_repo "$d" 'dawn::reconcile_apply sections/footer-group.json /dev/null'); rc=$?
assert_rc "$rc" 21 "unresolved collision stops"

# With a decision (keep staging for collide) => merged JSON
dec="$d/decisions.tsv"
printf 'sections/footer-group.json\t["sections","f","settings","collide"]\tstaging\n' > "$dec"
merged=$(in_repo "$d" "dawn::reconcile_apply sections/footer-group.json '$dec'"); rc=$?
assert_rc "$rc" 0 "resolved collision applies"
assert_eq "$(jq -r '.sections.f.settings.keep' <<< "$merged")" "S"    "staging-ahead kept"
assert_eq "$(jq -r '.sections.f.settings.fold' <<< "$merged")" "C"    "current-ahead folded"
assert_eq "$(jq -r '.sections.f.settings.collide' <<< "$merged")" "S" "collision -> staging"

# value:<json> resolution
printf 'sections/footer-group.json\t["sections","f","settings","collide"]\tvalue:"X"\n' > "$dec"
merged=$(in_repo "$d" "dawn::reconcile_apply sections/footer-group.json '$dec'")
assert_eq "$(jq -r '.sections.f.settings.collide' <<< "$merged")" "X" "collision -> entered value"

# staging-ahead DELETION: staging removed a key present at base+current => merged output omits it
dd=$(dawn_test_repo)
commit_on "$dd" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"keep":"base","drop":"base"}}}}' "base"
git -C "$dd" checkout -q current; git -C "$dd" merge -q sync 2>/dev/null || git -C "$dd" merge -q staging -m sync
commit_on "$dd" staging sections/footer-group.json <<< '{"sections":{"f":{"settings":{"keep":"base"}}}}' "drop key"
mm=$(in_repo "$dd" 'dawn::reconcile_apply sections/footer-group.json /dev/null')
assert_eq "$(jq -r '.sections.f.settings.drop // "GONE"' <<< "$mm")" "GONE" "staging-ahead deletion removes key"
assert_eq "$(jq -r '.sections.f.settings.keep' <<< "$mm")" "base" "sibling key retained"

echo "  reconcile_apply ok"
