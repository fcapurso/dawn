#!/usr/bin/env bash
# Usage: harvest.sh <path> [--hunks]   Lift a generic change from staging into customizations (L1).
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
file="${1:?usage: harvest.sh <path> [--hunks]}"; mode="${2:-}"

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD
# refuse config-snapshot files — those are L2, not L1
while IFS= read -r c; do [ "$c" = "$file" ] && { echo "GUARD: $file is config (L2), not harvestable to L1" >&2; exit $DAWN_GUARD; }; done < <(dawn::config_files)

if [ "$mode" = "--hunks" ]; then
  echo "STOP: $file mixes generic + store-specific lines; needs per-hunk selection." >&2
  echo "Agent: split the hunks with the user (generic -> L1), then re-run on a trimmed file." >&2
  exit $DAWN_STOP_JUDGMENT
fi

dawn::with_branch customizations || exit $DAWN_GUARD
git checkout staging -- "$file"
git add "$file"; git commit -q -m "L1: harvest $file"
git checkout -q staging
git rebase -q customizations || { echo "STOP: rebase conflict bringing harvest into staging" >&2; exit $DAWN_STOP_JUDGMENT; }
echo "Harvested $file into customizations; staging rebased."
exit $DAWN_OK
