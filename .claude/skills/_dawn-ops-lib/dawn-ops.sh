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
