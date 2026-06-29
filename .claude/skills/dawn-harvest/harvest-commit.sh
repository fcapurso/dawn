#!/usr/bin/env bash
# harvest-commit.sh --message <msg> --files <f1> [f2 ...] [--l1-content <file>:<tmp> ...]
# Atomically commits files from staging into customizations, then rebases staging.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

usage(){ echo "usage: harvest-commit.sh --message <msg> --files <f1> [f2 ...] [--l1-content <file>:<tmppath> ...]" >&2; exit $DAWN_GUARD; }

msg="" files=() l1_overrides=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message)    shift; msg="$1"; shift ;;
    --files)      shift; while [[ $# -gt 0 && "$1" != --* ]]; do files+=("$1"); shift; done ;;
    --l1-content) shift; l1_overrides+=("$1"); shift ;;
    *) usage ;;
  esac
done

[[ -z "$msg" ]]           && { echo "GUARD: --message is required" >&2; exit $DAWN_GUARD; }
[[ ${#files[@]} -eq 0 ]]  && { echo "GUARD: --files requires at least one path" >&2; exit $DAWN_GUARD; }

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD

# Guard: reject config files
while IFS= read -r c; do
  for f in "${files[@]}"; do
    if [[ "$f" = "$c" ]]; then
      echo "GUARD: $f is a config file — config files are not harvestable" >&2
      exit $DAWN_GUARD
    fi
  done
done < <(dawn::config_files)

dawn::with_branch customizations || exit $DAWN_GUARD

# For each file, check if there's an l1-content override (file:tmppath)
for f in "${files[@]}"; do
  tmp=""
  for entry in "${l1_overrides[@]+"${l1_overrides[@]}"}"; do
    key="${entry%%:*}"
    if [[ "$key" = "$f" ]]; then
      tmp="${entry#*:}"
      break
    fi
  done
  if [[ -n "$tmp" ]]; then
    mkdir -p "$(dirname "$f")"
    cp "$tmp" "$f"
    git add "$f"
  else
    git checkout staging -- "$f"
  fi
done

git add "${files[@]}"
git commit -q -m "$msg"

git checkout -q staging
git rebase -q customizations || {
  echo "STOP: rebase conflict bringing harvest commit into staging." >&2
  echo "Resolve conflicts, then: git rebase --continue (or git rebase --abort to undo)." >&2
  exit $DAWN_STOP_JUDGMENT
}
echo "Committed to customizations and rebased staging."
exit $DAWN_OK
