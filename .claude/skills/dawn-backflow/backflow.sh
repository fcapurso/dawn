#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

# Optional decisions file for collisions: --decisions <path>
# Apply mode: --apply (default is PLAN — does the real work, then hard-resets staging back to
# where it started, so a plan-only run never leaves a lasting change).
DECISIONS=/dev/null
APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --decisions) DECISIONS="${2:?}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    *) echo "GUARD: unknown argument: $1" >&2; exit $DAWN_GUARD ;;
  esac
done

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD
cur="$(dawn::current_ref)"
staging_remote="$(dawn::staging_remote_ref)"
git fetch origin current --quiet 2>/dev/null || true
git fetch origin staging --quiet 2>/dev/null || true
git fetch origin refs/dawn-sync/current:refs/dawn-sync/current --quiet 2>/dev/null || true
git fetch origin refs/dawn-sync/staging-remote:refs/dawn-sync/staging-remote --quiet 2>/dev/null || true
base="$(git merge-base staging "$cur" 2>/dev/null)" \
  || { echo "GUARD: no merge-base staging vs $cur" >&2; exit $DAWN_GUARD; }
cur_sha="$(git rev-parse "$cur" 2>/dev/null || true)"
staging_remote_sha="$(git rev-parse "$staging_remote" 2>/dev/null || true)"

orig_sha="$(git rev-parse staging)"
dawn::with_branch staging || exit $DAWN_GUARD

# Every exit from here on that isn't a genuine success (apply-mode exit 0) must leave staging
# exactly as it started — including the plan-mode "everything's fine, please approve" exit.
_dawn_bf_abort(){ git reset -q --hard "$orig_sha" 2>/dev/null || true; exit "$1"; }

# Advance both markers to the exact commits fetched this run. Gated on --apply by default — only
# a completed --apply run counts as "fully reconciled" for the plan/report path below. Pass
# "force" to write unconditionally: the "nothing to report" fast path collapses and commits
# staging regardless of --apply (nothing external was folded, so there's nothing to approve —
# matches pre-plan/apply backflow behavior for that one case), so its marker write must be
# equally unconditional or the markers fall out of step with staging's actual ancestry.
_dawn_bf_sync_markers(){
  [ "${1:-}" = "force" ] || [ "$APPLY" = "1" ] || return 0
  dawn::sync_marker_set current "$cur_sha"
  dawn::sync_marker_set staging-remote "$staging_remote_sha"
}

report_staging_remote=()
report_current=()

# --- Step 0a: fold origin/staging's config-class drift (same leaf reconciler as current) ---
sr_scan="$(dawn::reconcile_scan "$staging_remote")" || _dawn_bf_abort $DAWN_GUARD
sr_collisions="$(grep -E '^collision'$'\t' <<< "$sr_scan" || true)"
if [ -n "$sr_collisions" ]; then
  missing=""
  while IFS=$'\t' read -r verdict f p b s c; do
    res="$(awk -F'\t' -v ff="$f" -v pp="$p" '$1==ff && $2==pp {print $3}' "$DECISIONS" 2>/dev/null | head -1)"
    [ -z "$res" ] && missing+="$f"$'\t'"$p"$'\t'"base=$b"$'\t'"staging=$s"$'\t'"origin/staging=$c"$'\n'
  done <<< "$sr_collisions"
  if [ -n "$missing" ]; then
    echo "STOP: origin/staging config collisions need decisions (keep staging / take origin/staging / enter value):" >&2
    printf '%s' "$missing" >&2
    _dawn_bf_abort $DAWN_STOP_JUDGMENT
  fi
fi
sr_config_changed=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  merged="$(dawn::reconcile_apply "$f" "$DECISIONS" "$staging_remote")" || _dawn_bf_abort $?
  [ -z "$merged" ] && continue
  if [ ! -f "$f" ] || [ "$(cat "$f")" != "$merged" ]; then
    mkdir -p "$(dirname "$f")"; printf '%s\n' "$merged" > "$f"
    report_staging_remote+=("$f")
    sr_config_changed=1
  fi
done < <(dawn::config_targets "$staging_remote")
if [ "$sr_config_changed" = "1" ]; then
  git add -A
  git commit -q -m "fold origin/staging (config)"
fi

# Must run after Step 0a's commit — dawn::nonconfig_drift_scan assumes config-class drift is
# already resolved, so it never spuriously sees a config-class file as an unresolved conflict.
# --- Step 0b: fold origin/staging's remaining (non-config) drift (raw 3-way merge) ---
nc_out="$(dawn::nonconfig_drift_scan)"; nc_rc=$?
if [ "$nc_rc" = "1" ]; then
  echo "GUARD: origin/staging conflicts with local staging in:" >&2
  sed 's/^/  /' <<< "$nc_out" >&2
  echo "Resolve manually (e.g. git checkout -b scratch-fix, git merge $staging_remote, resolve, then reapply to staging — no worktrees; see conventions.md §3b) and re-run." >&2
  _dawn_bf_abort $DAWN_GUARD
