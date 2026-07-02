#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
fail=0
for t in test_*.sh; do
  echo "== $t =="
  if bash "$t"; then echo "  ok"; else echo "  FAILED"; fail=1; fi
done
exit $fail
