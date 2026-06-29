# Dawn Development and Release Workflow

Single reference for operating the Zogezeept theme repo. Read this before running any skill.

---

## Branch roles

```
dawn-vanilla      L0 — pristine Dawn @ fixed upstream commit; ff-only, never commit here
  └─ customizations  L1+L2 code — bot-free, rewritable (rebase, split OK)
       └─ staging    L2 + config snapshot at tip — bot-linked preview theme (append-only)
            ⇄ current  LIVE shop — bot-linked (append-only except guarded reset)
```

`customizations` is **never linked to a Shopify theme**. The Shopify GitHub bot never writes to it.
`staging` and `current` **are linked** to real themes. Treat them as append-only; never force-push them except the deliberate guarded reset (`dawn-promote`).

---

## Skill reference

| Skill | What it does | When to use |
|---|---|---|
| `dawn-harvest` | Analyses staging vs customizations, groups files into proposed L1/L2 commits, confirms interactively, then commits each group atomically into `customizations` and rebases `staging` | After finishing features on staging |
| `dawn-ship` | Cherry-picks a classified commit from `customizations` onto `current` (append-only) | To push a dormant piece to the live theme early, or to ship a tested active change incrementally |
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
- You confirm (or adjust) each proposed commit via `AskUserQuestion` before anything is written.
- Both L1 and L2 commits land in `customizations` with an `Inert:` trailer. L2 commits produce
  expected rebase conflicts during `dawn-upgrade` — each one requires manual review.
- Files that mix generic and store-specific hunks are flagged for manual separation before harvest.

### 3. Ship inert pieces early (optional)

If you need a dormant building block on the **live theme** before the full release (e.g. to unblock a page→template binding in the Shopify admin), ship it directly:

```bash
# Check which commits are on customizations
git log --oneline customizations ^staging

# Ship a specific commit (agent will show diff + classifier report, then ask for confirmation)
bash .claude/skills/dawn-ship/ship.sh <commit-sha>
```

This is **append-only** — no force-push, no config files. The Shopify bot's config churn on `current` is unaffected.

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
  → dawn-backflow → rebuild staging → dawn-promote

Captured live admin edits that aren't in staging yet?
  → dawn-backflow

Upgrading to a new Dawn version?
  → dawn-upgrade

Need to lift a generic feature from staging into L1?
  → dawn-harvest
```

---

## Rules (never break these)

1. **Never force-push `staging` or `current`** except the guarded reset in `dawn-promote`.
2. **All history surgery** (rebase, split, reword) on `customizations` only.
3. **Classify before shipping.** `dawn-ship` does this automatically; `dawn-harvest` records the trailer.
4. **`staging` tip = config snapshot.** Always ends in exactly one config-snapshot commit.
5. **Never commit to `current` locally.** `current` is the live shop — see `assert_not_current`.
6. **The mandatory pre-ship review is non-negotiable.** `dawn-ship` shows the exact diff and classifier report before anything is appended to `current`. The operator must confirm; the agent must never pass `--confirm-live` autonomously.
