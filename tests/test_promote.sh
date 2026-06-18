#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-promote/promote.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# With backflow pending (origin/current ahead of staging) → guard, rc 10, no push.
assert_rc "promote blocks when backflow pending" 10 bash "$SH"

# Sync staging to current (backflow), then promote without --confirm-live → STOP-live rc 20.
git checkout -q staging; git checkout -q origin/current -- config/settings_data.json; git commit -qm "sync"
assert_rc "promote stops for live confirm" 20 bash "$SH"
# origin/current must be UNCHANGED (no push happened)
assert_eq "current untouched pre-confirm" "$(git rev-parse refs/remotes/origin/current)" "$(git rev-parse current)"

# A config-archive tag was created at the pre-promote current.
git tag | grep -q '^config-archive/' && _pass "archive tag created" || _fail "archive tag created"

# With --confirm-live → rc 0 and origin/current now equals staging.
assert_rc "promote live succeeds with confirm" 0 bash "$SH" --confirm-live
assert_eq "current == staging after promote" "$(git rev-parse refs/remotes/origin/current)" "$(git rev-parse staging)"
finish
