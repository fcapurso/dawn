#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
d=$(dawn_test_repo)

# A full-config template WITH a JSONC header comment, present on base+current; staging tweaks a setting.
printf '/* comment */\n{"sections":{"m":{"settings":{"heading":"base"}}}}\n' | \
  commit_on "$d" staging templates/product.json "base"
git -C "$d" checkout -q current; git -C "$d" merge -q staging -m sync
printf '/* comment */\n{"sections":{"m":{"settings":{"heading":"S"}}}}\n' | \
  commit_on "$d" staging templates/product.json "staging tweak"

merged=$(in_repo "$d" 'dawn::reconcile_apply templates/product.json /dev/null')
# header preserved on its own first line
assert_eq "$(head -1 <<< "$merged")" "/* comment */" "JSONC header on its own line"
# body still valid JSON after stripping the header, and staging-ahead value kept
val=$(printf '%s' "$merged" | perl -0pe 's{^\s*/\*.*?\*/\s*}{}s' | jq -r '.sections.m.settings.heading')
assert_eq "$val" "S" "staging-ahead heading kept, body parses"

# A file WITHOUT a header must NOT gain a leading blank line
d2=$(dawn_test_repo)
commit_on "$d2" staging config/settings_data.json <<< '{"a":"base"}' "base"
git -C "$d2" checkout -q current; git -C "$d2" merge -q staging -m sync
commit_on "$d2" staging config/settings_data.json <<< '{"a":"S"}' "tweak"
merged2=$(in_repo "$d2" 'dawn::reconcile_apply config/settings_data.json /dev/null')
first="$(head -1 <<< "$merged2")"
assert_eq "$([ -n "$first" ] && echo nonblank || echo blank)" "nonblank" "no leading blank line when headerless"

echo "  reconcile_header ok"
