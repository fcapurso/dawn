#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; fail=0
for t in test_lib test_backflow test_harvest test_upgrade; do
  echo "### $t"; bash "$HERE/tests/$t.sh" || fail=1
done
echo "### test_promote"; DAWN_PROMOTE_REF=refs/remotes/origin/current bash "$HERE/tests/test_promote.sh" || fail=1
exit $fail
