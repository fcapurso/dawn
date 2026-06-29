# Dawn Development and Release Workflow

Single reference for operating the Zogezeept theme repo. Read this before running any skill.

---

## Branch roles

```
dawn-vanilla      L0 — pristine Dawn @ fixed upstream commit; ff-only, never commit here
  └─ customizations  L1 + L2 discrete classified commits — bot-free, rewritable (rebase, split OK)
       └─ staging    config snapshot at tip — bot-linked preview theme (append-only)
            ⇄ current  LIVE shop — bot-linked (append-only except guarded reset)
```

`customizations` is **never linked to a Shopify theme**. The Shopify GitHub bot never writes to it.
`staging` and `current` **are linked** to real themes. Treat them as append-only; never force-push them except the deliberate guarded reset (`dawn-promote`).

---

## Skill reference

| Skill | What it does | When to use |
|---|---|---|
| `dawn-harvest` | Analyses staging vs customizations, groups files into proposed commits, classifies each as L1 (generic structure), L2 (store-shaped structure), or Config (content only — leave in snapshot), confirms interactively, then commits approved groups into `customizations` | After finishing features on staging |
| `dawn-ship` | Lists shippable commits from `customizations` interactively, or ships a named commit directly — append-only cherry-pick onto `current` | To push an inert building block to the live theme early, or to ship a tested active change incrementally |
| `dawn-backflow` | Mirrors live admin/editor changes from `current` back into `staging` | Before a promote, or when the admin UI has config you need in staging |
| `dawn-promote` | Force-pushes `staging` → `current` (the authoritative reset; guarded) | Full release after rebuild, backflow, and testing |
| `dawn-upgrade` | Fast-forwards `dawn-vanilla` to a new Dawn release, then rebases `customizations` and `staging` | When a new Dawn version is available |

---

## Standard workflow

### 1. Develop

Work on a scratch branch off `staging` (or directly on `staging`). The `staging` branch is linked to the preview theme — changes you push appear in the Shopify theme preview.

```bash
git checkout staging
# ... make changes, test on preview theme ...
git commit -am "feat: add withdrawal form section"
```

### 2. Harvest pieces to `customizations`

`dawn-harvest` analyses all differences between `staging` and `customizations`, groups related
files (section + locale strings + assets) into proposed commits, and prompts you to classify each
as L1 (generic) or L2 (store-specific) before committing.

Run it from `ops` with a clean working tree:

```bash
# Just invoke the skill — the agent drives the rest interactively.
dawn-harvest
```

- The agent runs `dawn::harvest_candidates` to classify candidates, then proposes groupings.
- For each group you choose one of: **Approve** (L1 or L2 as proposed) / **Change to L1** /
  **Change to L2** / **Config (content only)** / **Skip** / **Edit message**.
- **Config (content only)** means the change is pure content (text, colours, section order) with no
  reuse value — leave it in the config snapshot, do not harvest. See §5 of `conventions.md` for
  the structure-vs-content distinction.
- L1 and L2 commits land in `customizations` with an `Inert:` trailer where applicable.
  **Exception:** purely additive L1 commits (new section/asset/snippet/locale files, nothing modified)
  do not need an `Inert:` trailer — the classifier recognises them as inert by structure (a new file
  can't be rendered until something references it). `dawn-ship` will still classify and surface them
  correctly in the interactive list.
- L2 commits produce expected rebase conflicts during `dawn-upgrade` — each one requires manual review.
- Files that mix generic and store-specific hunks are flagged for manual separation before harvest.

### 3. Ship inert pieces early (optional)

If you need a dormant building block on the **live theme** before the full release (e.g. to unblock a page→template binding in the Shopify admin):

```bash
# Interactive: lists inert + needs_judgment commits not yet on current; pick one
dawn-ship

# Direct: ship a specific commit by SHA (skips the list)
dawn-ship <commit-sha>
```

The interactive list shows two groups:
- **`[inert]`** — safe to ship after reviewing the diff
- **`[needs judgment]`** — suffix templates or similar; requires verifying in the Shopify admin that no resource is bound before confirming

In both cases the agent shows the full diff and classifier report, then stops for your explicit confirmation before touching `current`. This is **append-only** — no force-push, no config files.

### 4. Activate shop-global state in admin

Once inert building blocks are live on `current` (e.g. a new `page.herroeping.json` template), you can bind them in the Shopify admin:

- **Pages → Edit page → Template**: assign `page.herroeping` to the `/herroeping` page.
- Test the bound URL on **both** the preview theme (which now has the template too) and the live theme.

### 5. Release

When the feature is complete and tested:

```bash
# a) Capture any live admin edits back into staging
bash .claude/skills/dawn-backflow/backflow.sh

# b) Verify staging is clean (all harvested, config snapshot at tip)
# dawn-promote will check this automatically; if it fails, rebase staging onto customizations
# and recreate the config snapshot.

# c) Promote
bash .claude/skills/dawn-promote/promote.sh
# Agent will stop at the live-confirm gate and show you the full diff.
# After reviewing, confirm with --confirm-live.
bash .claude/skills/dawn-promote/promote.sh --confirm-live
```

After promote, `current == staging` exactly. Any interim `dawn-ship` cherry-picks are superseded.

---

## Decision tree

```
Want to push a dormant piece to the live theme now?
  → dawn-ship (inert commit from customizations)

Want to publish a full tested release?
  → dawn-backflow → dawn-promote (promote guards staging cleanliness automatically)

Captured live admin edits that aren't in staging yet?
  → dawn-backflow

Upgrading to a new Dawn version?
  → dawn-upgrade

Need to classify and harvest changes from staging into customizations?
  → dawn-harvest (produces L1, L2, or Config commits — agent guides classification)
```

---

## Rules (never break these)

1. **Never force-push `staging` or `current`** except the guarded reset in `dawn-promote`.
2. **All history surgery** (rebase, split, reword) on `customizations` only.
3. **Classify before shipping.** `dawn-ship` does this automatically; `dawn-harvest` records the trailer.
4. **`staging` tip = config snapshot.** Always ends in exactly one config-snapshot commit.
5. **Never commit to `current` locally.** `current` is the live shop — see `assert_not_current`.
6. **The mandatory pre-ship review is non-negotiable.** `dawn-ship` shows the exact diff and classifier report before anything is appended to `current`. The operator must confirm; the agent must never pass `--confirm-live` autonomously.
