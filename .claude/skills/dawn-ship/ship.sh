#!/usr/bin/env bash
# Usage: ship.sh <commit-ish> [--confirm-live]
# Cherry-picks a classified commit from customizations onto current (append-only).
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

commit="${1:?usage: ship.sh <commit-ish> [--confirm-live]}"
confirm="${2:-}"

# Resolve to a full sha
sha=$(git rev-parse --verify "${commit}^{commit}" 2>/dev/null) \
  || { echo "GUARD: cannot resolve commit '$commit'" >&2; exit $DAWN_GUARD; }

# Commit must be reachable from customizations (not just staging or elsewhere)
if ! git merge-base --is-ancestor "$sha" customizations 2>/dev/null; then
  echo "GUARD: $sha is not reachable from customizations — only cherry-pick from customizations" >&2
  exit $DAWN_GUARD
fi

# Classify the commit
echo "=== Classifier report ===" >&2
classify_out=$(dawn::classify_changes "$sha" 2>&1)
echo "$classify_out" >&2
verdict=$(echo "$classify_out" | grep '^VERDICT ' | awk '{print $2}')

# NEEDS_JUDGMENT → stop unless operator has explicitly confirmed
if [ "$verdict" = "NEEDS_JUDGMENT" ]; then
  if [ "$confirm" != "--confirm-live" ]; then
    echo "" >&2
    echo "STOP: commit contains a new suffix template. Confirm in Shopify admin that NO page or" >&2
    echo "      product is currently assigned to this template, then re-run with --confirm-live." >&2
    exit $DAWN_STOP_JUDGMENT
  fi
  echo "WARNING: shipping a suffix template — operator confirmed no resource is bound." >&2
fi

# Show the full diff the operator will be shipping
echo "" >&2
echo "=== Full diff to be shipped ===" >&2
git diff "${sha}^..${sha}" >&2

# Gate: require --confirm-live
if [ "$confirm" != "--confirm-live" ]; then
  echo "" >&2
  echo "Classifier verdict: $verdict" >&2
  if [ "$verdict" = "HAS_ACTIVE" ]; then
    echo "" >&2
    echo "ACTIVE changes detected. Before confirming, run a manual smoke test:" >&2
    echo "  1. Open the live storefront in an incognito window." >&2
    echo "  2. Visit the homepage, a product page, cart, and any recently changed page." >&2
    echo "  3. Confirm no visual regressions, no JS errors in console." >&2
  fi
  echo "" >&2
  echo "STOP: review the classifier report and diff above, then re-run with --confirm-live." >&2
  exit $DAWN_STOP_LIVE
fi

# Archive a rollback tag at the pre-ship current
stamp="ship-rollback/$(date +%Y-%m-%d-%H%M%S)"
git tag -f "$stamp" refs/remotes/origin/current >/dev/null 2>&1 \
  || git tag -f "$stamp" origin/current
echo "Archived pre-ship current at tag $stamp"

# Cherry-pick onto a temp branch based on origin/current, then push
if [ "${DAWN_SHIP_PUSH:-}" = "mock" ]; then
  echo "TEST MODE: would push $sha onto current (mock)"; exit $DAWN_OK
fi

tmp_branch="__dawn-ship-tmp-$$"
git checkout -q -b "$tmp_branch" refs/remotes/origin/current \
  || { echo "GUARD: cannot create temp branch from origin/current" >&2; exit $DAWN_GUARD; }
trap "git checkout -q - 2>/dev/null || true; git branch -D '$tmp_branch' 2>/dev/null || true" EXIT
git cherry-pick --no-edit "$sha" \
  || { echo "STOP: cherry-pick conflict — resolve manually, then push with:" >&2
       echo "  git push origin $tmp_branch:current" >&2; exit $DAWN_STOP_JUDGMENT; }
git push origin "${tmp_branch}:current" \
  || { echo "GUARD: push to current failed (non-fast-forward?)" >&2; exit $DAWN_GUARD; }
# Update our local remote ref
git update-ref refs/remotes/origin/current "$(git rev-parse "$tmp_branch")"
echo "Shipped $sha onto current ($verdict)."
exit $DAWN_OK
