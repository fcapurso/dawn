#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
d=$(dawn_test_repo)

# current_ref honours the seam
out=$(in_repo "$d" 'dawn::current_ref')
assert_eq "$out" "current" "current_ref uses DAWN_CURRENT_REF"

assert_eq "$(in_repo "$d" 'dawn::config_class config/settings_data.json')" "full"   "settings_data => full"
assert_eq "$(in_repo "$d" 'dawn::config_class sections/footer-group.json')" "full"  "footer-group => full"
assert_eq "$(in_repo "$d" 'dawn::config_class templates/product.json')" "full"      "default template => full"
assert_eq "$(in_repo "$d" 'dawn::config_class templates/page.withdrawal.json')" "suffix" "suffix => suffix"
assert_eq "$(in_repo "$d" 'dawn::config_class templates/product.soap.json')" "suffix" "suffix product => suffix"
assert_eq "$(in_repo "$d" 'dawn::config_class sections/footer.liquid')" ""           "non-config => empty"
assert_eq "$(in_repo "$d" 'dawn::config_class snippets/foo.liquid')" ""              "snippet => empty"

echo "  config_class/current_ref ok"
