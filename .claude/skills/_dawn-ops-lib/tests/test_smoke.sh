#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

d=$(dawn_test_repo)
commit_on "$d" staging config/settings_data.json <<< '{"a":1}'
out=$(git -C "$d" show staging:config/settings_data.json)
assert_eq "$out" '{"a":1}' "smoke read"
echo "  smoke ok"
