#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
BF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../dawn-backflow" && pwd)/backflow.sh"
run(){ ( cd "$1" && DAWN_CURRENT_REF=current DAWN_STAGING_REMOTE_REF=staging_remote \
         DAWN_SYNC_MARKER_NOPUSH=1 bash "$BF" "${@:2}" ); }

# 1) All agree → exit 0 without decisions
d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"k":"v"}' "base"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging_remote; git -C "$d" merge -q staging -m sync
git -C "$d" checkout -q staging
run "$d"; assert_rc "$?" 0 "all agree → exit 0"
assert_eq "$(git -C "$d" rev-list --count customizations..staging)" "1" "collapsed to one snapshot"

# 2) Any divergence without decisions → exit 22 (plan mode), staging unchanged
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"k":"base"}' "base"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
git -C "$d2" checkout -q staging_remote; git -C "$d2" merge -q staging -m sync
commit_on "$d2" current config/settings_data.json <<< '{"k":"live"}' "live edit"
git -C "$d2" checkout -q staging
before2=$(git -C "$d2" rev-parse staging)
run "$d2"; assert_rc "$?" 22 "divergence without decisions → exit 22"
assert_eq "$(git -C "$d2" rev-parse staging)" "$before2" "plan mode leaves staging unchanged"

# 3) Divergence + decision 'staging' → apply keeps staging's value
d3=$(dawn_test_repo)
commit_on "$d3" staging config/settings_data.json <<< '{"k":"s-val"}' "base"
git -C "$d3" checkout -q current; git -C "$d3" merge -q staging -m sync
git -C "$d3" checkout -q staging_remote; git -C "$d3" merge -q staging -m sync
commit_on "$d3" current config/settings_data.json <<< '{"k":"c-val"}' "live"
git -C "$d3" checkout -q staging
dec3=$(mktemp)
printf 'config/settings_data.json\t["k"]\tstaging\n' > "$dec3"
run "$d3" --apply --decisions "$dec3"; assert_rc "$?" 0 "staging verdict → exit 0"
assert_eq "$(git -C "$d3" show staging:config/settings_data.json | jq -r .k)" "s-val" "k stays at staging value"
assert_eq "$(git -C "$d3" rev-list --count customizations..staging)" "1" "collapsed to one snapshot"
rm -f "$dec3"

# 4) Divergence + decision 'current' → apply takes current's value
d4=$(dawn_test_repo)
commit_on "$d4" staging config/settings_data.json <<< '{"k":"base"}' "base"
git -C "$d4" checkout -q current; git -C "$d4" merge -q staging -m sync
git -C "$d4" checkout -q staging_remote; git -C "$d4" merge -q staging -m sync
commit_on "$d4" current config/settings_data.json <<< '{"k":"live"}' "live"
git -C "$d4" checkout -q staging
dec4=$(mktemp)
printf 'config/settings_data.json\t["k"]\tcurrent\n' > "$dec4"
run "$d4" --apply --decisions "$dec4"; assert_rc "$?" 0 "current verdict → exit 0"
assert_eq "$(git -C "$d4" show staging:config/settings_data.json | jq -r .k)" "live" "k takes current value"
assert_eq "$(git -C "$d4" rev-list --count customizations..staging)" "1" "collapsed to one snapshot"
rm -f "$dec4"

# 5) --apply without decisions when divergence exists → GUARD (exit 10)
d5=$(dawn_test_repo)
commit_on "$d5" staging config/settings_data.json <<< '{"k":"base"}' "base"
git -C "$d5" checkout -q current; git -C "$d5" merge -q staging -m sync
git -C "$d5" checkout -q staging_remote; git -C "$d5" merge -q staging -m sync
commit_on "$d5" current config/settings_data.json <<< '{"k":"live"}' "live"
git -C "$d5" checkout -q staging
before5=$(git -C "$d5" rev-parse staging)
run "$d5" --apply; assert_rc "$?" 10 "apply without decisions → GUARD"
assert_eq "$(git -C "$d5" rev-parse staging)" "$before5" "GUARD leaves staging unchanged"

# 6) Enrichment commit is the floor — preserved, never squashed
d6=$(dawn_test_repo)
commit_on "$d6" staging snippets/foo.liquid <<< 'hello' "L2: enrichment snippet"
commit_on "$d6" staging config/settings_data.json <<< '{"a":1}' "L2: store config snapshot"
git -C "$d6" checkout -q current; git -C "$d6" merge -q staging -m sync
git -C "$d6" checkout -q staging_remote; git -C "$d6" merge -q staging -m sync
git -C "$d6" checkout -q staging
run "$d6"; assert_rc "$?" 0 "enrichment-floor: all agree → exit 0"
assert_eq "$(git -C "$d6" log -1 --format=%s staging | grep -c 'store config snapshot')" "1" "tip is the snapshot"
assert_eq "$(git -C "$d6" log -1 --format=%s staging~1)" "L2: enrichment snippet" "enrichment preserved below snapshot"

echo "  backflow ok"

# --- sync markers ---

# plan-mode: no marker write
d7=$(dawn_test_repo)
commit_on "$d7" staging config/settings_data.json <<< '{"k":"base"}' "base"
git -C "$d7" checkout -q current; git -C "$d7" merge -q staging -m sync
git -C "$d7" checkout -q staging_remote; git -C "$d7" merge -q staging -m sync
commit_on "$d7" current config/settings_data.json <<< '{"k":"live"}' "live"
git -C "$d7" checkout -q staging
run "$d7" >/dev/null
marker_after_plan=$(git -C "$d7" rev-parse --verify -q refs/dawn-sync/current 2>/dev/null || echo "MISSING")
assert_eq "$marker_after_plan" "MISSING" "plan-mode does not write the marker"

# apply-mode: writes both markers
cur_sha7=$(git -C "$d7" rev-parse current); sr_sha7=$(git -C "$d7" rev-parse staging_remote)
dec7=$(mktemp); printf 'config/settings_data.json\t["k"]\tcurrent\n' > "$dec7"
run "$d7" --apply --decisions "$dec7" >/dev/null
assert_eq "$(git -C "$d7" rev-parse refs/dawn-sync/current)" "$cur_sha7" "apply writes current marker"
assert_eq "$(git -C "$d7" rev-parse refs/dawn-sync/staging-remote)" "$sr_sha7" "apply writes sr marker"
rm -f "$dec7"

# nothing-to-fold (all agree): always writes markers even without --apply
d8=$(dawn_test_repo)
commit_on "$d8" staging config/settings_data.json <<< '{"k":"v"}' "base"
git -C "$d8" checkout -q current; git -C "$d8" merge -q staging -m sync
git -C "$d8" checkout -q staging_remote; git -C "$d8" merge -q staging -m sync
git -C "$d8" checkout -q staging
cur_sha8=$(git -C "$d8" rev-parse current); sr_sha8=$(git -C "$d8" rev-parse staging_remote)
run "$d8" >/dev/null; assert_rc "$?" 0 "nothing to fold: exit 0"
assert_eq "$(git -C "$d8" rev-parse refs/dawn-sync/current)" "$cur_sha8" "nothing-to-fold writes current marker"
assert_eq "$(git -C "$d8" rev-parse refs/dawn-sync/staging-remote)" "$sr_sha8" "nothing-to-fold writes sr marker"

echo "  backflow sync-marker ok"
