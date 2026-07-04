# Dawn-ops: `dawn-stage-push` skill + shared origin/staging drift guard — Design

**Date:** 2026-07-04
**Repo:** Dawn / Zogezeept (operated from `ops`)
**Status:** Approved design, pending spec review → implementation plan
**Revises:** `_dawn-ops-lib/dawn-ops.sh` (`dawn::reconcile_pending`), `dawn-promote/promote.sh`.
**Adds:** `dawn-stage-push` (new skill). Builds on the sync-markers design
(`docs/superpowers/specs/2026-07-03-dawn-backflow-sync-markers-design.md`).

> Context: the operator wants a three-stage release flow — **backflow → stage-push → promote** —
> so a reconciled `staging` can be pushed to the preview theme and tested live before it ever
> touches the published storefront. Designing that surfaced a real, currently-shipped gap:
> `dawn-promote`'s guard (`dawn::reconcile_pending`) only ever checks `origin/current` for unfolded
> drift. It has no idea `origin/staging` exists. A live edit made in the preview theme's admin
> editor, never backflowed, would silently survive an untouched `dawn-promote` run to be
> **destroyed** by its force-push — never reaching `staging`, never reaching the published theme.

---

## 1. The three-stage flow

```
backflow  →  stage-push  →  promote
(reconcile)   (push to        (push to
              preview,        preview AND
              test it)        live)
```

Each stage's guard asks the same question — "has anything changed on either remote since I last
looked, that I haven't folded in yet?" — before letting you move forward. A live edit landing on
`origin/staging` or `origin/current` at any point knocks you back to needing `dawn-backflow` again.

---

## 2. One generalized guard, two callers

### 2.1 Generalize `dawn::reconcile_pending`

Today (`dawn-ops.sh:222-225`):
```bash
dawn::reconcile_pending(){
  local scan; scan="$(dawn::reconcile_scan)" || return $DAWN_GUARD
  grep -qE '^current_ahead'$'\t' <<< "$scan"
}
```
Hardcoded to `dawn::reconcile_scan`'s default (`current`). Generalize exactly like `reconcile_scan`
itself already was: accept an optional `other` ref, defaulting to `dawn::current_ref` so the
existing call site (none currently pass an arg) is unaffected. The "collisions don't count, only
current_ahead does" reasoning in the existing docstring applies identically regardless of which
remote is being checked — a collision resolved to staging is a deliberate "staging wins" outcome
either way, not something to block on.

### 2.2 A shared "is backflow needed?" check

New function, used by both callers below:

```bash
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
```

(`dawn::nonconfig_drift_scan` already exists from the sync-markers work; reused as-is, not
modified.)

### 2.3 `dawn-promote` — fix the gap

Replace `promote.sh:8`'s single-check guard:
```bash
dawn::reconcile_pending && { echo "GUARD: backflow first — origin/current has current-ahead edits not yet folded into staging" >&2; exit $DAWN_GUARD; }
```
with:
```bash
dawn::assert_backflow_not_pending || exit $DAWN_GUARD
```
This is the actual bug fix: promote now refuses if *either* remote has drift, not just `current`.

---

## 3. `dawn-stage-push` — new skill

Pushes local `staging` to `origin/staging` only. Nothing touches `current`; no live-confirm gate
(nothing customer-facing changes) — but it's still a force-push, so the same `assert_staging_clean`
and drift guard apply as promote's first two checks.

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"
PUSH="${DAWN_PUSH:-git push --force-with-lease}"
REMOTE="${DAWN_REMOTE:-origin}"

dawn::assert_backflow_not_pending || exit $DAWN_GUARD
dawn::assert_staging_clean || exit $DAWN_GUARD

if [ -n "${DAWN_STAGE_PUSH_REF:-}" ]; then      # test path: move local ref
  git update-ref "$DAWN_STAGE_PUSH_REF" staging
else                                             # real path: force-push staging onto origin/staging
  $PUSH "$REMOTE" staging || { echo "GUARD: push to $REMOTE staging failed; marker not updated" >&2; exit $DAWN_GUARD; }
fi
sha="$(git rev-parse staging)"
dawn::sync_marker_set staging-remote "$sha"
echo "Pushed staging -> origin/staging (preview theme). Test it there; run dawn-promote when ready to go live."
exit $DAWN_OK
```

Mirrors `promote.sh`'s existing structure and test-seam pattern exactly (`DAWN_STAGE_PUSH_REF` is
the same idea as `DAWN_PROMOTE_REF`, just a second, distinctly-named seam since there's only one
push target here instead of two).

`current`'s marker is untouched — nothing about `current` changed.

---

## 4. Testing (one shared fixture, per the frugality request — no per-skill duplication)

One new test file exercises the full chain with a single fixture, reusing assertions instead of
writing separate drift-guard tests per skill:

1. Drift on `origin/staging` (config-class) blocks **both** `dawn-stage-push` and `dawn-promote`
   with the same `GUARD` message shape.
2. `dawn-backflow` (`--apply`) clears it.
3. `dawn-stage-push` now succeeds; `origin/staging` (test double) and the `staging-remote` marker
   both land on `staging`'s tip.
4. A **fresh** drift lands on `origin/current` — blocks `dawn-promote` (proving the guard is
   symmetric, not just "checked once and forgotten").
5. `dawn-backflow` clears it again.
6. `dawn-promote --confirm-live` succeeds.

Existing `test_promote_guard.sh`'s current test (checks the `current`-side guard) stays as-is —
this new file only adds the `origin/staging`-side case and the cross-skill reuse, rather than
re-testing what's already covered.

---

## 5. Surface of change

| File | Change |
|---|---|
| `_dawn-ops-lib/dawn-ops.sh` | Generalize `dawn::reconcile_pending` (optional `other` param); add `dawn::assert_backflow_not_pending` |
| `dawn-promote/promote.sh` | Replace single-remote guard with `dawn::assert_backflow_not_pending` |
| `dawn-stage-push/stage-push.sh` (new) | New skill per §3 |
| `dawn-stage-push/SKILL.md` (new) | Brief: what it does, when to use it, exit codes (reuses `DAWN_GUARD`/`DAWN_OK` only — no judgment/collision states of its own, since `dawn-backflow` already owns those) |
| `_dawn-ops-lib/tests/test_promote_guard.sh` | No change (existing case untouched) |
| `_dawn-ops-lib/tests/test_stage_push_flow.sh` (new) | The one shared-fixture chain test from §4 |
| `_dawn-ops-lib/conventions.md` | Add `dawn-stage-push` to the branch-role table; note the guard now covers both remotes |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | Add `dawn-stage-push` row; update the standard workflow to show backflow → stage-push → promote |

## 6. Out of scope

- Any UI/automation for "test it on the preview theme" itself — that's manual, in the Shopify
  admin, outside this repo's tooling.
- Concurrent-push coordination — same as everywhere else in this branch model, not solved here.
