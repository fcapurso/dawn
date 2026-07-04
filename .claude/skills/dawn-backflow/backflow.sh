#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

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
sr="$(dawn::staging_remote_ref)"

git fetch origin current --quiet 2>/dev/null || true
git fetch origin staging --quiet 2>/dev/null || true
git fetch origin refs/dawn-sync/current:refs/dawn-sync/current --quiet 2>/dev/null || true
git fetch origin refs/dawn-sync/staging-remote:refs/dawn-sync/staging-remote --quiet 2>/dev/null || true

cur_sha="$(git rev-parse "$cur" 2>/dev/null || true)"
sr_sha="$(git rev-parse "$sr" 2>/dev/null || true)"

orig_sha="$(git rev-parse staging)"
dawn::with_branch staging || exit $DAWN_GUARD

_dawn_bf_abort(){ git reset -q --hard "$orig_sha" 2>/dev/null || true; exit "$1"; }

_dawn_bf_sync_markers(){
  [ "${1:-}" = "force" ] || [ "$APPLY" = "1" ] || return 0
  dawn::sync_marker_set current "$cur_sha"
  dawn::sync_marker_set staging-remote "$sr_sha"
}

# --- Step 0: detect non-config files on origin/current (need human classification) ---
# Only flag files that changed on $cur relative to staging (current-side changes), not files
# changed on staging relative to $cur — those are staging-local changes and handled elsewhere.
base_cur="$(git merge-base staging "$cur" 2>/dev/null || true)"
noncfg=()
if [ -n "$base_cur" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -n "$(dawn::config_class "$f")" ] && continue
    git diff --quiet "$base_cur" "$cur" -- "$f" && continue
    noncfg+=("$f")
  done < <(git diff --name-only staging "$cur" -- . ':(exclude)docs/' ':(exclude).claude/')
fi
if [ "${#noncfg[@]}" -gt 0 ]; then
  echo "STOP: origin/current has non-config changes that need classification:" >&2
  printf '  %s\n' "${noncfg[@]}" >&2
  echo "Decide per file: enrichment -> own L2 commit; generic -> dawn-harvest; churn -> ignore." >&2
  _dawn_bf_abort $DAWN_STOP_JUDGMENT
fi

# --- Step 1: scan config-class divergences across all three sources ---
scan="$(dawn::backflow_scan "$cur" "$sr")" || _dawn_bf_abort $DAWN_GUARD

# --- Step 2: non-config drift from origin/staging ---
nc_out="$(dawn::nonconfig_drift_scan)"; nc_rc=$?
if [ "$nc_rc" = "1" ]; then
  echo "GUARD: origin/staging conflicts with local staging in:" >&2
  sed 's/^/  /' <<< "$nc_out" >&2
  echo "Resolve manually and re-run." >&2
  _dawn_bf_abort $DAWN_GUARD
fi

# --- Nothing to do? ---
if [ -z "$scan" ] && [ -z "$nc_out" ]; then
  echo "Nothing to reconcile; staging is in sync with origin/current and origin/staging."
  _dawn_bf_sync_markers force
  exit $DAWN_OK
fi

# --- Plan mode ---
if [ "$APPLY" != "1" ]; then
  if [ -n "$scan" ]; then
    echo "Config settings that differ between staging, origin/current, and origin/staging:"
    echo
    while IFS=$'\t' read -r verdict f p sv cv rv; do
      printf '  %s  %s\n    staging=%s  origin/current=%s  origin/staging=%s\n' \
        "$f" "$p" "$sv" "$cv" "$rv"
    done <<< "$scan"
    echo
    printf 'Decisions TSV format: <file>\t<path-json>\t<staging|current|staging_remote|value:JSON>\n'
    echo
  fi
  if [ -n "$nc_out" ]; then
    echo "Non-config drift from origin/staging (folded automatically on apply):"
    sed 's/^/  /' <<< "$nc_out"
    echo
  fi
  rerun="bash .claude/skills/dawn-backflow/backflow.sh --apply"
  [ "$DECISIONS" != "/dev/null" ] && rerun="$rerun --decisions $DECISIONS"
  echo "Proceed? re-run with: $rerun"
  _dawn_bf_abort $DAWN_STOP_APPROVAL
fi

# --- Apply mode: verify all decisions are present ---
if [ -n "$scan" ]; then
  missing=""
  while IFS=$'\t' read -r verdict f p sv cv rv; do
    res="$(awk -F'\t' -v ff="$f" -v pp="$p" '$1==ff && $2==pp {print $3}' "$DECISIONS" 2>/dev/null | head -1)"
    [ -z "$res" ] && missing+="  $f $p"$'\n'
  done <<< "$scan"
  if [ -n "$missing" ]; then
    echo "GUARD: missing decisions — re-run in plan mode first, then provide decisions:" >&2
    printf '%s' "$missing" >&2
    _dawn_bf_abort $DAWN_GUARD
  fi
fi

# --- Apply config changes ---
config_changed=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  merged="$(dawn::backflow_apply "$f" "$DECISIONS" "$cur" "$sr")" || _dawn_bf_abort $?
  [ -z "$merged" ] && continue
  if [ ! -f "$f" ] || [ "$(cat "$f")" != "$merged" ]; then
    mkdir -p "$(dirname "$f")"; printf '%s\n' "$merged" > "$f"
    config_changed=1
  fi
done < <({ dawn::config_targets "$cur"; dawn::config_targets "$sr"; } | sort -u)

if [ "$config_changed" = "1" ]; then
  git add -A
  git commit -q -m "fold config (backflow)"
fi

# --- Apply non-config drift ---
if [ -n "$nc_out" ]; then
  dawn::nonconfig_drift_apply
  git add -A
  git commit -q -m "fold origin/staging (other)"
fi

# --- Collapse config snapshot ---
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

echo "Backflow complete: staging config collapsed into one snapshot at the tip."
_dawn_bf_sync_markers
exit $DAWN_OK
