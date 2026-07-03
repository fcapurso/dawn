# Dawn-ops: persisted sync markers replace merge-base for reconcile "base" — Design

**Date:** 2026-07-03
**Repo:** Dawn / Zogezeept (operated from `ops`)
**Status:** Approved design, pending spec review → implementation plan
**Revises:** `dawn::reconcile_scan` (the "base" computation) in `_dawn-ops-lib/dawn-ops.sh`,
`dawn-backflow/backflow.sh`, `dawn-promote/promote.sh`, `_dawn-ops-lib/conventions.md`. Builds on
`docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md` (the leaf-level reconciler)
and `docs/superpowers/specs/2026-07-03-dawn-backflow-staging-drift-and-plan-gate-design.md` (the
`origin/staging` fold this design shares its "base" logic with). No change to `dawn-harvest`,
`dawn-ship`, or `dawn-upgrade`.

> Context: on 2026-07-03, immediately after using the newly-built `origin/staging`-drift-aware
> backflow for the first time, the operator deliberately reverted a setting (`padding`) on the live
> preview theme back to its original value, expecting the next backflow run to pick that up as a
> fresh change. It didn't — backflow reported "nothing to reconcile" for that setting. Root cause:
> `dawn::reconcile_scan`'s "base" (the reference point for "did anything change since we last
> agreed?") is computed via `git merge-base staging <other>`. Because `dawn-backflow` deliberately
> collapses `staging`'s own commit history down to one snapshot on every run (conventions.md §4),
> `staging`'s ancestry keeps "forgetting" its own recent past — so the merge-base search lands on an
> older and older shared commit each run, one that may predate several already-folded changes. When
> the operator's revert happened to match that stale, older reference value, the diff correctly (by
> its own logic) saw "no change" — even though a real, fresh edit had just been made. This is a
> structural conflict between two of backflow's own design goals: "staging always ends in exactly
> one commit" and "3-way diff against a stable historical reference point."

---

## 1. Problem

`dawn::reconcile_scan`'s 3-way comparison needs a `base` value per leaf: the value staging and the
remote (`current` or `origin/staging`) are presumed to have last agreed on, so that a value differing
from `base` on one side and not the other can be attributed to "that side changed it." Today, `base`
is derived from `git merge-base staging <other>` — an inference from commit ancestry, not a recorded
fact.

That inference silently breaks whenever `staging`'s ancestry is rewritten in a way that discards a
point where staging and the remote were known to agree — which `dawn-backflow` does **on every
single run**, by design (the config-snapshot-collapse invariant). The merge-base search doesn't fail
loudly when this happens; it just quietly returns an older, technically-still-shared commit, whose
content may no longer reflect "the last time we actually looked." The bug is invisible until a
value happens to round-trip back to that older commit's value, at which point a genuine new change
is misclassified as "no change" and silently dropped.

**Detecting "did the bot commit something" was never the missing piece** — commit provenance is
already fully known. The missing piece is a reliable definition of **"since when."**

---

## 2. Core model: persisted sync markers, not inferred ancestry

Replace the ancestry-based `base` with an explicitly recorded one: a git ref, per remote, pointing
at the exact commit that remote was at the last time it was fully and correctly reconciled against.

### 2.1 The two markers

```
refs/dawn-sync/staging-remote   → last origin/staging commit fully reconciled against
refs/dawn-sync/current          → last origin/current commit fully reconciled against
```

Plain git refs (not branches — they never show in `git branch`, only `git for-each-ref` /
`git ls-remote`). A ref is the correct primitive here specifically because refs are git's actual
reachability mechanism: pointing a ref at a commit is what keeps that commit (and its whole tree —
every leaf's value at that moment) from ever being garbage-collected. A plain file recording a SHA
as text would **not** protect that commit; nothing would stop it from eventually disappearing.

### 2.2 What "base" becomes

`dawn::reconcile_scan`'s `base` for a comparison against ref `<other>` is no longer
`git merge-base staging <other>` — it's simply "the tree at whatever `refs/dawn-sync/<marker-for-other>`
currently points to." The rest of the reconcile algorithm (leaf-level 3-way classification,
`current_ahead` / `staging_ahead` / `collision` verdicts) is completely unchanged — only the source
of `base` changes.

