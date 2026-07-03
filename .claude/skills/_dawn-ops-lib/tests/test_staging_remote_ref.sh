#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

d=$(dawn_test_repo)
out=$(in_repo "$d" 'dawn::staging_remote_ref')
assert_eq "$out" "staging_remote" "test seam wins over remote-ref detection"

echo "  staging_remote_ref ok"
