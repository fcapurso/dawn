# Design: Full three-source backflow reconcile + promote stage-push guard

**Date:** 2026-07-04
**Status:** Approved

---

## Problem

### 1. Backflow auto-folds without consent

The current backflow uses a base SHA (sync marker or `git merge-base`) to classify each config
key as `staging_ahead`, `current_ahead`, or `collision`. Only collisions stop for a decision;
`current_ahead` keys fold automatically.

This means: if the preview theme (origin/staging) reverts a value that staging inherited from an
old snapshot (but never actively set), backflow silently overwrites staging with the live version.
The operator has no opportunity to reject it.

### 2. Promote can run without a stage-push

Nothing currently prevents promoting staging directly to the live shop without having first pushed
staging to the preview theme and verified it there. The stage-push step is advisory, not enforced.

---

## Goals

1. Every config key where staging, origin/current, and origin/staging do not all agree surfaces as
   an explicit operator decision — no silent auto-folds.
2. Promote is blocked unless the exact staging commit was tested on the preview theme (origin/staging)
   and neither staging nor origin/staging has changed since that push.

---

## Design: New backflow reconcile

### Core change

Replace the direction-aware 3-way reconcile (base + staging + other) with a **value-only 3-way
comparison** (staging + origin/current + origin/staging). For any config leaf key where the three
values are not all identical, the operator chooses which value staging should hold.

No base SHA. No direction inference. No auto-folds.

### New shell function: `dawn::backflow_scan`

```
dawn::backflow_scan [<current-ref> [<staging-remote-ref>]]
```

Defaults: `dawn::current_ref` and `dawn::staging_remote_ref`.

For each config-class file (from `dawn::config_targets`), reads all leaf keys from all three refs
and emits one TSV row per key where the three values are not all identical:

```
<verdict>\t<file>\t<path-json>\t<staging-val>\t<current-val>\t<staging-remote-val>
```

Verdict values (for display / SKILL.md guidance only — not used by apply logic):

| Verdict | Meaning |
|---|---|
| `agree_cs` | origin/current == origin/staging, staging differs |
| `agree_sc` | staging == origin/current, origin/staging differs |
| `agree_ss` | staging == origin/staging, origin/current differs |
| `all_differ` | all three values different |

`DAWN_ABSENT` sentinel is used for missing keys (key present on some sides but not others).

### New shell function: `dawn::backflow_apply`

```
dawn::backflow_apply <file> <decisions-file> [<current-ref> [<staging-remote-ref>]]
```

Reads the decisions TSV for `<file>` and applies the chosen values to staging's working copy.
Decision verdicts:

| Verdict in TSV | Action |
|---|---|
| `staging` | no-op (staging already holds the value) |
| `current` | take origin/current's value |
| `staging_remote` | take origin/staging's value |
| `value:<json>` | set the custom JSON value |

Returns empty output (no write) if the file already reflects all decisions. Errors if a key in the
scan output has no decision in the decisions file.

### backflow.sh rewrite

New flow, keeping the same `--apply` / `--decisions` / plan-mode gate interface:

```
1. fetch origin/current, origin/staging, sync markers
2. dawn::backflow_scan  → structured report of divergent keys
3. If no divergences and no non-config drift → exit 0 ("nothing to fold")
4. [plan mode] Output report. Exit 22 (SKILL.md agent asks per-key AskUserQuestion,
   builds decisions file, re-runs with --apply --decisions)
5. [apply mode] dawn::backflow_apply per file
6. dawn::nonconfig_drift_scan / dawn::nonconfig_drift_apply (locale files — unchanged)
7. Collapse config snapshot (unchanged)
8. Update sync markers (unchanged)
9. Exit 0
```

Non-config file handling (Step 6) is unchanged.

### Decisions TSV extension

