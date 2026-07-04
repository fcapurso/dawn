#!/usr/bin/env bash
# Dawn theme-ops shared library. Source from a checkout of the dawn repo.
# Exit-code contract: 0 ok · 10 guard · 20 stop-live · 21 stop-judgment · 22 stop-approval · 30 verify
set -uo pipefail
DAWN_OK=0 DAWN_GUARD=10 DAWN_STOP_LIVE=20 DAWN_STOP_JUDGMENT=21 DAWN_STOP_APPROVAL=22 DAWN_VERIFY=30
# Directory of this lib (for sibling files like config-paths.txt), resolved even when sourced.
# Portable across bash (BASH_SOURCE) and zsh (%x prompt-expansion) — this file gets `source`d
# directly from an operator's ambient shell, which on this machine defaults to zsh, not bash.
if [ -n "${BASH_SOURCE:-}" ]; then
  _dawn_self="${BASH_SOURCE[0]}"
else
  _dawn_self="${(%):-%x}"
fi
DAWN_LIB_DIR="$(cd "$(dirname "$_dawn_self")" && pwd)"
unset _dawn_self

# Cache config-paths.txt content at source time. The skills check out `staging` mid-run, and
# `staging` does not track the ops-only `.claude/` tree — so `git checkout staging` REMOVES this
# file from disk. Re-reading it after the switch fails and silently yields an empty path list
# (→ "nothing to reconcile"). Reading it once now, while `.claude/` is present, makes the list
# survive the branch switch. All readers use $DAWN_CONFIG_PATHS, never the file directly.
DAWN_CONFIG_PATHS="$(cat "$DAWN_LIB_DIR/config-paths.txt" 2>/dev/null || true)"

# Sentinel for "leaf absent at this ref" — a byte JSON can never contain.
DAWN_ABSENT=$'\x01ABSENT'

# Resolve the ref that represents the live theme. Test seam: DAWN_CURRENT_REF.
dawn::current_ref(){
  if [ -n "${DAWN_CURRENT_REF:-}" ]; then echo "$DAWN_CURRENT_REF"; return 0; fi
  if git rev-parse --verify -q refs/remotes/origin/current >/dev/null; then
    echo refs/remotes/origin/current
  else
    echo origin/current
  fi
}

# Resolve the ref that represents the staging preview theme's bot-linked remote copy.
# Test seam: DAWN_STAGING_REMOTE_REF.
dawn::staging_remote_ref(){
  if [ -n "${DAWN_STAGING_REMOTE_REF:-}" ]; then echo "$DAWN_STAGING_REMOTE_REF"; return 0; fi
  if git rev-parse --verify -q refs/remotes/origin/staging >/dev/null; then
    echo refs/remotes/origin/staging
  else
    echo origin/staging
  fi
}

dawn::current_branch(){ git rev-parse --abbrev-ref HEAD; }

dawn::assert_not_current(){
  if [ "$(dawn::current_branch)" = "current" ]; then
    echo "GUARD: refusing to operate on 'current' (the live shop)" >&2; return $DAWN_GUARD; fi; }

dawn::assert_clean_tree(){
  if [ -n "$(git status --porcelain)" ]; then
    echo "GUARD: working tree not clean — commit or stash first" >&2; return $DAWN_GUARD; fi; }

# Checkout target and restore the original branch when the *script* exits (success or failure).
dawn::with_branch(){
  local target="$1" orig; orig="$(dawn::current_branch)"
  git checkout -q "$target" 2>/dev/null || { echo "GUARD: cannot checkout $target" >&2; return $DAWN_GUARD; }
  trap "git checkout -q '$orig' 2>/dev/null || true" EXIT; }

dawn::merge_base_vanilla(){ git merge-base refs/remotes/upstream/main refs/remotes/origin/current 2>/dev/null \
  || git merge-base upstream/main origin/current; }

# Emit config-snapshot paths from config-paths.txt that actually exist as tracked files.
dawn::config_files(){
  local p; while IFS= read -r p; do [ -z "$p" ] && continue
    git ls-files -- "$p"; done <<< "$DAWN_CONFIG_PATHS" | sort -u; }

