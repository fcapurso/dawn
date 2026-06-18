#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-harvest/harvest.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Whole-file harvest of a generic file from staging into customizations.
git checkout -q staging; echo 'GENERIC TWEAK' > assets/base.css; git commit -qam "tweak base.css on staging"
assert_rc "harvest whole-file ok" 0 bash "$SH" assets/base.css
# customizations now carries the change…
assert_eq "in customizations" "$(git show customizations:assets/base.css)" "GENERIC TWEAK"
# …and staging was rebased onto it (config snapshot still the tip)
git checkout -q staging
assert_contains "config tip preserved" "$(git log -1 --format=%s)" "config snapshot"
# guard: refuse a config file (not harvestable to L1)
assert_rc "harvest refuses config file" 10 bash "$SH" config/settings_data.json
finish
