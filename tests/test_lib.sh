#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"
source "$HERE/tests/harness.sh"
LIB="$HERE/.claude/skills/_dawn-ops-lib/dawn-ops.sh"
FIX=$(bash "$HERE/tests/fixture.sh")
cd "$FIX"; source "$LIB"

# current_branch
git checkout -q staging
assert_eq "current_branch=staging" "$(dawn::current_branch)" "staging"

# assert_not_current: ok on staging, guard on current
( git checkout -q staging; dawn::assert_not_current ); assert_eq "not_current ok on staging" "$?" "0"
( git checkout -q current; dawn::assert_not_current ); assert_eq "not_current guards on current" "$?" "10"
git checkout -q staging

# assert_clean_tree: ok clean, guard when dirty
dawn::assert_clean_tree; assert_eq "clean ok" "$?" "0"
echo dirty >> config/settings_data.json
dawn::assert_clean_tree; assert_eq "dirty guards" "$?" "10"
git checkout -q -- config/settings_data.json

# merge_base_vanilla = the upstream/main tip (the vanilla commit)
assert_eq "merge_base_vanilla" "$(dawn::merge_base_vanilla)" "$(git rev-parse refs/remotes/upstream/main)"

# config_files resolves only existing tracked config paths
out="$(dawn::config_files)"
assert_contains "config has settings_data" "$out" "config/settings_data.json"
assert_contains "config has header-group" "$out" "sections/header-group.json"
case "$out" in *product.workshop.json*) _fail "config excludes enrichment templates" "found workshop";; *) _pass "config excludes enrichment templates";; esac

# backflow_pending: true (rc 0) because origin/current has the admin commit not in staging
dawn::backflow_pending; assert_eq "backflow pending true" "$?" "0"
# after folding current into staging it should be false (rc 1)
git checkout -q staging; git checkout -q origin/current -- config/settings_data.json; git commit -qm tmp
dawn::backflow_pending; assert_eq "backflow pending false after sync" "$?" "1"

# verify_tree_equal: equal vs different
git checkout -q staging
dawn::verify_tree_equal HEAD HEAD; assert_eq "tree equal" "$?" "0"
dawn::verify_tree_equal HEAD dawn-vanilla; assert_eq "tree differ" "$?" "30"

finish
