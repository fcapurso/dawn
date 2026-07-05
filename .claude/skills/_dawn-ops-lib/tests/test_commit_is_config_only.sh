#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Helper: get sha of tip of a branch in repo $1
tip(){ git -C "$1" rev-parse "$2"; }

# 1) Commit touching only config/settings_data.json → returns 0 (config-only)
d1=$(dawn_test_repo)
commit_on "$d1" staging config/settings_data.json <<< '{"col":"red"}' "settings only"
sha1=$(tip "$d1" staging)
in_repo "$d1" "dawn::_commit_is_config_only $sha1"; assert_rc "$?" 0 "settings_data.json → config-only"

# 2) Commit touching only a suffix template JSON → returns 0 (config-only)
d2=$(dawn_test_repo)
commit_on "$d2" staging templates/index.my-template.json <<< '{"sections":{}}' "suffix template"
sha2=$(tip "$d2" staging)
in_repo "$d2" "dawn::_commit_is_config_only $sha2"; assert_rc "$?" 0 "suffix template json → config-only"

# 3) Commit touching ONLY a locale file → returns 0 (locale files are skipped by the function,
#    not treated as non-config; locale-only commits are considered config-compatible)
d3=$(dawn_test_repo)
commit_on "$d3" staging locales/nl.json <<< '{"a":"b"}' "locale edit"
sha3=$(tip "$d3" staging)
in_repo "$d3" "dawn::_commit_is_config_only $sha3"; assert_rc "$?" 0 "locale-only commit → config-only (locale skipped)"

# 4) Commit touching a liquid snippet → returns 1 (not config-class)
d4=$(dawn_test_repo)
commit_on "$d4" staging snippets/foo.liquid <<< '{{ "hello" }}' "snippet edit"
sha4=$(tip "$d4" staging)
rc4=0; in_repo "$d4" "dawn::_commit_is_config_only $sha4" || rc4=$?
assert_rc "$rc4" 1 "liquid snippet → NOT config-only"

# 5) Commit touching both a config file AND a liquid file → returns 1
d5=$(dawn_test_repo)
git -C "$d5" checkout -q staging
mkdir -p "$d5/config" "$d5/snippets"
echo '{"col":"blue"}' > "$d5/config/settings_data.json"
echo '{{ "hello" }}' > "$d5/snippets/bar.liquid"
git -C "$d5" add -A
git -C "$d5" commit -q -m "mixed commit"
sha5=$(tip "$d5" staging)
rc5=0; in_repo "$d5" "dawn::_commit_is_config_only $sha5" || rc5=$?
assert_rc "$rc5" 1 "config + liquid → NOT config-only"

echo "  commit_is_config_only ok"
