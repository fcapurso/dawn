#!/usr/bin/env bash
# Dawn theme-ops shared library. Source from a checkout of the dawn repo.
# Exit-code contract: 0 ok · 10 guard · 20 stop-live · 21 stop-judgment · 30 verify
set -uo pipefail
DAWN_OK=0 DAWN_GUARD=10 DAWN_STOP_LIVE=20 DAWN_STOP_JUDGMENT=21 DAWN_VERIFY=30
# Directory of this lib (for sibling files like config-paths.txt), resolved even when sourced.
DAWN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
# that differ across any pair of {base, staging, current}.
dawn::config_targets(){
  local cur base; cur="$(dawn::current_ref)"; base="$(git merge-base staging "$cur" 2>/dev/null)"
  {
    dawn::config_files
    if [ -n "$base" ]; then
      { git diff --name-only "$base" staging      -- 'templates/'
        git diff --name-only "$base" "$cur"       -- 'templates/'
        git diff --name-only staging "$cur"       -- 'templates/'; } \
      | grep -E '^templates/[a-z_]+\.[a-z0-9_-]+\.json$' \
      | grep -vxFf <(printf '%s\n' "$DAWN_CONFIG_PATHS") || true
    fi
  } | sort -u
}

# 3-way classify every leaf of every reconcile target.
# Emits (only for non-agreeing leaves), tab-separated:
#   <verdict>\t<file>\t<path-json>\t<base>\t<staging>\t<current>
# verdict ∈ current_ahead | staging_ahead | collision.  Absent => $DAWN_ABSENT.
# NOTE: awk (not bash assoc arrays) for grouping; awk (not sed) for tab tagging.
# Safe because leaf lines are canonical jq -c: values never contain a raw TAB.
dawn::reconcile_scan(){
  local cur base f
  cur="$(dawn::current_ref)"
  base="$(git merge-base staging "$cur" 2>/dev/null)" \
    || { echo "GUARD: no merge-base for staging vs $cur" >&2; return $DAWN_GUARD; }
  [ -z "$base" ] && { echo "GUARD: no merge-base for staging vs $cur" >&2; return $DAWN_GUARD; }
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    {
      dawn::config_leaves "$base"   "$f" | awk '{print "B\t"$0}'
      dawn::config_leaves staging   "$f" | awk '{print "S\t"$0}'
      dawn::config_leaves "$cur"    "$f" | awk '{print "C\t"$0}'
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
  done < <(dawn::config_targets)
}

# rc 0 (pending) if any current-ahead leaf exists; else rc 1.
# Collisions are NOT counted here: they are decided at backflow time (backflow stops with
# exit 21 until every collision has a decision), and a collision resolved to staging is a
# deliberate staging-wins outcome that promote is meant to carry. Statelessly a
# resolved-to-staging collision is indistinguishable from an unresolved one (base absent,
# staging != current), so counting collisions here would block promote forever after you
# chose staging. A genuinely un-folded live edit shows up as current_ahead and does block.
dawn::reconcile_pending(){
  local scan; scan="$(dawn::reconcile_scan)" || return $DAWN_GUARD
  grep -qE '^current_ahead'$'\t' <<< "$scan"
}

# Deprecated name — kept so callers migrate incrementally. Prefer dawn::reconcile_pending.
dawn::backflow_pending(){ dawn::reconcile_pending; }

# Print the merged content for ONE file to stdout, or nothing if the file needs no change.
# Args: <file> <decisions-file>. Decisions lines: <file>\t<path-json>\t<staging|current|value:JSON>
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
  local file="$1" decisions="$2"

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
      current_ahead) _dawn_fold "$c" ;;
      collision)
        res="$(awk -F'\t' -v f="$file" -v pp="$p" '$1==f && $2==pp {print $3}' "$decisions" 2>/dev/null | head -1)"
        case "$res" in
          staging) : ;;                # staging already holds it
          current) _dawn_fold "$c" ;;
          value:*) _dawn_fold "${res#value:}" ;;
          *) unresolved+=("$p") ;;
        esac ;;
    esac
  done < <(dawn::reconcile_scan)

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
