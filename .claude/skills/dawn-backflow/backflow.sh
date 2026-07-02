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

# 3) Apply reconcile folds to every target on staging (writes files; no commit yet).
dawn::with_branch staging || exit $DAWN_GUARD
while IFS= read -r f; do
  [ -z "$f" ] && continue
  merged="$(dawn::reconcile_apply "$f" "$DECISIONS")" || exit $?
  [ -z "$merged" ] && continue
  if [ ! -f "$f" ] || [ "$(cat "$f")" != "$merged" ]; then
    mkdir -p "$(dirname "$f")"; printf '%s\n' "$merged" > "$f"
  fi
done < <(dawn::config_targets)

# 4) Collapse the contiguous config-only commit run at the tip into exactly ONE snapshot commit
#    (conventions §4: staging always ends in ONE config snapshot at the tip). The floor is the
#    first non-config (enrichment/code) commit from the top, else the customizations merge-base.
#    Enrichment commits are preserved as the floor — never squashed into the config snapshot.
cust_base="$(git merge-base staging customizations 2>/dev/null)" \
  || { echo "GUARD: no merge-base with customizations; cannot collapse snapshot" >&2; exit $DAWN_GUARD; }
[ -z "$cust_base" ] && { echo "GUARD: no merge-base with customizations" >&2; exit $DAWN_GUARD; }
floor="$cust_base"
for c in $(git rev-list staging "^$cust_base"); do   # tip-first
  dawn::_commit_is_config_only "$c" || { floor="$c"; break; }
done

git add -A
git reset -q --soft "$floor"
if git diff --cached --quiet; then
  git commit -q --allow-empty -m "L2: store config snapshot (reconciled)"
  echo "Nothing to reconcile; staging config collapsed to one empty snapshot at the tip."
else
  git commit -q -m "L2: store config snapshot (reconciled)"
  echo "Backflow complete: staging config collapsed into one snapshot at the tip."
fi
exit $DAWN_OK
