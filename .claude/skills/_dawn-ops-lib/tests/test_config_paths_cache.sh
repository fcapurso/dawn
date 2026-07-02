#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Reproduce the production bug: config-paths.txt disappears from disk AFTER the lib is sourced
# (as happens when backflow checks out `staging`, which lacks the ops-only .claude/ tree).
# The load-time cache must keep config_class / config_files working across the vanish.
libdir="$(dirname "$DAWN_LIB_SRC")"
tmp="$(mktemp -d)"
cp "$libdir/dawn-ops.sh" "$tmp/dawn-ops.sh"
cp "$libdir/config-paths.txt" "$tmp/config-paths.txt"

out="$(bash -c "
  source '$tmp/dawn-ops.sh'         # caches config-paths at source time
  rm -f '$tmp/config-paths.txt'     # file vanishes, mimicking the staging checkout
  dawn::config_class config/settings_data.json
")"
assert_eq "$out" "full" "config_class works after config-paths.txt removed (cache survives)"

echo "  config_paths_cache ok"
