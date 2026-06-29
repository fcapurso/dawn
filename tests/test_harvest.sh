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

# --- Trailer tests (fresh fixture) ---
FIX2=$(bash "$HERE/tests/fixture.sh"); cd "$FIX2"

# Harvest an orphan file (sections/new-widget.liquid is not in the reachable set) → Inert: yes
git checkout -q staging
echo '<div>new widget</div>' > sections/new-widget.liquid
git add sections/new-widget.liquid; git commit -qm "add new-widget on staging"
bash "$SH" sections/new-widget.liquid
trailer=$(git log -1 --format=%B customizations | grep '^Inert:')
assert_eq "orphan harvest trailer Inert: yes" "$trailer" "Inert: yes"

# Harvest a reachable file (layout/theme.liquid — layout files are always reachable) → Inert: no
git checkout -q staging
mkdir -p layout; echo '<!DOCTYPE html><html></html>' > layout/theme.liquid
git add layout/theme.liquid; git commit -qm "add layout on staging"
bash "$SH" layout/theme.liquid
trailer=$(git log -1 --format=%B customizations | grep '^Inert:')
assert_eq "reachable harvest trailer Inert: no" "$trailer" "Inert: no"

# Harvest a suffix template (templates/page.foo.json) → Inert: needs_judgment
git checkout -q staging
echo '{}' > templates/page.foo.json
git add templates/page.foo.json; git commit -qm "add page.foo template on staging"
bash "$SH" templates/page.foo.json
trailer=$(git log -1 --format=%B customizations | grep '^Inert:')
assert_eq "suffix template harvest trailer Inert: needs_judgment" "$trailer" "Inert: needs_judgment"

finish