# Classify a repo path for reconcile:
#   "full"   -> listed in config-paths.txt (all leaves are config)
#   "suffix" -> custom suffix template templates/<type>.<suffix>.json (settings leaves only)
#   ""       -> not a reconcile target
dawn::config_class(){
  local p="$1"
  if grep -qxF "$p" <<< "$DAWN_CONFIG_PATHS"; then echo full; return 0; fi
  # suffix template: templates/<type>.<suffix>.json, but NOT a default templates/<type>.json
  if echo "$p" | grep -qE '^templates/[a-z_]+\.[a-z0-9_-]+\.json$'; then echo suffix; return 0; fi
  echo ""
}

# rc 0 if every file a commit touches is config (a reconcile target) or locale churn; rc 1 if it
# touches any non-config file (i.e. it is an enrichment / code commit that must NOT be squashed
# into the config snapshot). Used by backflow to find the collapse floor.
dawn::_commit_is_config_only(){
  local c="$1" f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in locales/*) continue ;; esac
    [ -n "$(dawn::config_class "$f")" ] || return 1
  done < <(git show --name-only --format= "$c")
  return 0
}

# Emit canonical leaf map for one config file at one ref.
# One line per leaf:  <path-json>\t<value-json>. Leaf = scalar or whole array.
# For class "suffix", restrict to leaves whose path passes through a `settings` key.
dawn::config_leaves(){
  local ref="$1" file="$2" class
  class="$(dawn::config_class "$file")"
  local raw; raw="$(git show "$ref:$file" 2>/dev/null | dawn::_strip_jsonc)" || return 0
  [ -z "$raw" ] && return 0
  local sel='.'
  [ "$class" = suffix ] && sel='select(.p | index("settings"))'
  printf '%s' "$raw" | jq -rc "
    def leaves(\$p):
      if type==\"object\" then (to_entries[] as \$e | (\$e.value | leaves(\$p + [\$e.key])))
      else {p:\$p, v:.} end;
    leaves([]) | $sel | (.p|tojson) + \"\t\" + (.v|tojson)
  " 2>/dev/null
}

# Files to reconcile: all existing config-paths.txt files, plus suffix templates
# that differ across any pair of {base, staging, <other>}.
# <other> defaults to dawn::current_ref (existing call sites keep today's behavior); pass
# dawn::staging_remote_ref explicitly to reconcile against the staging preview theme's bot instead.
dawn::config_targets(){
  local other="${1:-$(dawn::current_ref)}"
  local base; base="$(git merge-base staging "$other" 2>/dev/null)"
  {
    dawn::config_files
    if [ -n "$base" ]; then
      { git diff --name-only "$base" staging  -- 'templates/'
        git diff --name-only "$base" "$other" -- 'templates/'
        git diff --name-only staging "$other" -- 'templates/'; } \
      | grep -E '^templates/[a-z_]+\.[a-z0-9_-]+\.json$' \
      | grep -vxFf <(printf '%s\n' "$DAWN_CONFIG_PATHS") || true
    fi
  } | sort -u
}

# Map a reconcile "other" ref value to its logical sync-marker name ("current" or
# "staging-remote"), or empty if it matches neither resolver's current output. Used so
# dawn::reconcile_scan can look up the right persisted marker without every caller having to
# pass a second, easy-to-get-out-of-sync parameter.
dawn::_sync_marker_name(){
  local other="$1"
  [ "$other" = "$(dawn::current_ref)" ] && { echo current; return 0; }
  [ "$other" = "$(dawn::staging_remote_ref)" ] && { echo staging-remote; return 0; }
  echo ""
}

# Read the commit refs/dawn-sync/<name> points at, or empty if the marker doesn't exist yet.
dawn::sync_marker_get(){
  local name="$1"
  git rev-parse --verify -q "refs/dawn-sync/$name" 2>/dev/null || true
}

# Point refs/dawn-sync/<name> at <sha> and push it (a plain ref, not a branch — this is what
# keeps that specific commit's content reachable and nameable after the branch it came from has
# moved on). A ref, not a text file, because only a ref actually protects the commit from
# garbage collection. Test seam: DAWN_SYNC_MARKER_NOPUSH — test fixtures have no real "origin"
# to push to; dawn::sync_marker_get reads the local ref regardless, so skipping the push is safe
# for tests. A missing/empty <sha> is a no-op (never clobber a marker with garbage).
dawn::sync_marker_set(){
  local name="$1" sha="$2"
  [ -z "$sha" ] && return 0
  git update-ref "refs/dawn-sync/$name" "$sha"
  [ -n "${DAWN_SYNC_MARKER_NOPUSH:-}" ] && return 0
  git push -q origin "refs/dawn-sync/$name:refs/dawn-sync/$name" 2>/dev/null || true
}

# 3-way classify every leaf of every reconcile target against <other> (default dawn::current_ref).
# "base" is read from the persisted sync marker for <other> (see dawn::sync_marker_get) when one
# exists, falling back to git merge-base only on the very first run before a marker is
# established. The marker exists specifically because git ancestry is NOT a reliable "last
# agreed" reference here: dawn-backflow collapses staging's own history on every run, which
# makes a merge-base search regress further into the past each time, potentially past several
# already-reconciled changes (see docs/superpowers/specs/2026-07-03-dawn-backflow-sync-markers-design.md).
# Emits (only for non-agreeing leaves), tab-separated:
#   <verdict>\t<file>\t<path-json>\t<base>\t<staging>\t<other>
# verdict ∈ current_ahead | staging_ahead | collision.  Absent => $DAWN_ABSENT.
# The verdict names are historical (from when <other> was always current) and are kept as-is
# regardless of which ref is passed: current_ahead means "the other side is ahead", staging_ahead
# means "staging is ahead of that same other side".
# NOTE: awk (not bash assoc arrays) for grouping; awk (not sed) for tab tagging.
# Safe because leaf lines are canonical jq -c: values never contain a raw TAB.
dawn::reconcile_scan(){
  local other="${1:-$(dawn::current_ref)}"
  local base f marker
  marker="$(dawn::_sync_marker_name "$other")"
  base=""
  [ -n "$marker" ] && base="$(dawn::sync_marker_get "$marker")"
  if [ -z "$base" ]; then
    base="$(git merge-base staging "$other" 2>/dev/null)" \
      || { echo "GUARD: no merge-base for staging vs $other" >&2; return $DAWN_GUARD; }
  fi
  [ -z "$base" ] && { echo "GUARD: no merge-base for staging vs $other" >&2; return $DAWN_GUARD; }
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    {
      dawn::config_leaves "$base"   "$f" | awk '{print "B\t"$0}'
      dawn::config_leaves staging   "$f" | awk '{print "S\t"$0}'
      dawn::config_leaves "$other"  "$f" | awk '{print "C\t"$0}'
    } | awk -F'\t' -v file="$f" -v ABSENT="$DAWN_ABSENT" '
      { side=$1; path=$2; val=$3; seen[path]=1
        if(side=="B"){b[path]=val}
        else if(side=="S"){s[path]=val}
        else {c[path]=val} }
      END{
        for(p in seen){
          bv=(p in b)?b[p]:ABSENT; sv=(p in s)?s[p]:ABSENT; cv=(p in c)?c[p]:ABSENT
          if(sv==cv) continue
          if(sv==bv && cv!=bv) v="current_ahead"
          else if(cv==bv && sv!=bv) v="staging_ahead"
          else v="collision"
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", v, file, p, bv, sv, cv
        }
      }'
  done < <(dawn::config_targets "$other")
}

# 3-way value scan: compare staging vs <cur> vs <sr> for every config-class leaf.
# Unlike dawn::reconcile_scan, uses NO base reference — emits one row per key where
# the three values are not all identical, regardless of who changed what.
# Emits tab-separated: <verdict>\t<file>\t<path-json>\t<staging>\t<cur>\t<sr>
# Verdict: agree_cs (cur==sr, staging differs) | agree_sc (staging==cur, sr differs) |
#          agree_ss (staging==sr, cur differs) | all_differ (all three different).
# Absent keys use $DAWN_ABSENT. Files scanned = union of config_targets for both remotes.
dawn::backflow_scan(){
  local cur="${1:-$(dawn::current_ref)}"
  local sr="${2:-$(dawn::staging_remote_ref)}"
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    {
      dawn::config_leaves staging "$f" | awk '{print "S\t"$0}'
      dawn::config_leaves "$cur"     "$f" | awk '{print "C\t"$0}'
      dawn::config_leaves "$sr"      "$f" | awk '{print "R\t"$0}'
    } | awk -F'\t' -v file="$f" -v ABSENT="$DAWN_ABSENT" '
      { side=$1; path=$2; val=$3; seen[path]=1
        if(side=="S"){s[path]=val}
        else if(side=="C"){c[path]=val}
        else {r[path]=val} }
      END{
        for(p in seen){
          sv=(p in s)?s[p]:ABSENT
          cv=(p in c)?c[p]:ABSENT
          rv=(p in r)?r[p]:ABSENT
          if(sv==cv && sv==rv) continue
          if(cv==rv && sv!=cv)      v="agree_cs"
          else if(sv==cv && sv!=rv) v="agree_sc"
          else if(sv==rv && sv!=cv) v="agree_ss"
          else                      v="all_differ"
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", v, file, p, sv, cv, rv
        }
      }'
  done < <({ dawn::config_targets "$cur"; dawn::config_targets "$sr"; } | sort -u)
}

# rc 0 (pending) if any current-ahead leaf exists against <other> (default dawn::current_ref);
# else rc 1. Generalized exactly like dawn::reconcile_scan itself (optional `other` ref) so the
# existing call site (no arg) is unaffected — dawn::assert_backflow_not_pending is what actually
# passes dawn::staging_remote_ref.
# Collisions are NOT counted here: they are decided at backflow time (backflow stops with
# exit 21 until every collision has a decision), and a collision resolved to staging is a
# deliberate staging-wins outcome that promote is meant to carry. Statelessly a
# resolved-to-staging collision is indistinguishable from an unresolved one (base absent,
# staging != current), so counting collisions here would block promote forever after you
# chose staging. A genuinely un-folded live edit shows up as current_ahead and does block.
dawn::reconcile_pending(){
  local other="${1:-$(dawn::current_ref)}"
  local scan; scan="$(dawn::reconcile_scan "$other")" || return $DAWN_GUARD
  grep -qE '^current_ahead'$'\t' <<< "$scan"
}

# Deprecated name — kept so callers migrate incrementally. Prefer dawn::reconcile_pending.
dawn::backflow_pending(){ dawn::reconcile_pending; }

# Combined guard: is there ANY unfolded drift — config-class or non-config — against `current` OR
# `staging_remote` that dawn-backflow would need to fold first? Both dawn-promote and
# dawn-stage-push require staging to already reflect everything live before pushing further.
dawn::assert_backflow_not_pending(){
  dawn::reconcile_pending && { echo "GUARD: backflow first — origin/current has current-ahead edits not yet folded into staging" >&2; return $DAWN_GUARD; }
  dawn::reconcile_pending "$(dawn::staging_remote_ref)" && { echo "GUARD: backflow first — origin/staging has current-ahead edits not yet folded into staging" >&2; return $DAWN_GUARD; }
  local nc; nc="$(dawn::nonconfig_drift_scan)"; local rc=$?
  [ "$rc" = "1" ] && { echo "GUARD: origin/staging conflicts with local staging (non-config file) — resolve manually and re-run dawn-backflow first" >&2; return $DAWN_GUARD; }
  [ -n "$nc" ] && { echo "GUARD: backflow first — origin/staging has non-config drift (e.g. locale files) not yet folded into staging" >&2; return $DAWN_GUARD; }
  return 0
}

# Print the merged content for ONE file to stdout, or nothing if the file needs no change.
# Args: <file> <decisions-file> [<other-ref>, default dawn::current_ref]. Decisions lines: <file>\t<path-json>\t<staging|current|value:JSON>
# Returns $DAWN_STOP_JUDGMENT (and lists paths) if a collision has no decision.
#
# Substrate = STAGING (not current): staging is what we commit, and for suffix templates the
# skeleton is staging-authoritative — rebuilding from current would clobber staging's structure.
# We therefore apply ONLY the folds that move staging toward the reconciled result:
#   current_ahead                -> take current's value (fold the live edit into staging)
#   collision resolved to current -> take current's value
#   collision resolved to value   -> take the entered value
# staging_ahead and collisions resolved to staging need NO op (staging already holds them).
# If there are no folds, emit nothing so the caller leaves staging's file byte-for-byte intact
# (no spurious re-serialization churn).
dawn::reconcile_apply(){
  local file="$1" decisions="$2" other="${3:-$(dawn::current_ref)}"

  local raw header body
  raw="$(git show "staging:$file" 2>/dev/null)"
  [ -z "$raw" ] && return 0   # staging lacks the file; nothing to reconcile into it
  header="$(printf '%s' "$raw" | perl -0ne 'print $1 if m{\A(\s*/\*.*?\*/\s*)}s')"
  body="$(printf '%s' "$raw" | dawn::_strip_jsonc)"

  # Build the fold ops. A fold sets (or deletes) a path in staging to current's / the chosen value.
  local ops='[]' verdict f p b s c res
  local -a unresolved=()
  _dawn_fold(){ # $1 = value-json or $DAWN_ABSENT ; appends a set/del op for path $p
    if [ "$1" = "$DAWN_ABSENT" ]; then
      ops="$(jq -c --argjson p "$p" '. + [{p:$p,del:true}]' <<< "$ops")"
    else
      ops="$(jq -c --argjson p "$p" --argjson v "$1" '. + [{p:$p,v:$v}]' <<< "$ops")"
    fi
  }
  while IFS=$'\t' read -r verdict f p b s c; do
    [ "$f" = "$file" ] || continue
    case "$verdict" in
      staging_ahead) : ;;              # staging already holds the desired value
      current_ahead)
        res="$(awk -F'\t' -v f="$file" -v pp="$p" '$1==f && $2==pp {print $3}' "$decisions" 2>/dev/null | head -1)"
        [ "$res" = "staging" ] || _dawn_fold "$c" ;;
      collision)
        res="$(awk -F'\t' -v f="$file" -v pp="$p" '$1==f && $2==pp {print $3}' "$decisions" 2>/dev/null | head -1)"
        case "$res" in
          staging) : ;;                # staging already holds it
          current) _dawn_fold "$c" ;;
          value:*) _dawn_fold "${res#value:}" ;;
          *) unresolved+=("$p") ;;
        esac ;;
    esac
  done < <(dawn::reconcile_scan "$other")

  if [ "${#unresolved[@]}" -gt 0 ]; then
    echo "STOP: unresolved collisions in $file:" >&2
    printf '  %s\n' "${unresolved[@]}" >&2
    return $DAWN_STOP_JUDGMENT
  fi

  # No folds => file already correct on staging; emit nothing so the caller skips rewriting it.
  [ "$ops" = "[]" ] && return 0

  [ -n "$header" ] && printf '%s\n' "$header"
  printf '%s' "$body" | jq --argjson ops "$ops" '
    reduce $ops[] as $o (.; if ($o.del // false) then delpaths([$o.p]) else setpath($o.p; $o.v) end)'
}

# Read-only-in-effect preview of folding dawn::staging_remote_ref's remaining (non-leaf-reconciled)
# drift into staging — in practice, locale files (dawn::config_class has no leaf reconciler for
# them). Call this AFTER the config-class fold (dawn::reconcile_apply against
# dawn::staging_remote_ref) has been committed, so config-class files' JSON-value-level collisions
# are already resolved by the time this runs.
# Real 3-way text merge (git merge-tree), since no leaf-level reconciler covers these paths.
# Explicitly EXCLUDES config-class files (dawn::config_class non-empty) from both the reported
# "changed" list and the conflict verdict — not just an optimization. A config-class collision
# resolved via decisions (e.g. "take staging's own value") is, at the byte level, still a genuine
# textual conflict against staging_remote's raw serialization on that line (staging changed it one
# way, staging_remote changed it another). git merge-tree correctly reports that as CONFLICT, but
# it is already-resolved from this tool's point of view — the leaf reconciler is authoritative for
# these paths, so raw-text disagreement here must never surface as drift or block the run.
# `git merge-tree --write-tree` (git 2.50) doesn't support pathspec-scoping the merge itself, so we
# run it whole-tree and then post-filter: parse the stage 1/2/3 index lines it prints after the
# tree oid (format: "<mode> <object> <stage>\t<path>", one per unmerged path) to find which paths
# actually conflicted, and only fail if that set overlaps the non-config-class changed-file set.
# Stdout: one changed-file path per line, config-class files excluded. Exit 0 = clean (list may be
# empty). Exit 1 = conflict (same file list — see caller for the "resolve manually" message).
dawn::nonconfig_drift_scan(){
  local remote base changed out conflicted overlap
  remote="$(dawn::staging_remote_ref)"
  git rev-parse --verify -q "$remote" >/dev/null 2>&1 || return 0
  base="$(git merge-base staging "$remote" 2>/dev/null)" \
    || { echo "GUARD: no merge-base for staging vs $remote" >&2; return 1; }
  [ -z "$base" ] && { echo "GUARD: no merge-base for staging vs $remote" >&2; return 1; }

  changed="$(git diff --name-only "$base" "$remote" -- . | while IFS= read -r f; do
    [ -n "$f" ] && [ -z "$(dawn::config_class "$f")" ] && printf '%s\n' "$f"
  done)"
  [ -z "$changed" ] && return 0

  out="$(git merge-tree --write-tree --merge-base="$base" staging "$remote" 2>/dev/null)"
  conflicted="$(awk -F'\t' 'NF==2 && $1 ~ /^[0-7]+ [0-9a-f]+ [123]$/ {print $2}' <<< "$out" | sort -u)"
  overlap="$(comm -12 <(sort -u <<< "$changed") <(printf '%s\n' "$conflicted"))"

  printf '%s\n' "$changed"
  [ -n "$overlap" ] && return 1
  return 0
}

