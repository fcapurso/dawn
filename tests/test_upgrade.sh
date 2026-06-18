#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-upgrade/upgrade.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Create a new "upstream release" tag advancing vanilla with a non-conflicting file.
git checkout -q dawn-vanilla; echo '/* v2 */' > assets/component-new.css; git commit -qam "vanilla v2"; git tag vNEXT
git checkout -q staging
assert_rc "upgrade ff+rebase ok" 0 bash "$SH" vNEXT
# dawn-vanilla advanced to the tag
assert_eq "vanilla ffd" "$(git rev-parse dawn-vanilla)" "$(git rev-parse vNEXT)"
# customizations + staging now contain the new upstream file
assert_eq "staging has upstream file" "$(git show staging:assets/component-new.css)" "/* v2 */"
# and still has L1 + config tip
assert_contains "L1 survived" "$(git log customizations --oneline)" "L1: inventory status"
assert_contains "config tip survived" "$(git log -1 --format=%s staging)" "config snapshot"

# Conflict case: make customizations and a new tag edit the same line → STOP rc 21.
git checkout -q dawn-vanilla; echo 'CONFLICT-A' > sections/main-product.liquid; git commit -qam "vanilla v3"; git tag vCONF
assert_rc "upgrade halts on conflict" 21 bash "$SH" vCONF
git rebase --abort 2>/dev/null || true
finish
