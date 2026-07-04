#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
PUSH="${DAWN_PUSH:-git push --force-with-lease}"
REMOTE="${DAWN_REMOTE:-origin}"

dawn::assert_backflow_not_pending || exit $DAWN_GUARD
dawn::assert_staging_clean || exit $DAWN_GUARD

if [ -n "${DAWN_STAGE_PUSH_REF:-}" ]; then      # test path: move local ref
  git update-ref "$DAWN_STAGE_PUSH_REF" staging
else                                             # real path: force-push staging onto origin/staging
  $PUSH "$REMOTE" staging || { echo "GUARD: push to $REMOTE staging failed; marker not updated" >&2; exit $DAWN_GUARD; }
fi
sha="$(git rev-parse staging)"
dawn::sync_marker_set staging-remote "$sha"
echo "Pushed staging -> origin/staging (preview theme). Test it there; run dawn-promote when ready to go live."
exit $DAWN_OK
