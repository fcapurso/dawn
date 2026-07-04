#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
# Test seam: in tests, set DAWN_PROMOTE_REF=refs/remotes/origin/current and DAWN_PUSH="git update-ref"
PUSH="${DAWN_PUSH:-git push --force-with-lease}"
REMOTE="${DAWN_REMOTE:-origin}"

dawn::assert_stage_push_current || exit $DAWN_GUARD
dawn::assert_backflow_not_pending || exit $DAWN_GUARD
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
  $PUSH "$REMOTE" staging || { echo "GUARD: push to $REMOTE staging failed; markers not updated" >&2; exit $DAWN_GUARD; }
  $PUSH "$REMOTE" staging:current || { echo "GUARD: push to $REMOTE staging:current failed; markers not updated" >&2; exit $DAWN_GUARD; }
fi
# After promote, staging / origin/staging / origin/current are all identical — both sync markers
# (used by dawn::reconcile_scan's base computation) must reflect that new shared state, or the
# next backflow run reasons from a stale pre-promote base (see the design doc's "post-promote
# regression" scenario: a value promote just pushed everywhere can look like an unresolved
# collision the next time it's genuinely edited on just one side). Only reached once both pushes
# above have actually succeeded — a partial-failure promote must not advance the markers past
# what's really live (this script has no `set -e`, so without the explicit `|| exit` above, a
# failed push wouldn't have stopped execution before reaching this point).
promoted_sha="$(git rev-parse staging)"
dawn::sync_marker_set current "$promoted_sha"
dawn::sync_marker_set staging-remote "$promoted_sha"
echo "Promoted staging -> current."
exit $DAWN_OK
