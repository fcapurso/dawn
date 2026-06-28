#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-promote/promote.sh"
export DAWN_PROMOTE_REF="refs/remotes/origin/current"
export DAWN_PUSH="git update-ref"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# With backflow pending (origin/current ahead of staging) → guard, rc 10, no push.
assert_rc "promote blocks when backflow pending" 10 bash "$SH"

# Sync staging to current (backflow), then promote without --confirm-live → STOP-live rc 20.
git checkout -q staging; git checkout -q origin/current -- config/settings_data.json; git commit -qm "L2: store config snapshot"
assert_rc "promote stops for live confirm" 20 bash "$SH"
# origin/current must be UNCHANGED (no push happened)
assert_eq "current untouched pre-confirm" "$(git rev-parse refs/remotes/origin/current)" "$(git rev-parse current)"

# A config-archive tag was created at the pre-promote current.
git tag | grep -q '^config-archive/' && _pass "archive tag created" || _fail "archive tag created"

# With --confirm-live → rc 0 and origin/current now equals staging.
assert_rc "promote live succeeds with confirm" 0 bash "$SH" --confirm-live
assert_eq "current == staging after promote" "$(git rev-parse refs/remotes/origin/current)" "$(git rev-parse staging)"

# --- Cleanliness guard tests (fresh fixture) ---
FIX2=$(bash "$HERE/tests/fixture.sh"); cd "$FIX2"

# staging tip is already a config snapshot in the fresh fixture, but customizations
# is BEHIND staging (staging has an L2 commit on top) → that means staging..customizations
# has 0 commits (staging is ahead of customizations). Let's verify:
# customizations..staging > 0 but that's OK. staging..customizations == 0 means staging is ahead.
# assert_staging_clean checks staging..customizations == 0 (customizations has no commits not in staging).

# First: make staging's tip NOT a config snapshot → guard fires
git checkout -q staging
git reset -q --soft HEAD~1       # drop the config-snapshot tip
echo 'debug content' > assets/debug.css
git add assets/debug.css; git commit -qm "debug: temp experiment"
# Now staging tip is "debug: temp experiment" (not a config snapshot)
# backflow_pending would fire first if origin/current differs, so sync them first
git update-ref refs/remotes/origin/current staging
assert_rc "promote blocks when staging tip is not a config snapshot" 10 bash "$SH"

# Now fix staging: replace the bad tip with a config snapshot
git reset -q --hard HEAD~1      # go back to the commit before "debug: temp experiment"
git checkout -q origin/current -- config/settings_data.json 2>/dev/null || true
git add config/settings_data.json
git commit -qm "L2: store config snapshot"
# staging tip is now "L2: store config snapshot" which matches the pattern
# Sync origin/current to the new staging tip so backflow passes.
git update-ref refs/remotes/origin/current staging
# staging tip now contains "config snapshot" — cleanliness guard passes
# backflow check: staging and origin/current are equal → no backflow pending
# Should proceed to stop-live (rc 20)
assert_rc "promote proceeds past cleanliness check to stop-live" 20 bash "$SH"

finish
