#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-upgrade/upgrade.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# --- Release selection (no tag): list candidates newer than dawn-vanilla, STOP rc 21. ---
# Build two newer release tags AHEAD of dawn-vanilla without moving the branch (detached HEAD).
git checkout -q --detach dawn-vanilla
echo a > assets/r1.css; git add -A; git commit -qm r1; git tag v9.0.0
echo b > assets/r2.css; git add -A; git commit -qm r2; git tag v9.1.0
git checkout -q staging
out=$(bash "$SH" 2>&1); rc=$?
assert_eq "no-arg STOPs for choice" "$rc" "21"
assert_contains "lists v9.0.0" "$out" "v9.0.0"
assert_contains "lists v9.1.0" "$out" "v9.1.0"

# Unknown tag → guard rc 10.
assert_rc "unknown tag guards" 10 bash "$SH" v99.99.99

# --- Happy path: direct upgrade to a tag that ff's dawn-vanilla with a non-conflicting file. ---
git checkout -q dawn-vanilla; echo '/* v2 */' > assets/component-new.css; git commit -qam "vanilla v2"; git tag vNEXT
git checkout -q staging
assert_rc "upgrade ff+rebase ok" 0 bash "$SH" vNEXT
assert_eq "vanilla ffd" "$(git rev-parse dawn-vanilla)" "$(git rev-parse vNEXT)"
assert_eq "staging has upstream file" "$(git show staging:assets/component-new.css)" "/* v2 */"
assert_contains "L1 survived" "$(git log customizations --oneline)" "L1: inventory status"
assert_contains "config tip survived" "$(git log -1 --format=%s staging)" "config snapshot"

# --- Conflict case: customizations and a new tag edit the same line → STOP rc 21. ---
git checkout -q dawn-vanilla; echo 'CONFLICT-A' > sections/main-product.liquid; git commit -qam "vanilla v3"; git tag vCONF
git checkout -q staging
assert_rc "upgrade halts on conflict" 21 bash "$SH" vCONF
git rebase --abort 2>/dev/null || true
finish
