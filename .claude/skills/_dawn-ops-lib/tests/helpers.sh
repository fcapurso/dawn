#!/usr/bin/env bash
# Test harness for dawn-ops. Plain bash, no bats dependency.
set -uo pipefail
DAWN_LIB_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dawn-ops.sh"

_dawn_fail(){ echo "  FAIL: $*" >&2; exit 1; }
assert_eq(){ [ "$1" = "$2" ] || _dawn_fail "expected [$2], got [$1] ${3:+($3)}"; }
assert_contains(){ grep -qF "$2" <<< "$1" || _dawn_fail "[$1] does not contain [$2] ${3:+($3)}"; }
assert_not_contains(){ grep -qF "$2" <<< "$1" && _dawn_fail "[$1] unexpectedly contains [$2] ${3:+($3)}" || true; }
assert_rc(){ [ "$1" = "$2" ] || _dawn_fail "expected rc $2, got $1 ${3:+($3)}"; }

# Create a throwaway git repo with base/staging/current branches. Prints its path.
dawn_test_repo(){
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" commit -q --allow-empty -m base
  git -C "$d" branch staging
  git -C "$d" branch current
  git -C "$d" branch customizations    # collapse floor for backflow (staging's stable base)
  echo "$d"
}

# commit_on <repo> <branch> <path> [msg]   (reads file content from stdin)
commit_on(){
  local d="$1" br="$2" path="$3" msg="${4:-edit}"
  git -C "$d" checkout -q "$br"
  mkdir -p "$d/$(dirname "$path")"
  cat > "$d/$path"
  git -C "$d" add -A
  git -C "$d" commit -q -m "$msg"
}

# Run a function inside the repo with the test seam pointing at the local 'current' branch.
in_repo(){
  local d="$1"; shift
  ( cd "$d" && DAWN_CURRENT_REF=current bash -c "source '$DAWN_LIB_SRC'; $*" )
}
