#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
LIB="$HERE/.claude/skills/_dawn-ops-lib/dawn-ops.sh"

# === Test Case 1: Orphan section → inert L1 ===
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"
source "$LIB"
git checkout -q staging
echo '<div>widget</div>' > sections/new-widget.liquid
git add sections/new-widget.liquid; git commit -qm "add new-widget on staging"
output=$(dawn::harvest_candidates)
assert_contains "orphan section has inert verdict" "$output" "inert"
assert_contains "orphan section has L1 hint" "$output" "L1"
assert_contains "orphan section filename in output" "$output" "sections/new-widget.liquid"

# === Test Case 2: Layout file → active L1 ===
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"
source "$LIB"
git checkout -q staging
mkdir -p layout; echo '<!DOCTYPE html><html></html>' > layout/theme.liquid
git add layout/theme.liquid; git commit -qm "add layout on staging"
output=$(dawn::harvest_candidates)
line=$(echo "$output" | grep "layout/theme.liquid" || true)
assert_contains "layout file has active verdict" "$line" "active"
assert_contains "layout file has L1 hint" "$line" "L1"

# === Test Case 3: File with store keyword → L2 hint ===
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"
source "$LIB"
git checkout -q staging
echo 'redirect to zogezeept.com' > sections/store-info.liquid
git add sections/store-info.liquid; git commit -qm "add store-info on staging"
output=$(dawn::harvest_candidates)
line=$(echo "$output" | grep "store-info.liquid" || true)
assert_contains "store keyword file has L2 hint" "$line" "L2"

# === Test Case 4: Suffix template → needs_judgment ===
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"
source "$LIB"
git checkout -q staging
echo '{"sections":{}}' > templates/product.soap.json
git add templates/product.soap.json; git commit -qm "add product.soap template on staging"
output=$(dawn::harvest_candidates)
line=$(echo "$output" | grep "product.soap.json" || true)
assert_contains "suffix template has needs_judgment verdict" "$line" "needs_judgment"

# === Test Case 5: Config file excluded ===
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"
source "$LIB"
git checkout -q staging
# config/settings_data.json is already changed in the fixture's config snapshot commit
output=$(dawn::harvest_candidates)
case "$output" in
  *config/settings_data.json*)
    _fail "config file excluded" "output contains config/settings_data.json"
    ;;
  *)
    _pass "config file excluded"
    ;;
esac

# === Test Case 6: Empty output when staging == customizations ===
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"
source "$LIB"
git checkout -q staging
git reset -q --hard customizations
output=$(dawn::harvest_candidates)
assert_eq "empty output when no changes" "$output" ""

finish
