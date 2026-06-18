#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-backflow/backflow.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Config-only churn on current → Case A: staging config-tip amended, commit COUNT unchanged.
before=$(git rev-list --count customizations..staging)
assert_rc "backflow config-only ok" 0 bash "$SH"
after=$(git rev-list --count customizations..staging)
assert_eq "no new commit (amended tip)" "$after" "$before"
# staging config now matches current's config
assert_eq "config synced" "$(git show staging:config/settings_data.json)" "$(git show origin/current:config/settings_data.json)"
# guard: refuse on dirty tree
echo x >> config/settings_data.json
assert_rc "backflow guards dirty tree" 10 bash "$SH"
git checkout -q -- config/settings_data.json
finish
