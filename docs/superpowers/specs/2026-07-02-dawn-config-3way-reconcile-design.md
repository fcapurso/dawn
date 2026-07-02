# Dawn-ops: direction-aware config reconcile (3-way key-level merge) — Design

**Date:** 2026-07-02
**Repo:** Dawn / Zogezeept (operated from `ops`)
**Status:** Approved design, pending spec review → implementation plan
**Revises:** the config-snapshot / backflow model in
`.claude/skills/_dawn-ops-lib/conventions.md` (§4, §4 backflow routing) and the `dawn-backflow`
and `dawn-promote` skills. Adds a key-level 3-way merge to `dawn-ops.sh`. No change to
`dawn-harvest`, `dawn-ship`, or the L1/L2 classification model.

> Context: this came out of trying to promote the EU right-of-withdrawal footer link. The three
> keys that wire the link on (`show_withdrawal_link`, `withdrawal_page`, `policies_own_line`) were
> configured in **staging**'s preview theme editor. `dawn-promote` refused (Exit 10 —
> "backflow first"), and following the instruction to run `dawn-backflow` would have **silently
> deleted those three keys** from staging (blind "current wins" overwrite), shipping the compliance
> feature in the *off* state. The current model has no way for a config value authored on staging
> to survive backflow and reach `current`.

---

## 1. Problem

The config machinery is one-way and destructive on the staging side:

- **`config-paths.txt`** defines the "config" file set (`settings_data.json`,
  `settings_schema.json`, header/footer groups, and the default templates).
- **`dawn-backflow` (Case A)** does, per config file, a blind
  `git checkout origin/current -- <file>` then `--amend`. Current overwrites staging wholesale.
  Any value authored on staging is destroyed.
- **`dawn-promote`** guards on `dawn::backflow_pending`, which is
  `! git diff --quiet staging origin/current -- <config-paths>` — i.e. "do these files *differ*?"
  It **cannot tell "staging ahead" from "current ahead."** So a state where staging holds a
  deliberate config change that current lacks is a **false positive**: promote refuses, and the
  only way to clear the guard is to backflow, which erases the change.

This is correct for *content the merchant edits on the live theme* (current is authoritative), but
wrong for the real workflow: **you change a setting in staging's preview theme to test an L1/L2
change, then want it to promote to current.** That deliberate change can touch any key in any
config file; it is not confined to a declarable set of "staging-owned" files.

### Live example (state at design time)

`git merge-base staging origin/current` = `9dc7fa17`. For `sections/footer-group.json`:

| key | base (`9dc7fa17`) | staging | current |
|---|---|---|---|
| `footer.show_withdrawal_link` | absent | `true` | absent |
| `footer.withdrawal_page` | absent | `"contract-withdrawal"` | absent |
| `footer.policies_own_line` | absent | `true` | absent |

All three: **staging changed relative to base, current did not.** The intent is unambiguous from
history alone — no declaration required.

---

## 2. Core model: 3-way key-level merge

Treat config reconciliation exactly like git treats a code merge, but on **parsed JSON values at
their paths** rather than text lines. "Did I change this deliberately on staging?" versus "is this
regular config I changed on current?" is not something to *declare* — it is already recorded in
history. Read it.

### 2.1 The three inputs

For each config file and each setting within it, compare three values:

- **base** = value at `git merge-base staging origin/current` — the last common point of the two
  branches (in practice, the last promote). This is a coherent shared config state because promote
  makes `current == staging`; both sides only diverge *after* it.
- **staging** = value at `staging` tip.
- **current** = value at `origin/current` tip.

A value may be **ABSENT** (the key does not exist at that ref). ABSENT is a first-class value in the
comparison, so add/delete/modify are all handled by one rule.

### 2.2 Per-key verdict

Let `b`, `s`, `c` be the base / staging / current values for one setting path.

| Condition | Meaning | Action |
|---|---|---|
| `s == c` | already agree (incl. both ABSENT) | no-op |
| `s == b` and `c != b` | **current-ahead** — edited on live only | **fold back** → take `c` |
| `c == b` and `s != b` | **staging-ahead** — deliberate staging change | **keep** → take `s` |
| `s != b` and `c != b` and `s != c` | **collision** — both changed, differently | **prompt operator** |

Because ABSENT participates, this single table covers every case:

