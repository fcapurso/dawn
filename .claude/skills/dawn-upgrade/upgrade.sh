#!/usr/bin/env bash
# Usage: upgrade.sh [<upstream-tag>]
#   No tag : fetch tags, list releases newer than dawn-vanilla, STOP (21) for you to pick.
#   <tag>  : ff dawn-vanilla -> rebase customizations -> rebase staging.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
tag="${1:-}"

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD

# Fold the fetch in (best-effort — offline must not hard-fail; we fall back to local tags).
git fetch upstream --tags --quiet 2>/dev/null \
  || echo "WARN: could not fetch upstream tags (offline?) — using local tags" >&2

# Release tags strictly ahead of dawn-vanilla (ff-able), version-sorted.
dawn_upgrade_candidates(){
  local t van; van="$(git rev-parse dawn-vanilla)"
  for t in $(git tag -l 'v[0-9]*' | sort -V); do
    git merge-base --is-ancestor dawn-vanilla "$t" 2>/dev/null || continue   # descendant => ff-able
    [ "$(git rev-parse "$t^{commit}")" = "$van" ] && continue                # skip == current
    echo "$t"
  done
}

if [ -z "$tag" ]; then
  cands="$(dawn_upgrade_candidates)"
  if [ -z "$cands" ]; then
    echo "Already at the latest available release (dawn-vanilla = $(git rev-parse --short dawn-vanilla)). Nothing to upgrade."
    exit $DAWN_OK
  fi
  echo "STOP: choose a release to upgrade to (dawn-vanilla is at $(git rev-parse --short dawn-vanilla)):" >&2
  echo "$cands" | sed 's/^/  /' >&2
  echo "Re-run: bash .claude/skills/dawn-upgrade/upgrade.sh <tag>" >&2
  exit $DAWN_STOP_JUDGMENT
fi

# --- Direct upgrade to $tag ---
if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "GUARD: tag '$tag' not found (did the upstream fetch succeed?)" >&2; exit $DAWN_GUARD; fi
git checkout -q dawn-vanilla || exit $DAWN_GUARD
if ! git merge-base --is-ancestor dawn-vanilla "$tag" 2>/dev/null; then
  echo "GUARD: $tag is not ahead of dawn-vanilla (ff not possible)" >&2; exit $DAWN_GUARD; fi
git merge --ff-only "$tag" -q || { echo "GUARD: ff to $tag failed" >&2; exit $DAWN_GUARD; }

for br in customizations staging; do
  git checkout -q "$br"
  if ! git rebase -q "$( [ "$br" = customizations ] && echo dawn-vanilla || echo customizations )"; then
    echo "STOP: rebase conflict on '$br' upgrading to $tag. Resolve with the user, then continue." >&2
    exit $DAWN_STOP_JUDGMENT
  fi
done
echo "Upgraded to $tag: dawn-vanilla ffd, customizations + staging rebased. Test on preview, then promote."
exit $DAWN_OK
