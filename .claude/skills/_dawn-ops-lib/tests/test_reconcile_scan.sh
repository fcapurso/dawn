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