- add on staging only (`b,c` ABSENT, `s` present) → **staging-ahead → keep** ← the footer keys
- add on current only (`b,s` ABSENT, `c` present) → current-ahead → fold
- add on both, same value → agree
- add on both, different values → collision
- delete on staging (`b,c` present equal, `s` ABSENT) → staging-ahead → keep the deletion
- delete on current (`b,s` present equal, `c` ABSENT) → current-ahead → fold the deletion
- modify one side only → ahead on that side
- modify both to different values, or delete-vs-modify → collision

**The operator is only ever asked about true collisions.** Staging-ahead and current-ahead resolve
automatically and correctly.

### 2.3 Value-based comparison → noise immunity

Comparisons are on **parsed values at JSON paths**, never on raw file text. Shopify re-serializes
the whole file on every theme-editor save (key reordering, whitespace, numeric reformatting). Under
a value comparison these produce **zero deltas** — the values are equal regardless of serialization.
This is what makes the prompt list contain only *real* changes and never phantom churn.

### 2.4 Arrays are atomic

A "setting" (leaf) is either a **scalar** or a **whole array**; objects are recursed into. Arrays
(e.g. a section group's `block_order`, or a template's `block_order`) are compared as one
canonicalized unit at their path, not element-by-element. A block reorder therefore surfaces as
**one** delta/collision to resolve, not a cascade of phantom per-element moves. This keeps
order-sensitive structures correct and legible.

---

## 3. Interactive reconciliation (collisions only)

When the dry-run merge finds one or more **collision** leaves, `dawn-backflow` stops and drives one
`AskUserQuestion` per collision (batched in one call where there are several). Each question shows:

- the file and JSON path (e.g. `sections/footer-group.json → footer.color_scheme`)
- **base**, **staging**, and **current** values side by side

Options per collision:

| Option | Result |
|---|---|
| **Keep staging** | staging's value wins (will promote to current) |
| **Take current** | current's value wins (folds the live edit into staging) |
| **Enter a value** | operator supplies a replacement value; it is set at that path and wins |

The **Enter a value** option is a follow-up open-text question (per the `AskUserQuestion` "Other"
affordance). The supplied text is parsed as JSON if it is valid JSON (so `true`, `36`, or a quoted
string round-trip to the right type); otherwise it is stored as a string. It is then materialised at
the collision path exactly like a staging-ahead value. All collisions are resolved before any file
is written; a partially-answered run writes nothing.

---

## 4. Where the merged result lands + durability

The merged result is written to the config files on `staging` and committed as the **single
config-snapshot commit at the tip** — same invariant as today (§4 of conventions): *N stable
enrichment commits + exactly one config-snapshot at the tip.* If the tip is already the snapshot,
amend it; otherwise (e.g. a Shopify bot commit landed on staging above the snapshot) re-establish
the snapshot at the tip as part of the reconcile.

### The snapshot stays regenerable — but from the merge, not from current

Today's model calls the snapshot "regenerable — its content is always whatever `current` is now."
This design **narrows that**: the snapshot is regenerable as the **deterministic output of the
3-way merge of `{base, staging, current}`**. Re-running the reconcile reproduces it exactly
(idempotent: feeding the merged snapshot back in as the staging input yields the same result,
because `base` is fixed until the next promote, so staging-ahead keys stay staging-ahead).

### Durability invariant (and the Case B hazard)

**Invariant:** every recreation of the config snapshot goes through the reconcile merge. Nothing may
recreate it by the old blind "checkout current" path, because that path cannot see staging-ahead
values and would silently drop them.

This directly affects **backflow routing Case B** (new L2 enrichment: `reset --hard HEAD~1` to drop
the snapshot, commit the enrichment, recreate the snapshot). The recreate step **must** be the
reconcile merge, not a current-mirror. As long as that holds, staging-ahead config survives Case B,
because the merge re-reads staging's value from history.

**Boundary condition:** a staging-authored config value must be present at `staging` tip when the
reconcile runs (it is, since the previous reconcile wrote it into the snapshot, and before that it
arrived via a staging preview-theme bot commit or an explicit commit). The only way to lose it is
to recreate the snapshot outside the reconcile — which the invariant forbids. The implementation
plan must audit every snapshot (re)creation site for compliance.

---

## 5. Guard fix: direction-aware pending check

`dawn::backflow_pending` (used by both `dawn-backflow`'s no-op short-circuit and `dawn-promote`'s
guard) is replaced by a **direction-aware** check:

- **OLD:** `staging` and `current` config files *differ at all* → pending.
- **NEW — `dawn::reconcile_pending`:** run the merge in **dry-run** and report pending **iff** there
  is at least one **current-ahead** leaf not yet folded into staging. States whose only differences
  are **staging-ahead** leaves or **collisions** are **not** pending. (Collisions are handled at
  backflow time, not the promote gate — see the field-test correction note in §7 for why counting
  them here would deadlock promote after a resolve-to-staging.)

Consequences:

- `dawn-promote` no longer false-positives when staging is merely ahead (today's footer case). It
  blocks only when the live theme has genuine edits staging hasn't absorbed, or an undecided
  collision remains.
- `dawn-backflow` short-circuits ("Nothing to backflow") only when there is truly nothing to fold
  and no collision — staging-ahead-only counts as nothing to do.

`dawn-promote` itself is otherwise unchanged: after a clean reconcile it still force-pushes
`staging → current` wholesale (staging = base + folded current edits + resolved collisions +
preserved staging-ahead), so the merged result reaches the live theme as one authoritative reset.

---

## 6. Scope

The reconcile parses and 3-way-merges two classes of file, distinguished by **which of their leaves
count as config**:

**A. Full-file config — every leaf reconciled.** The existing `config-paths.txt` set:
`config/settings_data.json`, `config/settings_schema.json`, `sections/header-group.json`,
`sections/footer-group.json`, and the default templates (`index`, `cart`, `collection`, `article`,
`blog`, `password`, `product`). Per convention §4 these files are admin-owned in full, so all leaves
are config.

**B. Suffix templates — only `settings` leaves reconciled.** Custom suffix templates
(`templates/<type>.<suffix>.json`, e.g. `page.withdrawal.json`, `product.soap.json`) are
**skeleton + `settings`**. The existing model already splits them: skeleton (section/block
add/remove/reorder, `type`, `disabled`, `name`, `block_order`) → **L2 structure, harvested**;
`settings` values → **content**. So the reconcile covers **only leaves whose JSON path passes
through a `settings` object** (section-level and block-level). This is the protection the "yes,
I edit suffix-template copy live" case needs: a live copy edit becomes a **current-ahead** settings
leaf and is folded in (or surfaces as a collision) instead of being **silently clobbered** by the
promote force-push. Skeleton leaves are **excluded** from the reconcile and continue to route to
`dawn-harvest` exactly as today.

Suffix-template detection: a `templates/*.json` whose basename still contains a dot after stripping
`.json` (e.g. `page.withdrawal` → suffix; `product` → default). Default templates are covered by
set A via their explicit `config-paths.txt` entries.

**Out of scope — non-config divergence routing is unchanged in kind, but made direction-aware.**
Non-config, non-suffix-template files continue through the existing `dawn-backflow` Exit-21 flow
(classify each as enrichment → L2 commit, generic → `dawn-harvest`, or churn → ignore). The one
consistency fix: that flow should flag only **current-ahead** non-config files — those actually
changed on the live theme relative to the merge-base and thus needing capture. A **staging-ahead**
non-config file is staging's own work (a harvested L1/L2 commit) and is carried to current by the
promote force-push; backflow has nothing to capture from it and must not false-halt on it (today it
does — the same directional blindness this design removes for config). A suffix template that differs
**only** in `settings` is now handled by the reconcile (no Exit-21); one whose **skeleton** differs
still routes to harvest for the structural part (mixed settings+skeleton drift: reconcile the
settings, harvest the skeleton — the existing `--l1-content` split in `dawn-harvest` already covers
this). This design does not touch `dawn-ship`, the L1/L2/Inert classification, or the promote
force-push mechanics.

---

## 7. Algorithm sketch

New lib functions in `dawn-ops.sh` (implementation detail for the plan; semantics fixed here):

```
dawn::config_class <file>
    # "full"   -> file is in config-paths.txt (set A): all leaves are config
    # "suffix" -> templates/<type>.<suffix>.json (set B): only settings leaves
    # ""       -> not a reconcile target (routes to the existing non-config flow)

dawn::config_leaves <ref> <file>
    # Emit a canonical leaf map for one config file at one ref:
    #   one line per leaf:  <json-path>\t<canonical-value>
    # Leaf = scalar OR whole array; objects recursed. Uses jq.
    # For class "suffix", restrict to leaves whose path passes through a
    #   `settings` object (section- or block-level); skeleton leaves omitted.
    # Missing file/key => leaf absent (no line).

dawn::reconcile_scan / dawn::reconcile_apply
    # base = git merge-base staging origin/current
    # Build leaf maps for base/staging/current via dawn::config_leaves.
    # For each leaf path in the union, classify per §2.2:
    #   agree | current-ahead | staging-ahead | collision
    # reconcile_scan: emit non-agreeing leaves (verdict/file/path/base/staging/current).
    # reconcile_apply <file> <decisions>: substrate = STAGING; apply ONLY folds; write file.

dawn::reconcile_pending
    # True iff any reconcile-target file has a current-ahead leaf.
    # Replaces dawn::backflow_pending everywhere.
```

The reconcile-target file set is `{full-config files from config-paths.txt} ∪ {suffix templates
that differ between refs}`, each processed under its `dawn::config_class`.

> **Materialisation — corrected during field testing (2026-07-03).** The first cut built the merged
> document from **current** and overlaid the staging side. That was wrong on two counts, both caught
> by field-testing the withdrawal-footer case: (a) for **suffix templates** the skeleton is
> staging-authoritative, so a current substrate risks clobbering staging's structure; and (b) it
> re-serialized *every* config-target file, spuriously rewriting untouched templates. The correct
> rule: **substrate = staging**, and apply **only the folds** that move staging toward the
> reconciled result — `current-ahead` → take current's value; a collision resolved to
> `current`/`value` → take that value (via `jq setpath`/`delpaths`). `staging-ahead` leaves and
> collisions resolved to `staging` need **no** op because staging already holds them. A file with no
> folds is emitted as **nothing**, so `dawn-backflow` leaves it byte-for-byte intact (zero churn).
> This preserves staging's skeleton for suffix templates for free, since suffix leaves are
> `settings`-only and the skeleton is never a fold target.

> **Pending — corrected during field testing (2026-07-03).** `reconcile_pending` counts
> **current-ahead leaves only**, not collisions. Statelessly, a collision *resolved to staging* is
> indistinguishable from an unresolved one (base absent / staging ≠ current), so counting collisions
> would block promote **forever** after you deliberately chose staging. Collisions are decided at
> **backflow** time instead (backflow stops with exit 21 until every collision has a decision); a
> resolved-to-staging collision is a deliberate staging-wins outcome that the promote force-push
> carries, with `--confirm-live` as the final human gate.

Per-file loop lives in `dawn-backflow`; the lib provides the mechanics.

---

## 8. Surface of change

| File | Change |
|---|---|
| `_dawn-ops-lib/dawn-ops.sh` | add `dawn::config_leaves`, `dawn::reconcile_file`, `dawn::reconcile_pending`; keep `dawn::backflow_pending` as a thin alias or remove after callers migrate |
| `dawn-backflow/backflow.sh` | replace the blind per-file `checkout current` with the reconcile loop over `{full-config ∪ differing suffix templates}`; drive collision prompts via the skill; keep Exit-21 routing for non-config files and for suffix-template *skeleton* drift |
| `dawn-backflow/SKILL.md` | document the reconcile behaviour, the collision `AskUserQuestion` step, and the new "staging-ahead survives" guarantee |
| `dawn-promote/promote.sh` | guard on `dawn::reconcile_pending` instead of `dawn::backflow_pending` |
| `dawn-harvest/SKILL.md` | no behaviour change; cross-reference only — a suffix template classified `config` now has its `settings` reconciled (not passively "left in the snapshot"); point the reader to this design |
| `_dawn-ops-lib/conventions.md` | §4: snapshot is regenerable *via reconcile*, not "= current"; add the direction-aware verdict table; Case B recreate = reconcile; note suffix-template `settings` are reconciled while skeleton stays harvested |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | update the backflow/promote steps and Case B choreography |
| `docs/superpowers/runbook/dawn-update-and-promote.md` | replace the "regenerable = whatever current is now" framing (line ~38) with "regenerable via reconcile"; update the Case-B `reset --hard HEAD~1` recreate steps (lines ~62–72) to recreate via reconcile; update the promote checklist's backflow-guard item (lines ~86, ~119) for the direction-aware guard |

No change to `config-paths.txt` contents (same file set).

### Documentation-consistency principle

**Living docs are updated; dated artifacts are not rewritten.**

- **Update to match the new behaviour:** `conventions.md`, both runbooks
  (`dawn-dev-and-release.md`, `dawn-update-and-promote.md`), and the affected skill `SKILL.md`
  files (`dawn-backflow`, cross-ref in `dawn-harvest`). These are the canonical, always-current
  references operators read.
- **Leave as point-in-time records:** dated specs, plans, and inventory files under
  `docs/superpowers/{specs,plans,inventory}/` (including this one after approval). They document
  decisions as of their date and are superseded by newer dated docs, not edited in place.
- **Verification:** the implementation plan ends with a consistency sweep — grep the living-doc set
  for the invalidated phrases (`current wins`, `whatever current`, `checkout .*current` in the
  backflow context, the old `backflow_pending` guard description) and confirm none remain in a
  canonical doc.

---

## 9. Edge cases

- **No merge-base** (unrelated histories): fail loud with a guard; do not fall back to blind
  overwrite. Should not happen given the branch model, but must not silently mis-resolve.
- **File present on one side only:** treated as all-leaves-absent on the missing side; per-leaf rule
  applies (a new config file authored on staging → all leaves staging-ahead → kept).
- **Bot commit above the snapshot on staging** (observed: `feb17332` sits above the config-snapshot
  commit): the reconcile normalises the tip back to a single snapshot; the deliberate values from
  the bot commit are read as staging-ahead and re-baked into the snapshot.
- **Invalid JSON at a ref:** abort with a clear error; never write a partial/merged file.
- **Type change at a path** (scalar ↔ object/array): treat as a collision (values differ), operator
  decides.
- **Array element-level intent** (operator wanted to keep some blocks from each side): not
  supported — arrays are atomic, so this is one collision. If finer control is ever needed, the
  operator edits the preview theme and re-runs. Documented limitation.
- **Suffix template with mixed drift** (both `settings` and skeleton changed): the reconcile handles
  the `settings` leaves; the skeleton part still routes to `dawn-harvest` (Exit-21). The two are
  independent — reconciling settings never rewrites skeleton, so there is no interference.
- **Operator-entered value fails to parse as JSON:** stored as a string (documented in §3); if the
  path expects a non-string, that is the operator's choice and is applied verbatim.

---

## 10. Testing

Follow the existing dawn-ops test seams (local refs, no network; cf. `DAWN_PROMOTE_REF`/`DAWN_PUSH`
in `promote.sh`). Fixture repo with `staging`/`current`/merge-base config files exercising:

1. **staging-ahead only** (the footer case) → no prompt, `reconcile_pending` false, promote allowed,
   staging value preserved.
2. **current-ahead only** → folded automatically, no prompt.
3. **collision** → one prompt; "Keep staging", "Take current", and an entered value each produce
   the right file.
4. **re-serialization noise** (same values, reordered/reformatted JSON) → zero deltas, no prompt.
5. **array reorder** → exactly one delta/collision, not many.
6. **add/delete matrix** → each row of §2.2's expanded list.
7. **idempotence** → running reconcile twice with no new edits is a no-op.
8. **Case B** (drop + recreate snapshot via reconcile) → staging-ahead config survives.
9. **suffix template, settings-only drift** → reconciled (current-ahead copy edit folded, not
   clobbered), no Exit-21; **skeleton drift** → routed to harvest, settings untouched.

---

## 11. Exit codes (unchanged contract)

| Code | When |
|---|---|
| `0` `DAWN_OK` | reconcile applied (or nothing to do); snapshot at tip |
| `10` `DAWN_GUARD` | dirty tree, wrong branch, no merge-base, invalid JSON |
| `21` `DAWN_STOP_JUDGMENT` | collisions need operator decisions (backflow), or non-config files need classification (existing Exit-21 flow) |

`dawn-promote` keeps its `20` `DAWN_STOP_LIVE` confirm-live gate.

---

## 12. Out of scope / YAGNI / future

- Suffix-template **skeleton** reconciliation — out of scope by design; skeleton is
  staging-authoritative L2 structure, harvested/shipped, not reconciled (§6). Only their `settings`
  are reconciled.
- Element-level array merging — deferred; arrays are atomic.
- Any change to harvest, ship, or L1/L2/Inert classification — untouched.
