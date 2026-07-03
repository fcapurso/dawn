# Dawn-ops: backflow auto-heals staging/origin-staging drift + plan/approve gate — Design

**Date:** 2026-07-03
**Repo:** Dawn / Zogezeept (operated from `ops`)
**Status:** Approved design, pending spec review → implementation plan
**Revises:** `dawn-backflow/backflow.sh`, `dawn-backflow/SKILL.md`, `_dawn-ops-lib/dawn-ops.sh`,
`_dawn-ops-lib/conventions.md` (§2a, §4). Builds directly on
`docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md` (the current-vs-staging
reconcile) without changing its behavior. No change to `dawn-harvest`, `dawn-ship`,
`dawn-promote`, or `dawn-upgrade`.

> Context: on 2026-07-03, live admin edits made in the staging preview theme's editor (a padding
> change and a `mailto:` link added to `templates/page.withdrawal.json`, plus Shopify's own
> formatting pass on the locale files) were silently absent from the reconciled config snapshot
> `dawn-backflow` produced. `origin/staging` (`7edb385f`, "Update from Shopify for theme
> dawn/staging") had them; local `staging` (`2f505c2d`, backflow's output) did not. The two commits
> are siblings — neither is an ancestor of the other — because `backflow.sh` never fetches or reads
> `origin/staging` at all (it only ever fetches `origin/current`, `backflow.sh:12`). This design
> closes that gap and, in the process, gives backflow the report-then-approve step it currently
> lacks.

---

## 1. Problem

Per `conventions.md` §2a, **both** `staging` and `current` are bot-linked: Shopify's GitHub
integration writes "Update from Shopify…" commits directly to whichever branch is wired to the
theme being live-edited. `current` is fetched and reconciled by backflow already (the 2026-07-02
design). `staging` is not — despite being just as bot-linked, and despite being the branch backflow
itself commits to.

Consequence: if an operator edits the **preview theme** in the admin UI, then runs local
`dawn-harvest`/`dawn-backflow` without first fetching and merging `origin/staging`, those edits sit
stranded on the remote. Backflow's collapse step (conventions.md §4: "collapses the loose 'Update
from Shopify…' bot commits… into that single commit each run") already knows how to absorb bot
commits **that are already part of local staging's history** — the gap is purely that they never
get fetched into local history in the first place.

Secondary, related problem: backflow currently computes and commits in one uninterruptible step.
There is no point at which the operator sees what is about to be folded together before it becomes
a commit.

---

## 2. Part A — auto-heal `origin/staging` drift

### 2.1 Fetch and preview

Add a step at the top of `backflow.sh`, before the existing non-config partition:

```
git fetch origin staging --quiet 2>/dev/null || true
base="$(git merge-base staging origin/staging)"   # GUARD if absent
```

This `merge-base` stays valid across repeated backflow runs even though backflow rewrites
`staging`'s tip on every collapse: the collapse only ever `reset --soft`s down to a **floor**
commit that both `staging` and `origin/staging` already share (conventions.md §4), it never rewrites
history below that floor. So the shared ancestor is stable and doesn't need special-casing.

Use git's three-way merge-tree preview (read-only — touches no ref, no working tree) to compute
what folding `origin/staging` into `staging` would produce:

```
dawn::staging_drift_scan
    # merge-tree(base, staging, origin/staging), read-only.
    # Returns: OK  + list of files that would change (if the merge is clean and non-empty)
    #          OK  + empty list (nothing to fold — already in sync)
    #          CONFLICT + list of conflicting files (real textual conflicts)
```

### 2.2 Conflict handling

A conflict here means the bot (via a live preview-theme edit) and the operator (locally) changed
the **same line of the same file**. This is a different, simpler kind of stop than the existing
config-leaf **collision** (which resolves at the JSON-value level via `AskUserQuestion`): a raw
textual merge conflict in an arbitrary file (most likely a locale file or a suffix-template
skeleton, neither of which the JSON-leaf reconciler covers) has no automated resolution and no
existing UI for picking a winner value-by-value. Treat it as a `DAWN_GUARD` (exit `10`), consistent
with the script's other "cannot proceed automatically" conditions (no merge-base, dirty tree):

```
GUARD: origin/staging conflicts with local staging in <file(s)> — resolve manually
(e.g. `git merge origin/staging` on a scratch branch, or hand-edit) and re-run.
```

Expected to be rare: the bot only ever writes admin/editor content; it would take editing the exact
same setting in both the admin UI and locally, between fetches, to collide.

### 2.3 Applying the fold

```
dawn::staging_drift_apply
    # For each file dawn::staging_drift_scan flagged as changed, write the merge-tree's
    # resulting blob into the working tree if it differs from what's there now. No merge
    # commit is created.
```

This materializes the fold the same way the existing current-vs-staging reconcile already
materializes folds (`backflow.sh` step 3, `dawn::reconcile_apply`): a plain working-tree write. No
merge commit is created — config folds are already just working-tree writes that the collapse step
(§2.4 below, unchanged) absorbs into the single snapshot commit. A merge commit would be soft-reset
away by the very next step anyway, so skip it.

### 2.4 Composition with the existing collapse (no change needed)

`backflow.sh`'s collapse step (reset `--soft` to the floor, `git add -A`, one commit) already
absorbs whatever is in the working tree, regardless of what produced it. Once §2.3 has written the
`origin/staging` fold into the tree, the collapse step needs no modification: it picks up those
changes exactly as it already picks up the current-vs-staging reconcile's writes. The floor
computation (`dawn::_commit_is_config_only` walk) is also unaffected — locale files are already
excluded from the config-only test (`backflow.sh` / `dawn-ops.sh:80`) and suffix templates already
classify as config, so a clean `origin/staging` fold never perturbs the floor.

---

## 3. Part B — plan, report, approve

### 3.1 New flow shape

```
bash backflow.sh                       # PLAN (default) — read-only, never writes or commits
  ├─ exit 10  GUARD                    — dirty tree / no merge-base / origin/staging conflict
  ├─ exit 21  STOP_JUDGMENT            — non-config files need classification, OR
  │                                      config collisions need decisions (unchanged from today)
  ├─ exit 0   nothing to do            — no drift, no folds, no collisions (unchanged fast-path)
  └─ exit 22  STOP_APPROVAL            — prints the plan report; re-run with --apply to commit

bash backflow.sh --apply [--decisions <path>]   # APPLY — performs the writes and commits
```

`--decisions <path>` is unchanged in meaning; it's still how collision resolutions are supplied.
`--apply` is new: it re-runs the identical computation (fetch, drift scan, reconcile scan) and,
finding everything already resolved, actually writes the folds and commits. Plan and apply share
one code path so the report can never drift from what apply actually does.

**Ordering (highest-priority stop wins, unchanged precedence + one new tier appended at the end):**

1. Dirty tree / branch guards (existing) → `10`
2. `origin/staging` merge conflict (new, §2.2) → `10`
3. Non-config current-ahead files needing classification (existing) → `21`
4. Config collisions needing decisions (existing) → `21`
5. **Everything above is clear → print the plan report → `22`, wait for `--apply`**

Collisions and classifications are resolved exactly as today (same `AskUserQuestion` flow, same
decisions TSV) *before* the new approval gate is reached. The approval gate shows the **final**
picture — including how collisions were resolved — so there's one clean yes/no at the end, not a
second collision review.

### 3.2 Report content

Plain-language, grouped by source, e.g.:

```
Backflow plan:

Pulling in from the live preview theme (origin/staging) — your local copy didn't have these:
  - locales/en.default.json, locales/nl.json  (formatting only)
  - templates/page.withdrawal.json  (padding_bottom, success_message)

Folding in from the live published theme (current):
  - config/settings_data.json — 6 settings changed
  - sections/footer-group.json, sections/header-group.json
  - templates/index.json, product.json, cart.json, collection.json

Keeping as-is (changed locally on staging, not overwritten):
  - (none this run)

Resolved collisions (from your decisions):
  - (none this run)

Proceed? re-run with: bash .claude/skills/dawn-backflow/backflow.sh --apply [--decisions <path>]
```

A "nothing changed anywhere" run skips the report and stays a plain `exit 0`, unchanged from
today — the approval gate only fires when there's something to actually approve.

### 3.3 SKILL.md flow update

The skill's existing loop (run → get 21 → collect decisions → re-run with `--decisions`) gains one
more link: once a run exits `22`, relay the report verbatim, ask one `AskUserQuestion`
(approve/abort), and on approval re-run with `--apply` (carrying forward the same `--decisions`
path if one was used). On abort, stop — nothing was written, the repo is untouched, no further
action needed.

---

## 4. Surface of change

| File | Change |
|---|---|
| `_dawn-ops-lib/dawn-ops.sh` | add `dawn::staging_drift_scan` (read-only merge-tree preview) and `dawn::staging_drift_apply` (materializes the clean fold into the working tree) |
| `dawn-backflow/backflow.sh` | fetch `origin/staging`; run drift scan before the non-config partition; route conflicts to `GUARD`; add `--apply` flag gating all writes/commit; on a clean plan with nothing to write, keep today's `exit 0`; otherwise print the report and `exit $DAWN_STOP_APPROVAL` (new, `22`) instead of committing |
| `dawn-backflow/SKILL.md` | document the `22` exit, the report format, and the approve → re-run-with-`--apply` step |
| `_dawn-ops-lib/conventions.md` | §2a: note that backflow now fetches+folds `origin/staging` automatically every run, so no manual "pull staging first" step is needed; §4: mention the new plan/apply split |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | update the backflow step to describe the new report + approval |

No change to `dawn-promote`, `dawn-ship`, `dawn-harvest`, `dawn-upgrade`, or the config-paths file
set.

---

## 5. Edge cases

- **`origin/staging` unreachable / fetch fails** (offline): `git fetch … || true` already swallows
  this in the existing `current` fetch; mirror that — a failed fetch just means the drift scan sees
  no new commits, not an error. (Same behavior gap as today's `current` fetch; not introduced by
  this change.)
- **`origin/staging` has no new commits**: drift scan returns an empty fold list; report omits the
  "pulling in from the live preview theme" section entirely rather than printing an empty one.
- **Both `origin/staging` drift and a config collision exist in the same run**: the collision stop
  (`21`) fires first (§3.1 ordering); the drift fold is still recomputed and included once the
  collision is resolved and the run reaches the plan report.
- **Repeated `--apply` runs with nothing new**: idempotent — second run finds no drift and no
  pending folds, falls through to the existing `exit 0` fast path, no approval prompt.
- **Conflict in a file the JSON-leaf reconciler also targets** (e.g. a suffix template's `settings`
  block edited both live and locally in the exact same spot): still a raw textual conflict at the
  `origin/staging` fold stage, which runs *before* the JSON-leaf reconcile — resolved as a `GUARD`
  per §2.2, not routed into the leaf-collision UI. Documented limitation; expected to be very rare.

---

## 6. Testing

Extends the existing fixture-repo test seams (local refs, no network):

1. **Clean drift fold** (this incident's shape: bot edits on `origin/staging` local doesn't have,
   no other changes) → plan report lists them under "pulling in from the live preview theme"; apply
   produces a snapshot commit containing them.
2. **No drift** → report omits that section; a fully no-op run stays `exit 0` with no prompt.
3. **Drift + current-ahead fold together** → both sections appear in one report.
4. **Drift conflict** (same line changed both remotely and locally) → `GUARD` (`10`), clear message
   naming the file(s), nothing written.
5. **Drift + a genuine config collision** → collision stop (`21`) fires first; after decisions are
   supplied, the plan report reflects the resolved value; `--apply` commits both.
6. **Plan then abort** → no `--apply` run follows; repo state unchanged (working tree and `staging`
   ref both untouched by the plan-only run).
7. **Plan/apply consistency** → apply's resulting commit matches exactly what the immediately
   preceding plan report described (no drift between the two phases sharing one code path).

---

## 7. Exit codes

| Code | Constant | When |
|---|---|---|
| `0` | `DAWN_OK` | nothing to do, or (with `--apply`) reconcile applied and committed |
| `10` | `DAWN_GUARD` | dirty tree, wrong branch, no merge-base, invalid JSON, **or `origin/staging` merge conflict (new)** |
| `21` | `DAWN_STOP_JUDGMENT` | collisions need decisions, or non-config files need classification (unchanged) |
| `22` | `DAWN_STOP_APPROVAL` | **(new)** plan computed and printed; re-run with `--apply` to commit |

---

## 8. Out of scope / follow-ups

- **Applying the same auto-fetch/plan-gate pattern to `dawn-harvest`, `dawn-ship`, `dawn-promote`,
  `dawn-upgrade`.** Deferred — those don't read live preview-theme config the way backflow does
  (harvest classifies code/structure commits, which the bot never writes), so there's no known drift
  risk there today. Revisit only if drift is observed to bite one of them in practice.
- **Element-level conflict resolution UI for raw textual `origin/staging` conflicts** — out of
  scope; these route to a manual-resolve `GUARD` (§2.2). If this turns out to be common in practice
  (not expected), a follow-up could route conflicting locale/skeleton files through a dedicated
  decision UI, mirroring the JSON-leaf collision flow.
- **Itemized (per-file) approval** — explicitly rejected in favor of one overall gate (this doc,
  §3.1); collisions keep their own itemized decisions, but the final plan is a single approve/abort.

---

## 9. Immediate use: today's stuck divergence

Once this lands, running the new `bash .claude/skills/dawn-backflow/backflow.sh` on the current
repo state is expected to detect that `origin/staging` (`7edb385f`) has the padding/`mailto:`-link
edits local `staging` (`2f505c2d`) is missing, print them in the plan report, and — on approval —
fold them into a fresh snapshot commit. This serves as the first real-world exercise of the new
drift-scan path, using the exact incident that motivated this design.
