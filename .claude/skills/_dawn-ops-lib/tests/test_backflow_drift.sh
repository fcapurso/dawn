#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"
run(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote bash "$BF" "${@:2}" ); }

# 1) Clean config-class drift fold (this incident's shape): origin/staging has a suffix-template
#    settings edit local staging never fetched. Plan reports it; --apply folds it.
d=$(dawn_test_repo)
commit_on "$d" staging templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":36}}}}
JSON
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
commit_on "$d" staging_remote templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":0}}}}
JSON
git -C "$d" checkout -q staging
before=$(git -C "$d" rev-parse staging)
run "$d"; assert_rc "$?" 22 "clean drift: plan stops for approval"
assert_eq "$(git -C "$d" rev-parse staging)" "$before" "clean drift: plan-only run untouched"
run "$d" --apply; assert_rc "$?" 0 "clean drift: apply ok"
assert_eq "$(git -C "$d" show staging:templates/page.withdrawal.json | jq -r .sections.wf.settings.padding_bottom)" "0" "bot edit folded"

# 2) Config-class drift collision: same setting edited both live (staging_remote) and locally.
d2=$(dawn_test_repo)
commit_on "$d2" staging templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":36}}}}
JSON
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
commit_on "$d2" staging templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":10}}}}
JSON
commit_on "$d2" staging_remote templates/page.withdrawal.json <<'JSON'
{"sections":{"wf":{"type":"withdrawal-form","settings":{"padding_bottom":0}}}}
JSON
git -C "$d2" checkout -q staging
run "$d2"; assert_rc "$?" 21 "drift collision: stops for decision"
decisions=$(mktemp)
printf 'templates/page.withdrawal.json\t["sections","wf","settings","padding_bottom"]\tvalue:0\n' > "$decisions"
run "$d2" --decisions "$decisions"; assert_rc "$?" 22 "drift collision: plan resolves, waits for apply"
run "$d2" --apply --decisions "$decisions"; assert_rc "$?" 0 "drift collision: apply ok"
assert_eq "$(git -C "$d2" show staging:templates/page.withdrawal.json | jq -r .sections.wf.settings.padding_bottom)" "0" "collision resolved to entered value"
rm -f "$decisions"

# 3) Non-config drift conflict (locale file, same line edited both places) -> GUARD, nothing written.
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" staging_remote locales/nl.json <<'JSON'
{
  "a": "bot-value",
  "b": "base"
}
JSON
git -C "$d3" checkout -q staging
commit_on "$d3" staging locales/nl.json <<'JSON'
{
  "a": "staging-value",
  "b": "base"
}
JSON
before3=$(git -C "$d3" rev-parse staging)
run "$d3"; assert_rc "$?" 10 "non-config drift conflict: GUARD"
assert_eq "$(git -C "$d3" rev-parse staging)" "$before3" "GUARD leaves staging untouched"

# 4) Plan/apply consistency: apply's commit matches what the immediately preceding plan reported.
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "config snapshot"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
commit_on "$d4" current config/settings_data.json <<< '{"k":"live"}'
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging
plan_out=$(run "$d4"); assert_rc "$?" 22 "plan/apply consistency: plan stops"
apply_out=$(run "$d4" --apply); assert_rc "$?" 0 "plan/apply consistency: apply ok"
assert_eq "$(git -C "$d4" show staging:config/settings_data.json | jq -r .k)" "live" "apply matches what plan reported"
assert_contains "$plan_out" "config/settings_data.json" "plan report named the folded file"

echo "  backflow_drift ok"