# Materialize dawn::nonconfig_drift_scan's clean fold into the working tree. Call only after a 0
# return from dawn::nonconfig_drift_scan. No commit is created — same working-tree-write pattern
# as dawn::reconcile_apply's callers. Skips config-class files (dawn::config_class non-empty) so
# it never touches a path the leaf reconciler already owns — mirrors the scan's exclusion.
dawn::nonconfig_drift_apply(){
  local remote base tree f
  remote="$(dawn::staging_remote_ref)"
  base="$(git merge-base staging "$remote" 2>/dev/null)" || return 1
  tree="$(git merge-tree --write-tree --merge-base="$base" staging "$remote" 2>/dev/null | head -1)"
  [ -z "$tree" ] && return 1
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -n "$(dawn::config_class "$f")" ] && continue
    if git cat-file -e "$tree:$f" 2>/dev/null; then
      mkdir -p "$(dirname "$f")"
      git show "$tree:$f" > "$f" 2>/dev/null || continue
    else
      rm -f -- "$f"
    fi
  done < <(git diff --name-only "$base" "$remote" -- .)
}

# rc 0 if trees equal (excl docs/ + .claude/), rc 30 with a summary if not.
dawn::verify_tree_equal(){
  local a="$1" b="$2"
  if git diff --quiet "$a" "$b" -- . ':(exclude)docs/' ':(exclude).claude/'; then return $DAWN_OK; fi
  echo "VERIFY FAIL: $a vs $b differ:" >&2
  git diff --stat "$a" "$b" -- . ':(exclude)docs/' ':(exclude).claude/' >&2; return $DAWN_VERIFY; }

