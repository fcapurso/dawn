#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
source "$HERE/.claude/skills/_dawn-ops-lib/dawn-ops.sh"
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Helper: make a commit with a given file content and classify it.
classify_commit(){
  local file="$1" content="$2"
  echo "$content" > "$file"
  git add "$file"; git commit -qm "test: $file"
  dawn::classify_changes HEAD 2>/dev/null
}

git checkout -q customizations

# 1. New orphan section (not referenced by any reachable template) → inert
mkdir -p sections
out=$(classify_commit sections/orphan-widget.liquid '<div>new</div>')
assert_contains "orphan section is inert" "$out" "inert sections/orphan-widget.liquid"
assert_contains "orphan verdict ALL_INERT" "$out" "VERDICT ALL_INERT"

# 2. Edit to always-reachable layout file → active
mkdir -p layout
out=$(classify_commit layout/theme.liquid '{% render "orphan-widget" %}')
assert_contains "layout edit is active" "$out" "active layout/theme.liquid"
assert_contains "active verdict HAS_ACTIVE" "$out" "VERDICT HAS_ACTIVE"

# 3. New suffix template (page.herroeping.json) → needs_judgment
mkdir -p templates
out=$(classify_commit templates/page.herroeping.json '{"sections":{}}')
assert_contains "suffix template is needs_judgment" "$out" "needs_judgment templates/page.herroeping.json"
assert_contains "needs_judgment verdict" "$out" "VERDICT NEEDS_JUDGMENT"

# 4. Additive locale: add a brand-new locale file (no `-` lines in diff) → inert
mkdir -p locales
printf '{\n  "hello": "world"\n}\n' > locales/en.default.json
git add locales/en.default.json; git commit -qm "test: locales/en.default.json"
out=$(dawn::classify_changes HEAD 2>/dev/null)
assert_contains "additive locale is inert" "$out" "inert locales/en.default.json"

# 5. Changed existing locale value → active
printf '{\n  "hello": "CHANGED"\n}\n' > locales/en.default.json
git add locales/en.default.json; git commit -qm "test: locales/en.default.json"
out=$(dawn::classify_changes HEAD 2>/dev/null)
assert_contains "changed locale value is active" "$out" "active locales/en.default.json"

# 5b. Additive key to EXISTING locale file → inert (more realistic than new file)
# Create base with 2 keys, then in next commit add a 3rd key only (no value changes)
echo '{}' > locales/nl.default.json
git add locales/nl.default.json; git commit -qm "init: empty nl locale"
printf '{\n  "hello": "wereld",\n  "goodbye": "dag"\n}\n' > locales/nl.default.json
git add locales/nl.default.json; git commit -qm "base: nl locale with 2 keys"
# Now add a 3rd key without changing any existing values
printf '{\n  "hello": "wereld",\n  "goodbye": "dag",\n  "thanks": "dank"\n}\n' > locales/nl.default.json
git add locales/nl.default.json; git commit -qm "feat: add thanks key to nl locale"
# Classify only the latest commit (which adds the key)
out=$(dawn::classify_changes HEAD 2>/dev/null)
assert_contains "add key to existing locale is inert" "$out" "inert locales/nl.default.json"

# 6. Mixed commit: orphan section + reachable section → HAS_ACTIVE
git checkout -q customizations
echo '<div>orphan2</div>' > sections/orphan2.liquid
# header-group.json is always reachable
echo '{"name":"header","v":2}' > sections/header-group.json
git add sections/orphan2.liquid sections/header-group.json
git commit -qm "mixed: orphan + reachable"
out=$(dawn::classify_changes HEAD 2>/dev/null)
assert_contains "mixed: orphan2 inert" "$out" "inert sections/orphan2.liquid"
assert_contains "mixed: header active" "$out" "active sections/header-group.json"
assert_contains "mixed verdict HAS_ACTIVE" "$out" "VERDICT HAS_ACTIVE"

finish