The decisions file gains one new valid verdict: `staging_remote` (take origin/staging's value).
The existing `staging`, `current`, and `value:<json>` verdicts are retained.

### SKILL.md agent behaviour (Exit 22)

When the plan output contains divergent key rows, the agent presents them via `AskUserQuestion`
with `multiSelect: false` (single-select per key). Options for each key:

- Keep staging `<val>`
- Take origin/current `<val>`
- Take origin/staging `<val>` *(shown only if different from the other two options)*
- Enter a custom value

Two options are collapsed into one if their values are identical (e.g. if origin/current and
staging agree, show "Keep staging / origin/current `<val>`" as a single option vs. "Take
origin/staging `<val>`").

After all per-key decisions, the agent builds `/tmp/backflow-decisions.tsv` and runs
`--apply --decisions`.

### What does NOT change

- `dawn::reconcile_scan` and `dawn::reconcile_apply` are **kept** — the guard functions
  (`dawn::reconcile_pending`, `dawn::assert_backflow_not_pending`) depend on them and their
  base/marker logic remains correct for detecting new live commits.
- `dawn::nonconfig_drift_scan` / `dawn::nonconfig_drift_apply` — unchanged.
- Sync marker read/write — unchanged.
- Existing test files for `reconcile_scan`, `reconcile_apply`, `reconcile_pending` — unchanged.
- `test_backflow_drift.sh` and `test_backflow.sh` — will be rewritten to match the new behaviour.

### Repeated-question behaviour

Because there is no direction anchor, a key where staging intentionally differs from both live
sources (operator chose to reject a live edit) will appear again on the next backflow if the live
sources haven't changed. This is acceptable: in the normal workflow
(backflow → stage-push → promote), after promote all three sources agree and the question
disappears. It only recurs if the operator backlflows multiple times without promoting.

---

## Design: Promote stage-push guard

### Invariant

Before promoting, staging must equal origin/staging, and that equality must have been established
by a stage-push (not by coincidence). The sync marker `refs/dawn-sync/staging-remote` records
staging's exact SHA at the last stage-push.

### New shell function: `dawn::assert_stage_push_current`

```bash
dawn::assert_stage_push_current(){
  local marker; marker="$(dawn::sync_marker_get staging-remote 2>/dev/null)"
  if [ -z "$marker" ]; then
    echo "GUARD: stage-push first — staging has never been pushed to the preview theme" >&2
    return $DAWN_GUARD
  fi
  local staging_sha; staging_sha="$(git rev-parse staging 2>/dev/null)"
  if [ "$staging_sha" != "$marker" ]; then
    echo "GUARD: stage-push first — staging has changed since the last preview push" >&2
    return $DAWN_GUARD
  fi
  git fetch origin staging --quiet 2>/dev/null || true
  local remote_sha; remote_sha="$(git rev-parse "${DAWN_STAGING_REMOTE_REF:-origin/staging}" 2>/dev/null || true)"
  if [ "$remote_sha" != "$marker" ]; then
    echo "GUARD: stage-push first — the preview theme has changed since the last push (run backflow then stage-push again)" >&2
    return $DAWN_GUARD
  fi
  return 0
}
```

### Integration in promote.sh

Call `dawn::assert_stage_push_current` **before** the existing
`dawn::assert_backflow_not_pending`. Rationale: the stage-push guard is cheaper (local ref
comparison) and catches the most common error (forgetting to stage-push) without needing to do
the full backflow scan.

```bash
dawn::assert_stage_push_current || exit $DAWN_GUARD
dawn::assert_backflow_not_pending || exit $DAWN_GUARD
```

### Test cases

| Scenario | Expected |
|---|---|
| Marker missing (stage-push never run) | rc=10, message mentions "never been pushed" |
| staging SHA ≠ marker (staging has new commit) | rc=10, message mentions staging changed |
| origin/staging SHA ≠ marker (bot commit after stage-push) | rc=10, message mentions preview theme changed |
| All three match | guard passes, rc proceeds to next check |

---

## Files affected

| File | Change |
|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | Add `dawn::backflow_scan`, `dawn::backflow_apply`, `dawn::assert_stage_push_current` |
| `.claude/skills/dawn-backflow/backflow.sh` | Rewrite reconcile loop to use new scan/apply |
| `.claude/skills/dawn-promote/promote.sh` | Add `dawn::assert_stage_push_current` guard |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow_scan.sh` | New: unit tests for `dawn::backflow_scan` |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow_apply.sh` | New: unit tests for `dawn::backflow_apply` |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow.sh` | Rewrite end-to-end tests for new behaviour |
| `.claude/skills/_dawn-ops-lib/tests/test_backflow_drift.sh` | Rewrite for new behaviour (no auto-fold) |
| `.claude/skills/_dawn-ops-lib/tests/test_promote_guard.sh` | Add stage-push guard cases |
| `.claude/skills/dawn-backflow/SKILL.md` | Rewrite Exit 22 for per-key single-select AskUserQuestion |
| `.claude/skills/dawn-promote/SKILL.md` | Add new Exit 10 cause: stage-push not current |
| `.claude/skills/_dawn-ops-lib/conventions.md` | Minor: update backflow description |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | Minor: update backflow row, promote row |

Unchanged: `dawn::reconcile_scan`, `dawn::reconcile_apply`, `dawn::reconcile_pending`,
`dawn::assert_backflow_not_pending`, `test_reconcile_scan.sh`, `test_reconcile_apply.sh`,
`test_reconcile_pending.sh`, `test_assert_backflow_not_pending.sh`, `test_stage_push_flow.sh`,
stage-push skill.