# --- Inert/active classifier helpers ---

# Print the set of template JSON basenames that are always reachable (not suffix templates).
# Suffix templates (page.foo.json, product.foo.json) are NEEDS_JUDGMENT because
# whether a resource is bound to them is shop-global admin state, not in git.
dawn::_default_templates(){
  echo "index.json cart.json search.json 404.json gift_card.liquid password.json \
product.json collection.json article.json blog.json page.json list-collections.json"
}

# Print repo-relative paths of files reachable from the render graph (conservative).
# Outputs one path per line. Always includes layout/, header/footer groups, default templates,
# and any sections listed in reachable template/group JSON files.
dawn::reachable_files(){
  # Always-reachable roots
  git ls-files -- 'layout/' 'sections/header-group.json' 'sections/footer-group.json' \
    'config/settings_data.json' 'config/settings_schema.json'
  # Default templates
  local t; for t in $(dawn::_default_templates); do git ls-files -- "templates/$t"; done
  # Sections referenced in reachable template JSONs and section-group JSONs
  {
    for _t in $(dawn::_default_templates); do git ls-files -- "templates/$_t"; done
    git ls-files -- 'sections/header-group.json' 'sections/footer-group.json'
  } | while IFS= read -r jf; do
    [ -f "$jf" ] || continue
    # extract "type":"<section-handle>" values → sections/<handle>.liquid
    grep -o '"type": "[^"]*"' "$jf" 2>/dev/null | sed 's/"type": "//;s/"//' \
      | while IFS= read -r h; do git ls-files -- "sections/${h}.liquid"; done
  done
}