### 2.3 Who writes the markers, and when

Both write sites end by pointing their relevant marker(s) at the commit(s) they just finished
reconciling against, then push that ref (a plain `git push origin refs/dawn-sync/<name>`, not a
branch push):

- **`dawn-backflow`**, at the end of a successful `--apply` run: sets **both** markers to the
  `origin/staging` and `origin/current` SHAs it fetched and reconciled against that run —
  unconditionally, even if nothing needed folding. A "nothing to fold" verdict is still a complete,
  correct reasoning pass over the remote's current state; there's no reason to leave the marker
  pointing at an older commit than necessary.
- **`dawn-promote`**, at the end of a successful promote: sets **both** markers to the new shared
  state. Promote force-pushes `staging` onto both `origin/current` and `origin/staging`
  (conventions.md §4 — promote's push of the collapsed `staging` back to `origin/staging` is already
  an established part of its job, not new to this design), so after a successful promote all three
  — `staging`, `origin/staging`, `origin/current` — are identical. If promote doesn't also refresh
  the markers, the next backflow run reasons from a stale pre-promote base: any leaf that was
  staging-ahead before the promote (and got pushed everywhere by it) now has a base that still
  reflects the *old*, pre-promote value on that leaf — so a genuine future live edit to that same
  leaf gets compared against an obsolete reference and misclassified as a **collision** against
  staging, when only the remote actually changed. Promote must own this update; backflow has no
  visibility into promote ever having run.

### 2.4 Reading the markers

Both markers must be fetched explicitly — a bare `git fetch origin` only follows branches, not
arbitrary refs. `backflow.sh` fetches `refs/dawn-sync/staging-remote` and `refs/dawn-sync/current`
alongside its existing `current`/`staging` fetches.

### 2.5 Bootstrap (marker doesn't exist yet)

First run ever with this feature (or a marker deleted/lost some other way): fall back to today's
`git merge-base staging <other>` for that one run only. The run's own successful completion writes
the marker per §2.3, so every subsequent run uses the persisted marker. No other special-casing —
a missing marker is not an error condition, just "not established yet."

---

## 3. Interaction with existing components (unchanged by design, verified deliberately)

