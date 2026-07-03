# Dawn-ops: backflow auto-heals staging/origin-staging drift + plan/approve gate — Design

**Date:** 2026-07-03
**Repo:** Dawn / Zogezeept (operated from `ops`)
**Status:** Approved design, pending spec review → implementation plan
**Revises:** `dawn-backflow/backflow.sh`, `dawn-backflow/SKILL.md`, `_dawn-ops-lib/dawn-ops.sh`,
`_dawn-ops-lib/conventions.md` (§2a, §4). Generalizes (parameterizes) the leaf-level reconciler from
`docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md` to reuse it for a second
comparison ref; existing call sites keep their default behavior unchanged. No change to
`dawn-harvest`, `dawn-ship`, `dawn-promote`, or `dawn-upgrade`.

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

> **Corrected during plan research (2026-07-03).** The first cut of this section routed *all*
> `origin/staging` drift through a raw `git merge-tree` text merge. Empirically verified against
> this repo's actual (pretty-printed, one-key-per-line) JSON: git's default line-based 3-way merge
> produces **false-positive conflicts** even for semantically independent edits, whenever the two
> changed lines are adjacent with no unchanged line of context between them (reproduced with a
> minimal fixture: two branches each editing a *different* key one line apart from each other
> conflicted). Config-class files already have a leaf-level (parsed-JSON-value) reconciler
> immune to exactly this failure mode (2026-07-02 design §2.3). Splitting the mechanism by file
> class — leaf reconcile where one already exists, raw merge only where it doesn't — avoids
> spurious manual-resolution stops on the file class that matters most (settings/templates), at
> the cost of the raw-merge path (locale files only) still being conflict-prone. The corrected
> design below reflects this split; the report/approval-gate shape from Part B is unaffected.

### 2.1 Two mechanisms, split by file class

- **Config-class files** (`dawn::config_targets`: the `config-paths.txt` set + suffix-template
  `settings` leaves) — route `origin/staging` drift through the **same leaf-level reconciler**
  already built for current-vs-staging (2026-07-02 design). Generalize
  `dawn::reconcile_scan`/`dawn::reconcile_apply` to take the "other side" ref as a parameter
  (defaulting to `dawn::current_ref` at existing call sites, so today's behavior is unchanged),
  and call them a second time with `dawn::staging_remote_ref` (new, mirrors `dawn::current_ref`;
  test seam `DAWN_STAGING_REMOTE_REF`) as the other side. No raw text merge is involved for these
  files, so re-serialization noise and line-adjacency false conflicts don't apply — only genuine
  same-setting-changed-both-places collisions stop the run, exactly like today's current-vs-staging
  collisions.
- **Everything else the bot might touch** — in practice, locale files, which are deliberately
  outside the leaf reconciler's scope (`dawn::_commit_is_config_only`'s `locales/*` exclusion; no
  per-key reconciliation exists for them today, config-class or not). No leaf reconciler exists to
  reuse, so fold these via `git merge-tree` (real 3-way text merge, read-only preview via
  `--write-tree --merge-base=<base>`, verified above to exit `1` with `CONFLICT` markers on
  overlap). A conflict here is a `DAWN_GUARD` (§2.2) — accepted as a documented limitation, since
  it's confined to a narrow, already-excluded file class rather than the config files a store edits
  most often.

### 2.2 Conflict handling (raw-merge path only)

A conflict here means the bot (via a live preview-theme edit) and the operator (locally) changed
overlapping or adjacent lines of the same non-config file (in practice, a locale file). There's no
per-key UI for these (unlike config-class collisions, §2.1), so treat it as a `DAWN_GUARD` (exit
`10`), consistent with the script's other "cannot proceed automatically" conditions:

```
GUARD: origin/staging conflicts with local staging in <file(s)> — resolve manually
(e.g. `git merge origin/staging` on a scratch branch, or hand-edit) and re-run.
```

### 2.3 Sequencing: the origin/staging fold must land as a real commit first

Both `dawn::reconcile_scan` and `dawn::reconcile_apply` read from `staging`'s **committed** tip
(`git show staging:$file`), never the working tree. So the origin/staging fold must be committed to
local `staging` *before* the existing current-vs-staging reconcile runs — otherwise that reconcile
would compute against stale, pre-fold staging content. Step 0 is therefore:

1. Fetch `origin/staging`.
2. Run the (generalized) leaf reconciler against `dawn::staging_remote_ref` for config-class files.
   Any collision here stops the run (exit `21`) with the *same* `AskUserQuestion` flow used for
   current-vs-staging collisions today — resolved and re-run before continuing (see §3.1 for how
   this composes with the existing collision tier: sequential, not merged into one decisions file,
   to avoid ambiguity if the *same* file+path collided against both `origin/staging` and `current`
   in the same run — an edge case rare enough not to warrant a compound decisions-file key).
3. Apply the resolved folds to the working tree and commit them to `staging` (e.g. `git commit -m
   "fold origin/staging (config)"`).
4. Fold non-config files (§2.1 second bullet) via `git merge-tree`; `GUARD` on conflict; otherwise
   write and commit (e.g. `git commit -m "fold origin/staging (other)"`).
5. Continue into the existing non-config partition, current-vs-staging reconcile, and collapse —
   all unchanged, now operating on a `staging` tip that already includes the `origin/staging` drift.

### 2.4 Composition with the existing collapse (no change needed)

The intermediate commits from steps 2.3.3–2.3.4 are not special: the collapse step already squashes
any number of commits above the floor into one snapshot (conventions.md §4; validated by
`test_backflow.sh`'s "multiple config commits… collapse into ONE snapshot" case), so they disappear
into the final single commit exactly like today's already-fetched bot commits do. The floor
computation (`dawn::_commit_is_config_only` walk) is unaffected: locale-only commits are already
excluded from the config-only test, and config-class folds already classify as config, so these new
intermediate commits never become the floor by accident.

---

## 3. Part B — plan, report, approve

### 3.1 New flow shape

```
bash backflow.sh                       # PLAN (default) — read-only, never writes or commits
  ├─ exit 10  GUARD                    — dirty tree / no merge-base / origin/staging raw-merge conflict
  ├─ exit 21  STOP_JUDGMENT            — origin/staging config collisions, non-config files needing
  │                                      classification, or current-vs-staging config collisions
  │                                      need decisions (see ordering below)
  ├─ exit 0   nothing to do            — no drift, no folds, no collisions (unchanged fast-path)
  └─ exit 22  STOP_APPROVAL            — prints the plan report; re-run with --apply to commit

bash backflow.sh --apply [--decisions <path>]   # APPLY — performs the writes and commits
```

`--decisions <path>` is unchanged in meaning; it's still how collision resolutions are supplied —
now potentially across two collision tiers (origin/staging and current), consumed independently by
each tier's own reconcile pass (same file, same `<file>\t<path-json>\t<verdict>` format; an operator
resolving both in one round just writes both tiers' lines into the same TSV).
`--apply` is new: it re-runs the identical computation (fetch, drift fold, reconcile scans) and,
finding everything already resolved, actually writes the folds and commits. Plan and apply share
one code path so the report can never drift from what apply actually does.

**Ordering (highest-priority stop wins — this is the script's actual execution order, per §2.3):**

1. Dirty tree / branch guards (existing) → `10`
2. `origin/staging` **config-class** collisions needing decisions (new, §2.1 first bullet) → `21`
3. `origin/staging` **non-config** raw-merge conflict (new, §2.2) → `10` — only reached once (2) is
   clear, since the config-class fold commits before the non-config fold is attempted (§2.3)
4. Non-config current-ahead files needing classification (existing) → `21`
5. Current-vs-staging config collisions needing decisions (existing) → `21`
6. **Everything above is clear → print the plan report → `22`, wait for `--apply`**

All collisions and classifications are resolved exactly as today (same `AskUserQuestion` flow, same
decisions TSV) *before* the new approval gate is reached. The approval gate shows the **final**
picture — including how every collision was resolved — so there's one clean yes/no at the end, not
a second collision review. A run can require more than one resolve-and-re-run round-trip if it hits
more than one tier (e.g. an `origin/staging` collision *and* a current-vs-staging collision in the
same run) — no different in kind from today, where a single collision already requires one
round-trip.

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
| `_dawn-ops-lib/dawn-ops.sh` | add `dawn::staging_remote_ref` (mirrors `dawn::current_ref`, test seam `DAWN_STAGING_REMOTE_REF`); generalize `dawn::reconcile_scan`/`dawn::reconcile_apply` to accept an "other ref" parameter (default `dawn::current_ref`, preserving today's call sites); add `dawn::nonconfig_drift_scan`/`dawn::nonconfig_drift_apply` (raw `git merge-tree` preview/apply for the non-config-file fold, §2.1 second bullet) |
| `dawn-backflow/backflow.sh` | fetch `origin/staging`; add Step 0 (§2.3): config-class leaf-reconcile fold against `dawn::staging_remote_ref` (commit), then non-config raw-merge fold (commit); route raw-merge conflicts to `GUARD`; add `--apply` flag gating all writes/commit; on a clean plan with nothing to write, keep today's `exit 0`; otherwise print the report and `exit $DAWN_STOP_APPROVAL` (new, `22`) instead of committing |
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
- **Both `origin/staging` drift and a current-vs-staging config collision exist in the same run**:
  the `origin/staging` collision tier (if any) fires first, then the non-config classification tier,
  then the current-vs-staging collision tier (§3.1 ordering) — each resolved and re-run in turn; the
  drift fold is recomputed fresh each time and included once everything is resolved and the run
  reaches the plan report.
- **Repeated `--apply` runs with nothing new**: idempotent — second run finds no drift and no
  pending folds, falls through to the existing `exit 0` fast path, no approval prompt.
- **The exact same setting is edited both live on the preview theme and locally in staging** (e.g. a
  suffix template's `settings` value): this is a genuine config-class collision, and — because
  `origin/staging` drift now goes through the same leaf reconciler as current-vs-staging drift
  (§2.1) — it's correctly routed to the leaf-collision `AskUserQuestion` UI, not a raw-merge `GUARD`.
  The `GUARD` path is reserved for non-config files only (in practice, locale files), where no
  per-key UI exists.

---

## 6. Testing

Extends the existing fixture-repo test seams (local refs, no network):

1. **Clean config-class drift fold** (this incident's shape: bot edits a suffix-template `settings`
   value or a `config-paths.txt` file that local staging doesn't have, no other changes) → plan
   report lists it under "pulling in from the live preview theme"; apply produces a snapshot commit
   containing it.
2. **Clean non-config drift fold** (bot edits a locale file's formatting, no overlapping local
   edits) → folded via the raw-merge path; same report section.
3. **No drift** → report omits that section; a fully no-op run stays `exit 0` with no prompt.
4. **Drift + current-ahead fold together** → both sections appear in one report.
5. **Non-config drift conflict** (a locale file changed on adjacent/overlapping lines both remotely
   and locally) → `GUARD` (`10`), clear message naming the file(s), nothing written.
6. **Config-class drift collision** (the same setting changed both live on the preview theme and
   locally) → `21`; after a decision is supplied, the plan report reflects the resolved value.
7. **Drift collision + a separate current-vs-staging collision in the same run** → each tier stops
   in turn (§3.1 ordering); after both are resolved, one plan report reflects both resolutions;
   `--apply` commits everything in one snapshot.
8. **Plan then abort** → no `--apply` run follows; repo state unchanged (working tree and `staging`
   ref both untouched by the plan-only run).
9. **Plan/apply consistency** → apply's resulting commit matches exactly what the immediately
   preceding plan report described (no drift between the two phases sharing one code path).

---

## 7. Exit codes

| Code | Constant | When |
|---|---|---|
| `0` | `DAWN_OK` | nothing to do, or (with `--apply`) reconcile applied and committed |
| `10` | `DAWN_GUARD` | dirty tree, wrong branch, no merge-base, invalid JSON, **or a raw-merge conflict folding `origin/staging`'s non-config-file drift (new, §2.2)** |
| `21` | `DAWN_STOP_JUDGMENT` | **`origin/staging` config-class collisions need decisions (new, §2.1)**, non-config files need classification, or current-vs-staging config collisions need decisions (existing) |
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
