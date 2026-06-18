# Dawn theme-ops skills — design

**Date:** 2026-06-18
**Repo:** `fcapurso/dawn`, `ops` branch (home base for docs + skills)
**Status:** Design approved in brainstorming; pending spec review before planning.
**Depends on:** the layered branch model + runbook from
`docs/superpowers/specs/2026-06-17-dawn-repo-layer-separation-design.md` and
`docs/superpowers/runbook/dawn-update-and-promote.md`.

## Problem

The runbook procedures (backflow, promote, Dawn-upgrade, harvest) are written for a human operator
who supplies judgment at the ambiguous moments. They are **not reliably agent-executable**: they
contain interactive steps (`git checkout -p`), judgment calls (layer classification, conflict
resolution), live/destructive operations (force-push to `current`), and lack verification gates.
We want these operations encoded as **skills** an agent can run reliably and safely on a live
storefront.

## Goals

- Encode **four** operations as skills: `dawn-backflow`, `dawn-promote`, `dawn-upgrade`,
  `dawn-harvest`.
- **Auto-mechanical + hard-STOP at gates:** the skill does all safe, deterministic work and
  verification, then STOPS for explicit human approval at (a) any live/irreversible step and
  (b) any judgment call.
- **Reliability via deterministic scripts:** mechanical git work lives in tested bash scripts with
  built-in verification, not in agent-improvised commands.
- Skills discoverable from any branch/worktree; docs + skills versioned on `ops`.

## Non-goals (YAGNI)

- No skill for preview-theme linkage (Shopify admin UI; stays manual).
- No skill for full inventory/rebuild (one-time, already done).
- No fully-autonomous live promote (always human-gated).
- No multi-project generalization yet (built for this store; can generalize later).

## Home-base layout

- **`ops` branch** holds the canonical `.claude/skills/*` and `docs/superpowers/*`. Never deployed
  (Shopify ignores non-theme dirs; theme branches stay pure regardless).
- **Persistent `ops` worktree** (e.g. `~/Shopify/dawn-ops/`) — stable path for docs + symlink target.
- **Discoverability:** a location-aware `setup.sh` (on `ops`) makes the skills resolvable from any
  branch/worktree. Implementation tries the cleanest available mechanism first, falls back as needed:
  1. **Preferred:** register the external skills dir via Claude Code `settings.json` / a thin local
     plugin (relocation = edit one path). *Verify CC supports this during implementation.*
  2. **Fallback:** `setup.sh` creates `~/.claude/skills/dawn-* →` (absolute) symlinks into the ops
     worktree. Idempotent and **location-aware** (derives its own path), so after any relocation you
     re-run it from the new location and symlinks re-point. No drift (single source), relocation is a
     one-command fix.

## Components

```
.claude/skills/
  setup.sh                ← location-aware installer (symlinks or settings/plugin registration)
  _dawn-ops-lib/
    conventions.md        ← invariants + branch model (single source of truth, referenced by all)
    dawn-ops.sh           ← sourced bash library of guarded helpers
  dawn-backflow/  SKILL.md + backflow.sh
  dawn-promote/   SKILL.md + promote.sh
  dawn-upgrade/   SKILL.md + upgrade.sh
  dawn-harvest/   SKILL.md + harvest.sh
```

### `_dawn-ops-lib/dawn-ops.sh` — shared, guarded helpers
Single source for the mechanics every skill needs. Functions (each self-verifying):
- `assert_not_current` — abort if operating on/pushing `current` outside the sanctioned promote path.
- `assert_clean_tree` — abort on a dirty worktree.
- `make_worktree <branch> [path]` / `cleanup_worktree <path>` — throwaway worktree lifecycle.
- `config_files()` — emits the canonical config-snapshot path set (`settings_data.json`,
  `sections/*-group.json`, stock `templates/*.json`).
- `merge_base_vanilla()` — `git merge-base upstream/main origin/current` (the true L0 base).
- `verify_tree_equal <refA> <refB> [pathspec]` — assert two trees match (the acceptance-test
  primitive); non-zero on mismatch with a diff summary.
- `backflow_pending()` — true if `origin/current` has commits not in `staging` (gate for promote).

### The four skills (SKILL.md = when/orchestration/gates; *.sh = mechanics)

| Skill | Auto (mechanical) | Hard-STOP gate |
|---|---|---|
| **dawn-backflow** | fetch `current`; classify changed files (config / generic / enrichment / churn); apply config churn by amending the config-tip (Case A) or drop-recreate (Case B); verify | **ambiguous classification** (is this generic-L1, enrichment, or config?) → present + ask |
| **dawn-promote** | require no `backflow_pending`; tag `config-archive/<date>`; push `staging`; verify `staging` vs `current` delta is only the documented set | **the live `staging:current` force-push** → only with `--confirm-live`, set after explicit approval |
| **dawn-upgrade** | `ff dawn-vanilla` to target tag; `rebase customizations`; `rebase staging`; run verifications | **any rebase conflict** → stop, show the conflict, ask |
| **dawn-harvest** | locate the candidate change; build the L1 commit on `customizations`; `rebase staging` (config stays at tip) | **per-hunk "is this generic?" split** → propose the split + ask |

### Safety model (structural, not just procedural)
- Every script begins with guards (`assert_not_current`, `assert_clean_tree`, preconditions).
- **Only `promote.sh` can write to `current`, and only its final step, gated behind `--confirm-live`.**
  Default invocation runs everything up to the gate and exits with a distinct "STOP: awaiting live
  confirmation" status + a printed summary of exactly what it will push.
- Judgment gates: the script does what it deterministically can, prints the ambiguous part, and exits
  with a "STOP: needs human decision" status. The SKILL.md instructs the agent to ask the user and
  re-invoke with the decision.
- Distinct exit codes for: success, guard-failure, STOP-live, STOP-judgment, verification-failure.

### Worktree lifecycle
Each skill operates in a **throwaway worktree** for its target branch (created by `make_worktree`,
removed on success), so the user's main checkout and the persistent `ops` worktree are never
disturbed. Aligns with `superpowers:using-git-worktrees`.

## Testing

Scripts are tested against a **scratch fixture repo** (a local clone with synthetic
`dawn-vanilla`/`customizations`/`staging`/`current` branches), never the real branches. Assertions:
- guards fire (refuse on `current`, dirty tree, missing preconditions);
- happy path produces the expected tree (via `verify_tree_equal`);
- gates stop with the correct exit code (live force-push blocked without `--confirm-live`; conflicts
  and ambiguous classification halt);
- `setup.sh` is idempotent and re-points after a simulated relocation.

## Acceptance criteria

1. From a fresh shell on any branch/worktree, the four skills are discoverable (post-`setup.sh`).
2. `dawn-backflow` on a config-only change keeps `staging` at exactly one config-snapshot commit.
3. `dawn-promote` refuses to push live without approval; with approval, `current` matches `staging`.
4. `dawn-upgrade` advances the base and replays the layers, halting on conflict.
5. `dawn-harvest` produces a clean L1 commit and re-based `staging`, halting on per-hunk ambiguity.
6. All scripts pass the fixture test suite; none can touch `current` outside the gated promote path.
