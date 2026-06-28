#!/usr/bin/env bash
# Dawn theme-ops shared library. Source from a checkout of the dawn repo.
# Exit-code contract: 0 ok · 10 guard · 20 stop-live · 21 stop-judgment · 30 verify
set -uo pipefail
DAWN_OK=0 DAWN_GUARD=10 DAWN_STOP_LIVE=20 DAWN_STOP_JUDGMENT=21 DAWN_VERIFY=30
# Directory of this lib (for sibling files like config-paths.txt), resolved even when sourced.
DAWN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    git ls-files -- "$p"; done < "$DAWN_LIB_DIR/config-paths.txt" | sort -u; }

# rc 0 if origin/current has config changes not in staging (backflow needed), else rc 1.
dawn::backflow_pending(){
  local ref; ref="refs/remotes/origin/current"
  git rev-parse --verify "$ref" &>/dev/null || ref="origin/current"
  ! git diff --quiet staging "$ref" -- $(cat "$DAWN_LIB_DIR/config-paths.txt" | grep -v '^$' | tr '\n' ' '); }

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
