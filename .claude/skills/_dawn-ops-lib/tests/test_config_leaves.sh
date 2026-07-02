#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
d=$(dawn_test_repo)

# A section-group-like file with a nested settings object and an array.
commit_on "$d" staging sections/footer-group.json <<'JSON'
{
  "sections": {
    "footer": {
      "type": "footer",
      "settings": { "show_withdrawal_link": true, "margin_top": 48 },
      "block_order": ["a","b"]
    }
  }
}
JSON

leaves=$(in_repo "$d" 'dawn::config_leaves staging sections/footer-group.json')
assert_contains "$leaves" '["sections","footer","settings","show_withdrawal_link"]	true'
assert_contains "$leaves" '["sections","footer","settings","margin_top"]	48'
assert_contains "$leaves" '["sections","footer","type"]	"footer"'
assert_contains "$leaves" '["sections","footer","block_order"]	["a","b"]'

# Missing file => no output
empty=$(in_repo "$d" 'dawn::config_leaves staging sections/does-not-exist.json')
assert_eq "$empty" "" "absent file => empty"

# Suffix class keeps only settings leaves
commit_on "$d" staging templates/page.withdrawal.json <<'JSON'
{
  "sections": {
    "wf": { "type": "withdrawal-form", "settings": { "heading": "Herroeping" } }
  },
  "order": ["wf"]
}
JSON
sfx=$(in_repo "$d" 'dawn::config_leaves staging templates/page.withdrawal.json')
assert_contains "$sfx" '["sections","wf","settings","heading"]	"Herroeping"'
assert_not_contains "$sfx" '"type"'
assert_not_contains "$sfx" '"order"'

echo "  config_leaves ok"