- **`dawn::reconcile_pending`** (used by `dawn-promote`'s guard) already calls `dawn::reconcile_scan`.
  Once `reconcile_scan`'s `base` computation switches to the marker, this guard is automatically
  correct with no separate code change — it was never doing its own ancestry lookup.
- **The leaf-level verdict table** (`agree` / `current_ahead` / `staging_ahead` / `collision`, per
  the 2026-07-02 design) is untouched. This design only changes where `base` comes from, not how it's
  used once obtained.
- **The `origin/staging` non-config raw-merge path** (`dawn::nonconfig_drift_scan`/`apply`, from the
  2026-07-03 drift design) uses `git merge-base staging <remote>` for its own, separate purpose —
  computing an actual 3-way *text* merge, not a leaf-level value comparison. That merge-base usage
  is not the same failure mode (it's not trying to answer "since when," it's git's own merge
  machinery needing *a* valid common ancestor to merge from) and is **out of scope** for this design.
  It has its own latent version of a similar problem (a collapsed-history merge-base could, in
  principle, produce a wider or narrower merge than intended), but that's unconfirmed and separable;
  not addressed here.

---

## 4. Edge cases

- **Marker points at a commit that's since been force-pushed away everywhere** (e.g. someone
  manually rewrote `origin/staging`'s history): the marker ref itself keeps the old commit reachable
  regardless, so reads still succeed — the diff is simply against whatever that pinned commit still
  contains. If the rewrite was a deliberate reset the operator wants reflected as "no assumed prior
  state," they'd need to manually delete/reset the marker ref, falling back to §2.5's bootstrap path.
  Not automated; expected to be rare enough not to warrant tooling.
- **Backflow's plan-mode rollback** (`_dawn_bf_abort`, from the 2026-07-03 drift design): a plan-only
  run must **not** write or push the markers — only a completed `--apply` counts as "fully
  reconciled." The existing `--apply`-gated write in §2.3 already only fires in the success path
  that survives to the end, so a plan-mode abort naturally never reaches it; no extra guard needed.
- **Concurrent backflow runs** (two operators, or an operator and CI, running at once): the last
  writer's marker wins, same failure mode as any other unsynchronized concurrent git push — not
  meaningfully different from the existing risk of concurrent `staging` pushes, and out of scope to
  solve generally here.
- **Promote fails partway** (pushes to `current` succeeds, marker update fails, or vice versa):
  the marker write should happen only after the force-pushes to `current`/`origin/staging` have
  both succeeded, so a partial promote failure leaves the markers at their last-known-good (possibly
  stale, but not *wrong*) state rather than a marker pointing at content that was never actually
  pushed.

---

## 5. Surface of change

| File | Change |
|---|---|
| `_dawn-ops-lib/dawn-ops.sh` | `dawn::reconcile_scan`'s `base` computation reads from the marker ref instead of `git merge-base`, with the bootstrap fallback (§2.5); add small helpers to read/write/push a marker ref given a logical name (`staging-remote` / `current`) |
| `dawn-backflow/backflow.sh` | fetch both marker refs at startup; on successful `--apply` completion, write + push both markers to the SHAs fetched that run |
| `dawn-promote/promote.sh` | after both force-pushes (to `current` and to `origin/staging`) succeed, write + push both markers to the new shared state |
| `_dawn-ops-lib/conventions.md` | document the marker refs, what they mean, and that both `dawn-backflow` and `dawn-promote` are responsible for keeping them current |

No change to `dawn-harvest`, `dawn-ship`, `dawn-upgrade`, or the leaf-reconcile verdict logic itself.

---

## 6. Testing

Extends the existing fixture-repo test seams:

1. **Marker absent (bootstrap)** → falls back to `git merge-base`, behaves exactly as today;
   completing the run establishes the marker.
2. **Marker present, remote unchanged since marker** → no drift detected, regardless of what git
   ancestry would otherwise compute (this is the test that directly reproduces and proves the fix
   for today's incident: collapse staging's history away from a commit, confirm a value that
   round-trips back to an old ancestry-shared value is still correctly seen as "changed" because the
   marker — not ancestry — is what's consulted).
3. **Marker present, remote changed since marker** → folds correctly (or collides, if staging also
   changed the same leaf), independent of how much staging's own history has been rewritten since.
4. **Successful `--apply` updates both markers** to the fetched SHAs; a plan-mode-only run does not.
5. **Successful promote updates both markers** to the new shared state; a failed/partial promote does
   not update markers pointing at content that was never actually pushed.
6. **Post-promote regression** (the scenario from this design's discussion): a staging-ahead leaf
   gets promoted everywhere; a fresh unrelated live edit to that same leaf on `current` afterward is
   correctly folded (current-ahead), not misclassified as a collision against staging.

---

## 7. Out of scope / follow-ups

- Reconciling `dawn::nonconfig_drift_scan`'s own separate `git merge-base` usage (§3) — different
  problem class, not confirmed broken, deferred.
- Any UI/tooling for manually resetting a marker — deferred until a real need surfaces (§4's edge
  case is expected to be rare).
- Concurrent-run coordination/locking — out of scope, matches existing unsynchronized-push risk
  elsewhere in this branch model.
