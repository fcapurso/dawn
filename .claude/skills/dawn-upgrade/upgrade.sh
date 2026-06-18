#!/usr/bin/env bash
# Usage: upgrade.sh <upstream-tag>   ff dawn-vanilla -> rebase customizations -> rebase staging.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
tag="${1:?usage: upgrade.sh <upstream-tag>}"

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD

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
