#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-ship/ship.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Setup: add an inert orphan commit on customizations
git checkout -q customizations
mkdir -p sections
echo '<div>withdrawal form</div>' > sections/withdrawal.liquid
git add sections/withdrawal.liquid; git commit -qm "L1: add withdrawal section (inert)"
INERT_COMMIT=$(git rev-parse HEAD)

# Add an active commit on customizations (edits always-reachable header-group)
echo '{"name":"header","v":99}' > sections/header-group.json
git add sections/header-group.json; git commit -qm "L1: update header (active)"
ACTIVE_COMMIT=$(git rev-parse HEAD)

git checkout -q staging

# 1. NEEDS_JUDGMENT: commit with a suffix template → rc 21
git checkout -q customizations
mkdir -p templates
echo '{}' > templates/page.herroeping.json
git add templates/page.herroeping.json; git commit -qm "L1: withdrawal template (needs judgment)"
NJ_COMMIT=$(git rev-parse HEAD)
git checkout -q staging
assert_rc "ship stops for needs_judgment" 21 bash "$SH" "$NJ_COMMIT"

# 2. Inert commit without --confirm-live → rc 20 (STOP-live)
out=$(bash "$SH" "$INERT_COMMIT" 2>&1 || true)
echo "$out" | grep -qi "inert\|ALL_INERT\|classifier" && _pass "inert report shown" || _fail "inert report shown" "$out"
assert_rc "inert commit stops for live confirm" 20 bash "$SH" "$INERT_COMMIT"

# 3. Active commit without --confirm-live → rc 20 and shows smoke-test prompt
out=$(bash "$SH" "$ACTIVE_COMMIT" 2>&1 || true)
echo "$out" | grep -qi "smoke\|test\|active\|HAS_ACTIVE" && _pass "active report shown" || _fail "active report shown" "$out"
assert_rc "active commit stops for live confirm" 20 bash "$SH" "$ACTIVE_COMMIT"

# 4. Inert commit with --confirm-live → rc 0, rollback tag created (test seam: DAWN_SHIP_PUSH=mock)
export DAWN_SHIP_PUSH=mock
assert_rc "inert ship with confirm succeeds" 0 bash "$SH" "$INERT_COMMIT" --confirm-live
# rollback tag must exist
git tag | grep -q '^ship-rollback/' && _pass "rollback tag created" || _fail "rollback tag created"
unset DAWN_SHIP_PUSH

# 5. Commit not reachable from customizations → guard (rc 10)
git checkout -q staging
echo 'staging-only' > assets/staging-only.css
git add assets/staging-only.css; git commit -qm "staging-only commit"
STAGING_ONLY=$(git rev-parse HEAD)
assert_rc "ship refuses non-customizations commit" 10 bash "$SH" "$STAGING_ONLY"

finish
