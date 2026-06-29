#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-harvest/harvest-commit.sh"

# ---------------------------------------------------------------------------
# Test 1: Single-file commit
# ---------------------------------------------------------------------------
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"
git checkout -q staging
echo '<div>generic widget</div>' > sections/new-widget.liquid
git add sections/new-widget.liquid
git commit -qm "add new-widget on staging"

msg="L1: add new-widget section

Inert: yes"
assert_rc "T1: rc=0" 0 bash "$SH" --message "$msg" --files sections/new-widget.liquid

assert_eq "T1: file in customizations" \
  "$(git show customizations:sections/new-widget.liquid)" \
  '<div>generic widget</div>'

assert_eq "T1: Inert trailer on customizations" \
  "$(git log -1 --format=%B customizations | grep '^Inert:')" \
  "Inert: yes"

assert_contains "T1: staging tip has config" \
  "$(git log -1 --format=%s staging)" "config"

# ---------------------------------------------------------------------------
# Test 2: Multi-file commit
# ---------------------------------------------------------------------------
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"
git checkout -q staging
mkdir -p locales
echo '<section>withdrawal</section>' > sections/withdrawal.liquid
echo '{"withdrawal":{"title":"Withdrawal"}}' > locales/nl.default.json
git add sections/withdrawal.liquid locales/nl.default.json
git commit -qm "add withdrawal section on staging"

msg2="L1: add withdrawal section

Inert: yes"
assert_rc "T2: rc=0" 0 bash "$SH" --message "$msg2" \
  --files sections/withdrawal.liquid locales/nl.default.json

file_count=$(git diff-tree --no-commit-id -r --name-only customizations | wc -l | tr -d ' ')
assert_eq "T2: two files in customizations commit" "$file_count" "2"

assert_eq "T2: withdrawal.liquid content" \
  "$(git show customizations:sections/withdrawal.liquid)" \
  '<section>withdrawal</section>'

assert_eq "T2: nl.default.json content" \
  "$(git show customizations:locales/nl.default.json)" \
  '{"withdrawal":{"title":"Withdrawal"}}'

# ---------------------------------------------------------------------------
# Test 3: --l1-content override
# Scenario: staging has new-widget.liquid on disk (not yet committed).
# We provide GENERIC ONLY via --l1-content; staging's tree is clean enough.
# We add it to staging first, commit, then check that the override wins.
# To avoid rebase conflict: we build the scenario so staging only touches
# assets/base.css (a different file) and the --l1-content path provides
# sections/mixed.liquid content without a staging commit touching it.
# ---------------------------------------------------------------------------
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Add mixed.liquid to staging as a commit (so harvest knows the file exists
# in the staging tree — needed for --files without override to work).
# But because we use --l1-content, harvest-commit won't checkout from staging;
# it will use the temp file. The rebase then needs to skip the staging commit
# cleanly. We stage mixed.liquid on staging SEPARATELY from what we harvest so
# there is no conflict.
#
# Simpler: just have a clean staging with a separate new file committed, and
# use --l1-content to supply mixed.liquid content from a tmp file. Because
# the override path does NOT do "git checkout staging -- <file>", staging
# never needs to have mixed.liquid committed. The rebase then sees no
# conflicting staging commit for mixed.liquid.
git checkout -q staging
echo 'SOME OTHER CHANGE' > assets/base.css
git add assets/base.css
git commit -qm "unrelated staging change"

tmpfile=$(mktemp)
echo 'GENERIC ONLY' > "$tmpfile"

msg3="L1: add mixed section

Inert: yes"
assert_rc "T3: rc=0" 0 bash "$SH" --message "$msg3" \
  --files sections/mixed.liquid \
  --l1-content "sections/mixed.liquid:$tmpfile"
rm -f "$tmpfile"

assert_eq "T3: l1-content override applied" \
  "$(git show customizations:sections/mixed.liquid)" \
  "GENERIC ONLY"

# ---------------------------------------------------------------------------
# Test 4: Guard — config file rejected
# ---------------------------------------------------------------------------
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

msg4="L1: should be rejected

Inert: yes"
assert_rc "T4: config file rejected (rc=10)" 10 bash "$SH" \
  --message "$msg4" \
  --files config/settings_data.json

# ---------------------------------------------------------------------------
# Test 5: Rebase conflict → DAWN_STOP_JUDGMENT (rc=21)
# Scenario: after the fixture, add an independent commit to customizations that
# changes sections/header-group.json. Then add a staging commit that also
# changes sections/header-group.json differently. When harvest-commit tries to
# harvest a different file (assets/base.css) and rebases staging onto
# customizations, the staging commit conflicts with the new customizations commit.
# ---------------------------------------------------------------------------
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Add a commit to customizations that changes header-group.json
git checkout -q customizations
printf '{"name":"header","L1-extra":"yes"}' > sections/header-group.json
git add sections/header-group.json
git commit -qm "L1: update header-group"

# Add a staging commit that changes header-group.json differently (based on
# the staging version which doesn't include the L1-extra key)
git checkout -q staging
printf '{"name":"header","store":true,"staging-extra":"yes"}' > sections/header-group.json
git add sections/header-group.json
git commit -qm "staging: conflicting header-group edit"

# Add a harvestable file to staging so --files is satisfied
echo 'GENERIC ASSET' > assets/new-asset.css
git add assets/new-asset.css
git commit -qm "staging: add new-asset.css"

msg5="L1: add new-asset

Inert: yes"
assert_rc "T5: rebase conflict yields rc=21" 21 bash "$SH" \
  --message "$msg5" \
  --files assets/new-asset.css

git rebase --abort 2>/dev/null || true

finish