# Assert staging is "clean" for a guarded reset:
# staging must equal customizations with only config-snapshot enrichments on top —
# i.e. the last commit's subject must match "config snapshot" and
# no commits since customizations contain debug/WIP markers.
# Conservative: checks that staging is ahead of (or equal to) customizations (no divergence) and
# the tip commit subject contains "config" (the snapshot invariant).
dawn::assert_staging_clean(){
  # staging must be ahead of (or equal to) customizations, not diverged
  local behind; behind=$(git rev-list --count staging..customizations 2>/dev/null || echo 1)
  if [ "$behind" != "0" ]; then
    echo "GUARD: staging has diverged from customizations (customizations is $behind commits ahead of staging). Rebase staging onto customizations first." >&2
    return $DAWN_GUARD
  fi
  # tip commit must be a config snapshot
  local tip_msg; tip_msg=$(git log -1 --format=%s staging)
  case "$tip_msg" in
    *config*|*snapshot*|*settings*) ;;
    *) echo "GUARD: staging tip commit '$tip_msg' does not look like a config snapshot. Run dawn-backflow to recreate the snapshot at the tip." >&2
       return $DAWN_GUARD ;;
  esac
}

# Classify changes in a commit ref or range (base..tip).
# Stdout: one "<label> <path>" per changed file, then "VERDICT <ALL_INERT|HAS_ACTIVE|NEEDS_JUDGMENT>".
# Stderr: human-readable explanation for each classification decision.
dawn::classify_changes(){
  local range="${1:?usage: dawn::classify_changes <ref-or-range>}"
  # Normalize single ref to parent..ref
  case "$range" in *..*) ;; *) range="${range}^..${range}" ;; esac

  local reachable; reachable=$(dawn::reachable_files | sort -u)

  # Pre-compute added-only files in this range (status A = new file, not modified)
  local added_files; added_files=$(git diff --name-status "$range" | awk '$1=="A"{print $2}' | sort -u)

  local verdict="ALL_INERT" path label
  while IFS= read -r path; do
    [ -z "$path" ] && continue

    # Rule 1: new suffix template → NEEDS_JUDGMENT
    # Matches page.<something>.json or product.<something>.json but NOT page.json / product.json
    if echo "$path" | grep -qE '^templates/[a-z]+\..+\.json$'; then
      label="needs_judgment"
      echo "NEEDS_JUDGMENT: $path — new suffix template; confirm no resource is bound to it in admin" >&2
      verdict="NEEDS_JUDGMENT"

    # Rule 2: locale file — check for removed/changed lines (not purely additive)
    elif echo "$path" | grep -qE '^locales/'; then
      local removed; removed=$(git diff "$range" -- "$path" | grep -c '^-[^-]' || true)
      if [ "$removed" = "0" ]; then
        label="inert"
        echo "inert: $path — locale addition only (no changed/removed keys)" >&2
      else
        label="active"
        echo "active: $path — locale value changed or key removed" >&2
        [ "$verdict" = "ALL_INERT" ] && verdict="HAS_ACTIVE"
      fi

    # Rule 2b: newly-added file (status A) → inert regardless of reachability.
    # A brand-new section/asset/snippet can't be rendered until something references it,
    # so it's architecturally inert even if the classifier would otherwise flag it active.
    elif echo "$added_files" | grep -qxF "$path"; then
      label="inert"
      echo "inert: $path — newly-added file; unreachable until admin or template references it" >&2

    # Rule 3: in always-reachable set → active
    elif echo "$reachable" | grep -qxF "$path"; then
      label="active"
      echo "active: $path — in reachable render graph" >&2
      [ "$verdict" = "ALL_INERT" ] && verdict="HAS_ACTIVE"

    # Rule 4: not reachable → inert orphan
    else
      label="inert"
      echo "inert: $path — not reachable from any live render root" >&2
    fi

    echo "$label $path"
  done < <(git diff --name-only "$range")

  echo "VERDICT $verdict"
}

