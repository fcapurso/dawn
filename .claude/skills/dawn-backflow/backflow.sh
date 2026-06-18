#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD
git fetch origin current --quiet 2>/dev/null || true

# Files changed on current since staging.
changed=()
while IFS= read -r line; do changed+=("$line"); done < <(
  git diff --name-only staging refs/remotes/origin/current 2>/dev/null \
    || git diff --name-only staging origin/current)
[ "${#changed[@]}" -eq 0 ] && { echo "Nothing to backflow."; exit $DAWN_OK; }

# Partition: config vs non-config. Non-config requires human judgment (enrichment vs generic).
cfg=()
while IFS= read -r line; do cfg+=("$line"); done < <(dawn::config_files)
noncfg=()
for f in "${changed[@]}"; do
  case " ${cfg[*]} " in *" $f "*) : ;; *) noncfg+=("$f");; esac
done

if [ "${#noncfg[@]}" -gt 0 ]; then
  echo "STOP: non-config changes need classification (enrichment vs generic-L1 vs ignore):" >&2
  printf '  %s\n' "${noncfg[@]}" >&2
  echo "Decide per file: enrichment -> own L2 commit; generic -> dawn-harvest; churn -> ignore." >&2
  exit $DAWN_STOP_JUDGMENT
fi

# Case A: pure config churn. Refresh config files and amend the tip config-snapshot commit.
dawn::with_branch staging || exit $DAWN_GUARD
last_msg="$(git log -1 --format=%s)"
case "$last_msg" in
  *"config snapshot"*) ;;  # tip is the config snapshot — safe to amend
  *) echo "GUARD: staging tip is not the config snapshot ('$last_msg'); fix ordering first" >&2; exit $DAWN_GUARD;;
esac
while IFS= read -r f; do git checkout refs/remotes/origin/current -- "$f" 2>/dev/null \
  || git checkout origin/current -- "$f"; done < <(printf '%s\n' "${cfg[@]}")
git commit -q --amend --no-edit
echo "Backflow complete (config snapshot amended)."
exit $DAWN_OK
