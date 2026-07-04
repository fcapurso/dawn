#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"
run(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
         DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" "${@:2}" ); }

# 1) origin/staging drift requires explicit decision; plan shows key detail
d=$(dawn_test_repo)
commit_on "$d" staging templates/page.withdrawal.json \
  <<< '{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":36}}}}' "base"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
commit_on "$d" staging_remote templates/page.withdrawal.json \
  <<< '{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":0}}}}' "bot edit"
git -C "$d" checkout -q staging
before=$(git -C "$d" rev-parse staging)
plan_out=$(run "$d" 2>&1); assert_rc "$?" 22 "staging_remote drift: plan stops for approval"
assert_eq "$(git -C "$d" rev-parse staging)" "$before" "plan-only run leaves staging untouched"
assert_contains "$plan_out" '"padding_bottom"' "plan report names the key"

# 2) staging_remote drift with 'staging_remote' verdict → folds preview value
dec=$(mktemp)
printf 'templates/page.withdrawal.json\t["sections","wf","settings","padding_bottom"]\tstaging_remote\n' > "$dec"
run "$d" --apply --decisions "$dec"; assert_rc "$?" 0 "staging_remote verdict: apply ok"
assert_eq "$(git -C "$d" show staging:templates/page.withdrawal.json \
  | jq -r .sections.wf.settings.padding_bottom)" "0" "preview value folded in"
rm -f "$dec"

# 3) staging_remote drift with 'staging' verdict → keeps staging's value
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"col":"base"}' "base"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging_remote config/settings_data.json <<< '{"col":"red"}' "bot edit"
git -C "$d3" checkout -q staging
dec3=$(mktemp)
printf 'config/settings_data.json\t["col"]\tstaging\n' > "$dec3"
run "$d3" --apply --decisions "$dec3"; assert_rc "$?" 0 "staging verdict: apply ok"
assert_eq "$(git -C "$d3" show staging:config/settings_data.json | jq -r .col)" "base" "staging value kept (bot edit rejected)"
rm -f "$dec3"

# 4) Non-config drift conflict (locale file, same line edited both places) → GUARD
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
commit_on "$d4" staging_remote locales/nl.json <<< '{"a":"bot-value","b":"base"}'
git -C "$d4" checkout -q staging
commit_on "$d4" staging locales/nl.json <<< '{"a":"staging-value","b":"base"}'
before4=$(git -C "$d4" rev-parse staging)
run "$d4"; assert_rc "$?" 10 "non-config drift conflict: GUARD"
assert_eq "$(git -C "$d4" rev-parse staging)" "$before4" "GUARD leaves staging untouched"

# 5) Plan report shows per-key detail for all divergent keys
d5=$(dawn_test_repo)
commit_on "$d5" staging config/settings_data.json <<< '{"col":"base","img":"base"}' "base"
git -C "$d5" checkout -q current; git -C "$d5" merge -q staging -m sync
git -C "$d5" checkout -q staging_remote; git -C "$d5" merge -q staging -m sync
commit_on "$d5" staging_remote config/settings_data.json <<< '{"col":"red","img":"abc"}' "preview edits"
git -C "$d5" checkout -q staging
plan5=$(run "$d5" 2>&1); assert_rc "$?" 22 "plan stops for approval"
assert_contains "$plan5" '"col"' "plan shows col key"
assert_contains "$plan5" '"img"' "plan shows img key"

echo "  backflow_drift ok"