# --- Template JSON structure-vs-content classifier ---
#
# For a template JSON that differs between customizations and staging, decide whether
# the difference is STRUCTURE (→ L2) or only in-section settings values (→ Config).
#
# Rule: a template's structure is everything OUTSIDE the `settings` objects. Strip every
# `settings` object (section-level AND block-level, since `blocks` is a sibling of
# `settings`), then compare the remainder. Any difference in the remainder is structural:
# section add/remove/reorder, section `type`, `disabled`, `name`, or block add/remove/
# reorder/`type`. If the remainders match and only values inside `settings` differ, the
# change is content that belongs in the config snapshot, not in customizations.
#
# A structural change is always L2 (store-shaped), never L1.
# A template present on only one side (added/removed), or unparseable, is treated as L2.

# Strip a leading JSONC /* ... */ header comment (Shopify auto-generates one) so jq can parse.
dawn::_strip_jsonc(){ perl -0pe 's{^\s*/\*.*?\*/\s*}{}s'; }

# stdin: raw template JSON. stdout: normalized JSON with every `settings` object removed.
dawn::_template_skeleton(){
  dawn::_strip_jsonc | jq -S '
    def strip:
      if   type=="object" then (with_entries(select(.key != "settings")) | map_values(strip))
      elif type=="array"  then map(strip)
      else . end;
    strip' 2>/dev/null
}

