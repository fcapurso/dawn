#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
# Test seam: in tests, set DAWN_PROMOTE_REF=refs/remotes/origin/current and DAWN_PUSH="git update-ref"
PUSH="${DAWN_PUSH:-git push --force-with-lease}"
REMOTE="${DAWN_REMOTE:-origin}"

dawn::reconcile_pending && { echo "GUARD: backflow first — origin/current has current-ahead edits not yet folded into staging" >&2; exit $DAWN_GUARD; }
dawn::assert_staging_clean || exit $DAWN_GUARD

stamp="config-archive/$(date +%Y-%m-%d-%H%M%S)"
git tag -f "$stamp" refs/remotes/origin/current >/dev/null 2>&1 || git tag -f "$stamp" origin/current
echo "Archived pre-promote current at tag $stamp"

if [ "${1:-}" != "--confirm-live" ]; then
  echo "STOP: ready to promote staging -> $REMOTE/current (LIVE)." >&2
  echo "      Re-run with --confirm-live after human approval." >&2
  git --no-pager diff --stat staging refs/remotes/origin/current -- . ':(exclude)docs/' ':(exclude).claude/' >&2 || true
  exit $DAWN_STOP_LIVE
fi

if [ -n "${DAWN_PROMOTE_REF:-}" ]; then         # test path: move local ref
  git update-ref "$DAWN_PROMOTE_REF" staging; git update-ref refs/remotes/origin/current staging
else                                            # real path: force-push staging onto current
  git push "$REMOTE" staging
  $PUSH "$REMOTE" staging:current
fi
echo "Promoted staging -> current."
exit $DAWN_OK
