#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

# Optional decisions file for collisions: --decisions <path>
DECISIONS=/dev/null
[ "${1:-}" = "--decisions" ] && { DECISIONS="${2:?}"; shift 2; }

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD
cur="$(dawn::current_ref)"
git fetch origin current --quiet 2>/dev/null || true
base="$(git merge-base staging "$cur" 2>/dev/null)" \
  || { echo "GUARD: no merge-base staging vs $cur" >&2; exit $DAWN_GUARD; }

# 1) Direction-aware non-config partition: only current-ahead non-config files need capture.
noncfg=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -n "$(dawn::config_class "$f")" ] && continue     # config target — handled by reconcile
  git diff --quiet "$base" "$cur" -- "$f" && continue # not current-ahead (staging-only or same)
  noncfg+=("$f")
done < <(git diff --name-only staging "$cur" -- . ':(exclude)docs/' ':(exclude).claude/')

if [ "${#noncfg[@]}" -gt 0 ]; then
  echo "STOP: current-ahead non-config changes need classification (enrichment vs generic-L1 vs ignore):" >&2
  printf '  %s\n' "${noncfg[@]}" >&2
  echo "Decide per file: enrichment -> own L2 commit; generic -> dawn-harvest; churn -> ignore." >&2
  exit $DAWN_STOP_JUDGMENT
fi

# 2) Collisions without decisions -> stop and list.
scan="$(dawn::reconcile_scan)" || exit $DAWN_GUARD
collisions="$(grep -E '^collision'$'\t' <<< "$scan" || true)"
if [ -n "$collisions" ]; then
  missing=""
  while IFS=$'\t' read -r verdict f p b s c; do
    res="$(awk -F'\t' -v ff="$f" -v pp="$p" '$1==ff && $2==pp {print $3}' "$DECISIONS" 2>/dev/null | head -1)"
    [ -z "$res" ] && missing+="$f"$'\t'"$p"$'\t'"base=$b"$'\t'"staging=$s"$'\t'"current=$c"$'\n'
  done <<< "$collisions"
  if [ -n "$missing" ]; then
    echo "STOP: config collisions need decisions (keep staging / take current / enter value):" >&2
    printf '%s' "$missing" >&2
    exit $DAWN_STOP_JUDGMENT
  fi
fi

# 3) Apply reconcile to every target on staging, then amend the config snapshot.
dawn::with_branch staging || exit $DAWN_GUARD
changed=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  merged="$(dawn::reconcile_apply "$f" "$DECISIONS")" || exit $?
  [ -z "$merged" ] && continue
  if [ ! -f "$f" ] || [ "$(cat "$f")" != "$merged" ]; then
    mkdir -p "$(dirname "$f")"; printf '%s\n' "$merged" > "$f"; changed=1
  fi
done < <(dawn::config_targets)

if [ "$changed" = "0" ]; then
  echo "Nothing to backflow (no current-ahead config; staging-ahead values already present)."
  exit $DAWN_OK
fi

git add -A
last_msg="$(git log -1 --format=%s)"
case "$last_msg" in
  *config*|*snapshot*|*settings*) git commit -q --amend --no-edit ;;
  *) git commit -q -m "L2: store config snapshot (reconciled)" ;;
esac
echo "Backflow complete (config reconciled into the snapshot)."
exit $DAWN_OK