# dawn::classify_template_json <template-path>
# Stdout: "config" or "l2".  Exit: 0 if config (skeletons match), 1 if l2 (structural).
dawn::classify_template_json(){
  local path="${1:?usage: dawn::classify_template_json <template-path>}"
  local cust stag
  cust=$(git show "customizations:$path" 2>/dev/null | dawn::_template_skeleton)
  stag=$(git show "staging:$path" 2>/dev/null | dawn::_template_skeleton)
  if [ -z "$cust" ] || [ -z "$stag" ]; then echo l2; return 1; fi   # one side missing/unparseable
  if [ "$cust" = "$stag" ]; then echo config; return 0; fi
  echo l2; return 1
}

# Emit candidate files to harvest from staging into customizations.
# Output: one line per file: "<verdict>  <L1|L2>  <path>"
# Scope: git diff --name-only customizations staging, excluding config-paths.txt, docs/, .claude/
dawn::harvest_candidates(){
  # Build exclusion list from config-paths.txt
  local excludes=()
  while IFS= read -r p; do [ -z "$p" ] && continue; excludes+=(":(exclude)$p"); done \
    <<< "$DAWN_CONFIG_PATHS"

  local files
  files=$(git diff --name-only customizations staging \
    -- . ':(exclude)docs/' ':(exclude).claude/' "${excludes[@]}" 2>/dev/null) || true

  # Post-filter: remove config-paths.txt entries in case pathspec exclusion didn't catch them
  if [ -n "$files" ]; then
    files=$(echo "$files" | grep -vxFf <(printf '%s\n' "$DAWN_CONFIG_PATHS") || true)
  fi

  [ -z "$files" ] && return 0

  # Call classify_changes once and cache — avoids O(N²) and ensures consistent verdicts
  local all_cls
  all_cls=$(dawn::classify_changes "customizations..staging" 2>/dev/null) || true

  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue

    # Per-file verdict from cached classify_changes output
    local cls_out verdict
    cls_out=$(grep "${f}$" <<< "$all_cls" | grep -v '^VERDICT' | head -1 || true)
    case "$cls_out" in
      needs_judgment*) verdict="needs_judgment" ;;
      active*)         verdict="active" ;;
      *)               verdict="inert" ;;
    esac

    # L2 keyword scan on the file content at staging
    local hint="L1"
    local content; content=$(git show "staging:$f" 2>/dev/null || true)
    if echo "$content" | grep -qiE 'zogezeept|\bcustom\.|\.myshopify\.com|GTM-'; then
      hint="L2"
    fi

    printf "%-18s %-4s %s\n" "$verdict" "$hint" "$f"
  done <<< "$files"
}
