#!/usr/bin/env bash
# Tiny dependency-free test harness. Source it; use assert_* ; call finish at end.
set -uo pipefail
_T_PASS=0 _T_FAIL=0
_pass(){ _T_PASS=$((_T_PASS+1)); echo "  ok  - $1"; }
_fail(){ _T_FAIL=$((_T_FAIL+1)); echo "  NOT ok - $1"; [ -n "${2:-}" ] && echo "        $2"; }
assert_eq(){ [ "$2" = "$3" ] && _pass "$1" || _fail "$1" "expected [$3] got [$2]"; }
assert_rc(){ # assert_rc "name" expected_rc cmd...
  local name="$1" exp="$2"; shift 2; "$@"; local rc=$?
  [ "$rc" = "$exp" ] && _pass "$name" || _fail "$name" "expected rc=$exp got rc=$rc"; }
assert_contains(){ case "$2" in *"$3"*) _pass "$1";; *) _fail "$1" "[$2] lacks [$3]";; esac; }
finish(){ echo "== $_T_PASS passed, $_T_FAIL failed =="; [ "$_T_FAIL" = 0 ]; }