fi
if [ -n "$nc_out" ]; then
  dawn::nonconfig_drift_apply
  git add -A
  git commit -q -m "fold origin/staging (other)"
  while IFS= read -r f; do [ -n "$f" ] && report_staging_remote+=("$f"); done <<< "$nc_out"
fi

# --- Step 1: direction-aware non-config partition (current vs staging, unchanged) ---
noncfg=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -n "$(dawn::config_class "$f")" ] && continue
  git diff --quiet "$base" "$cur" -- "$f" && continue
  noncfg+=("$f")
done < <(git diff --name-only staging "$cur" -- . ':(exclude)docs/' ':(exclude).claude/')

if [ "${#noncfg[@]}" -gt 0 ]; then
  echo "STOP: current-ahead non-config changes need classification (enrichment vs generic-L1 vs ignore):" >&2
  printf '  %s\n' "${noncfg[@]}" >&2
  echo "Decide per file: enrichment -> own L2 commit; generic -> dawn-harvest; churn -> ignore." >&2
  _dawn_bf_abort $DAWN_STOP_JUDGMENT
fi

# --- Step 2: current-vs-staging collisions without decisions -> stop and list (unchanged) ---
scan="$(dawn::reconcile_scan)" || _dawn_bf_abort $DAWN_GUARD
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
    _dawn_bf_abort $DAWN_STOP_JUDGMENT
  fi
fi

# --- Step 3: apply current-vs-staging reconcile folds (unchanged) ---
while IFS= read -r f; do
  [ -z "$f" ] && continue
  merged="$(dawn::reconcile_apply "$f" "$DECISIONS")" || _dawn_bf_abort $?
  [ -z "$merged" ] && continue
  if [ ! -f "$f" ] || [ "$(cat "$f")" != "$merged" ]; then
    mkdir -p "$(dirname "$f")"; printf '%s\n' "$merged" > "$f"
    report_current+=("$f")
  fi
done < <(dawn::config_targets)

# --- Step 4: collapse the contiguous config-only commit run at the tip into ONE snapshot (unchanged) ---
cust_base="$(git merge-base staging customizations 2>/dev/null)" \
  || { echo "GUARD: no merge-base with customizations; cannot collapse snapshot" >&2; _dawn_bf_abort $DAWN_GUARD; }
[ -z "$cust_base" ] && { echo "GUARD: no merge-base with customizations" >&2; _dawn_bf_abort $DAWN_GUARD; }
floor="$cust_base"
for c in $(git rev-list staging "^$cust_base"); do
  dawn::_commit_is_config_only "$c" || { floor="$c"; break; }
done

git add -A
git reset -q --soft "$floor"
if git diff --cached --quiet; then
  git commit -q --allow-empty -m "L2: store config snapshot (reconciled)"
else
  git commit -q -m "L2: store config snapshot (reconciled)"
fi

# --- Report / approval gate ---
if [ "${#report_staging_remote[@]}" = "0" ] && [ "${#report_current[@]}" = "0" ]; then
  if git diff --quiet "$floor" HEAD -- .; then
    echo "Nothing to reconcile; staging config collapsed to one empty snapshot at the tip."
  else
    echo "Backflow complete: staging config collapsed into one snapshot at the tip."
  fi
  # This fast path ALWAYS collapses and commits, regardless of --apply — force the marker write
  # to match (see _dawn_bf_sync_markers's comment for why "nothing to report" still needs it).
  _dawn_bf_sync_markers force
  exit $DAWN_OK
fi

if [ "$APPLY" != "1" ]; then
  echo "Backflow plan:"
  echo
  if [ "${#report_staging_remote[@]}" -gt 0 ]; then
    echo "Pulling in from the live preview theme ($staging_remote) — your local copy didn't have these:"
    printf '  - %s\n' "${report_staging_remote[@]}"
    echo
  fi
  if [ "${#report_current[@]}" -gt 0 ]; then
    echo "Folding in from the live published theme ($cur):"
    printf '  - %s\n' "${report_current[@]}"
    echo
  fi
  rerun="bash .claude/skills/dawn-backflow/backflow.sh --apply"
  [ "$DECISIONS" != "/dev/null" ] && rerun="$rerun --decisions $DECISIONS"
  echo "Proceed? re-run with: $rerun"
  _dawn_bf_abort $DAWN_STOP_APPROVAL
fi

echo "Backflow complete: staging config collapsed into one snapshot at the tip."
_dawn_bf_sync_markers
exit $DAWN_OK
