# Dawn theme-ops — operating conventions

Single source of truth for all five skills (`dawn-backflow`, `dawn-promote`, `dawn-upgrade`,
`dawn-harvest`, `dawn-ship`). Full depth: runbook at
`docs/superpowers/runbook/dawn-dev-and-release.md`, layer design at
`docs/superpowers/specs/2026-06-17-dawn-repo-layer-separation-design.md`, skills design at
`docs/superpowers/specs/2026-06-18-dawn-theme-ops-skills-design.md`,
inert-shipping design at `docs/superpowers/specs/2026-06-28-dawn-ops-inert-shipping-design.md`.

---

## 1. Branch model

```
dawn-vanilla        pristine Dawn @ a fixed upstream commit/tag — ff-only, never rebased
  └─ customizations   + L1 generic features and L2 store-specific enrichments — both as discrete classified commits; rebases onto new Dawn
       └─ staging     + L2 enrichments (discrete commits) + ONE config snapshot at tip
            ⇄ current   the LIVE theme — Shopify writes admin/editor commits here
```

- `dawn-vanilla` → fast-forward only (never commit, never rebase).
- `customizations` → L1 generic changes **and** L2 store-specific enrichments, each as a discrete classified commit (prefix `L1:` / `L2:`, `Inert:` trailer); rebased onto `dawn-vanilla` on Dawn upgrades.
- `staging` → L2 enrichments + exactly one config-snapshot commit **always at the tip**; linked to
  the non-live preview theme in the Shopify admin.
- `current` → the live storefront; **see the hard rule below**.

---

## 2. The hard rule — never touch `current` by hand

- **Never** commit, push, reset, or check out `current` locally.
- `current` changes only via: (a) Shopify's own auto-commits ("Update from Shopify…"), or (b) the
  sanctioned force-push performed by `dawn-promote` after explicit human confirmation.
- `dawn-ops.sh::assert_not_current` enforces this in every script.

---

## 2a. Bot-linked branches are append-only

`staging` and `current` are linked to real Shopify themes. The Shopify GitHub integration writes "Update from Shopify…" commits to them directly. Because of this:

- **Never force-push `staging` or `current`** except the one deliberate guarded reset performed by `dawn-promote`.
- **All history surgery** (rebase, split, reword) happens on `customizations`, which is not linked to any theme and is always bot-free.
- Force-pushing a bot-linked branch while the bot has committed to it produces repeated churn (conflicting history) that re-triggers on every editor save.

---

## 3. Two operating modes

| Mode | Branch | Purpose |
|---|---|---|
| **Develop / experiment** | `staging` (or a scratch branch off it) | Build features; linked to the preview theme for live testing. Generic results get lifted to `customizations` via `dawn-harvest`. |
| **Operate** | `ops` | Check out `ops`, launch the agent from there, run a skill. Skills and docs live on `ops`. |

`ops` is never deployed (Shopify ignores `.claude/` and `docs/`; theme branches stay pure).

---

## 3a. Two promote modes

| Mode | Skill | What it does | When to use |
|---|---|---|---|
| **Ship** (incremental) | `dawn-ship` | Cherry-picks a classified commit from `customizations` onto `current`. Append-only. Classifier gates: ALL_INERT → light confirm; HAS_ACTIVE → full confirm + smoke test; NEEDS_JUDGMENT → stop. | Ship dormant building blocks early (to unblock shop-global activation like a page binding), or ship tested-active changes incrementally. |
| **Promote** (release) | `dawn-promote` | Force-pushes `staging` onto `current` (the authoritative reset). Yields `current == staging`. Guarded: staging must be clean. | Full release after rebuild, backflow, and testing. |

The two modes are complementary: `dawn-ship` ships pieces incrementally between releases; `dawn-promote` resets `current` to the authoritative tested `staging` at each release, reconciling any divergence.

---

## 3b. Single working tree — no git worktrees

All branch switches, including scratch/feature branches for development, happen as **ephemeral
`git checkout`s in this one working tree** — never as a separate `git worktree add`. `dawn-ops.sh`
formalizes this via `dawn::with_branch`: it checks out the target branch and traps the shell's
`EXIT` to check the original branch back out, whether the script succeeds or fails.

**Why this matters, not just style:** `.claude/` and `docs/` live only on `ops` (§ above). A linked
worktree for a feature branch is a second directory that never has `.claude/` — any skill or
agent that assumes "the repo" means one working directory (all five `dawn-*` skills do) will
silently operate on the wrong tree, or an agent will default back to the main checkout for
commands it forgets to scope, leaving the main tree's `HEAD` on the wrong branch. There's no
isolation benefit here either: `current` and `staging` are guarded against destructive operations
by `dawn::assert_not_current` / `assert_clean_tree`, not by directory separation.

If you need an isolated sandbox for something orthogonal to Dawn's branch model (e.g. a spike you
want to `rm -rf` without touching real branches), that's fine — just don't reach for a worktree as
the mechanism for normal `ops → staging/customizations → ops` development.

---

## 3c. Invoke `dawn-ops.sh` via explicit `bash`, never a bare `source`

`dawn-ops.sh` has a `#!/usr/bin/env bash` shebang, but a shebang only applies when a file is
*executed*; `source`ing it runs the script under whatever shell is already running. On this
machine the operator's default shell is zsh, not bash, and native zsh has two independent problems
with this library:

- **Nounset on `BASH_SOURCE`** — `dawn-ops.sh` resolves its own directory via `${BASH_SOURCE[0]}`,
  which doesn't exist in zsh; under `set -u` this used to throw a "parameter not set" error on
  every source. Fixed in the library itself (portable bash/zsh self-path resolution), but the next
  point is not fixable inside the library.
- **Intermittent `command not found: git` under process substitution** — reproducible independent
  of `dawn-ops.sh` (a bare `while read; do :; done < <(git diff ...)` loop fails ~1 in 3 tries in
  native zsh here). Root cause: `~/.zshrc` sources `nvm.sh` via a `$(brew --prefix nvm)` shell-out,
  which races with zsh's command-hash table when a forked subshell (like a process substitution)
  looks up `git`. This is silent and non-deterministic — it has produced a **wrong classification
  verdict** (`inert` instead of `needs_judgment`) with no error surfaced to the caller.

`bash` does not exhibit either problem. Every invocation of `dawn-ops.sh` functions — from a skill
doc, from an agent, from a terminal — must go through an explicit bash subprocess:

```bash
bash --noprofile --norc -c '
source .claude/skills/_dawn-ops-lib/dawn-ops.sh
dawn::some_function args...
'
```

Never write a bare `source .claude/skills/_dawn-ops-lib/dawn-ops.sh` intended to run in the calling
shell — there is no guarantee that shell is bash. (The `bash .../foo.sh args` entry points like
`harvest-commit.sh`, `promote.sh`, `ship.sh`, `upgrade.sh`, `backflow.sh` are already safe: an
explicit `bash` prefix runs them under real bash regardless of the ambient shell.)

---

## 4. Config-snapshot invariant

**`staging` always ends in exactly ONE config-snapshot commit at the tip.** That commit is
*regenerable* — its content is the deterministic output of the **3-way config reconcile** of
`{base = git merge-base staging origin/current, staging, current}` (see
`docs/superpowers/specs/2026-07-02-dawn-config-3way-reconcile-design.md`). You can drop and recreate
it freely **by re-running the reconcile** (never by a blind "checkout current", which would lose
values authored on staging). `current` is the source of truth for values edited live; `staging` is
the source of truth for values you deliberately changed there.

**How the single commit is maintained:** `dawn-backflow` `reset --soft`s `staging` to its collapse
floor — the first non-config (enrichment/code) commit from the tip, else the `customizations`
merge-base — and re-commits the reconciled config as one snapshot. This **collapses** the loose
"Update from Shopify…" bot commits and any previous snapshot into that single commit each run;
enrichment/code commits are the floor and are never squashed in. Because this rewrites `staging`'s
local history, the eventual `git push origin staging` in `dawn-promote` **must** be a
`--force-with-lease` (the sanctioned reset of §2a); the pushed **tree** is unchanged, so the preview
theme content does not move — only the commit history collapses.

**Canonical config file set** (defined in `.claude/skills/_dawn-ops-lib/config-paths.txt`):

```
config/settings_data.json   config/settings_schema.json
sections/header-group.json  sections/footer-group.json
templates/index.json        templates/cart.json
templates/collection.json   templates/article.json
templates/blog.json         templates/password.json
templates/product.json
```

These are Dawn's default templates plus theme settings and section-group JSONs. They are **content
files**: they hold what the site currently says, shows, and how it's arranged — text, colours,
section order, image choices. Content changes independently of structure (you can rewrite copy
without touching a template) and has no reuse value. The live version in `current` is always the
source of truth; we regenerate them on backflow, never harvest them.

### Backflow routing

| Change type | Action |
|---|---|
| Config/settings divergence (either direction) | **Reconcile:** `dawn-backflow` runs the 3-way merge — staging-ahead kept, current-ahead folded, collisions prompted; amends the snapshot |
| New L2 enrichment (store-specific) | **Case B:** `reset --hard HEAD~1` (drop the regenerable snapshot), commit the enrichment, **recreate the snapshot by re-running the reconcile** |
| Generic code change (L1 candidate) | Route to `dawn-harvest`; rebase keeps the snapshot at the tip automatically |
| Locale / cosmetic churn | Ignore — Shopify re-serialization noise (the reconcile is value-based and ignores it automatically) |

**Invariant after either case:** N stable enrichment commits + exactly one config-snapshot at the tip.

---

## 5. Classification: Config / L2 / L1

Every harvestable change falls into one of three buckets. The classifier provides hints; the
operator makes the final call via `dawn-harvest`.

### The core question: structure or content?

**Structure** = something that defines how the site works or is organised — a new template, a new
section, a behaviour change, an integration. Structure has reuse value: a template applied to one
page can be applied to ten; a section added once appears wherever it's referenced.

**Content** = what the site currently says and shows — text, colours, typography, section order on
a live page, image choices. Content has no reuse value; it *is* the site at a point in time.
Content belongs in the config snapshot and is never harvested.

### The three buckets

**Config (content only):** the change is purely content — text values, colour tokens, section
ordering on a default template, theme settings. No structure was added or changed. Lives in the
config-snapshot commit on `staging`; regenerated from `current` on backflow. Never harvested.
*Signals:* `settings_data.json`, `settings_schema.json`, header/footer group JSONs, default
template JSONs where only section order or settings values changed (no new section types added).

**L2 (store-shaped structure):** a structural addition or change shaped for this store — a new
suffix template, a layout file modified for store-specific integrations, a section wired to
store-specific metafields or app IDs. The structure has reuse value within this store (a template
applies to many resources, a section appears on many pages) but cannot be dropped onto a different
store unchanged. Lives in `customizations` as `L2:` commits.
*Signals:* store domain/brand, app instance UUIDs, store-specific metafield handles (`custom.*`),
GTM/analytics IDs, hardcoded Dutch/market-specific copy that is part of the structure itself.

**L1 (generic structure):** a structural addition that passes the stranger test — a developer at
any Shopify store could drop this file in unchanged and it would work. No store-specific data
anywhere in the file. Lives in `customizations` as `L1:` commits.
*Signals:* generic app block integration (type only, no instance IDs), layout/styling changes with
no store data, new utility sections or snippets with no store-specific references.

### Direction-aware config reconcile (verdict per setting)

For config-path files (all leaves) and suffix templates (`settings` leaves only), `dawn-backflow`
compares each setting at `base` / `staging` / `current`:

| base vs staging vs current | Meaning | Action |
|---|---|---|
| staging changed, current didn't | deliberate staging change | keep staging (promotes) |
| current changed, staging didn't | live editor change | fold into staging |
| both changed, same value | agree | no-op |
| both changed, different values | collision | prompt operator |

Suffix-template **skeleton** changes are excluded from the reconcile and continue to route to
`dawn-harvest` as L2 structure.

### Rules

- **When in doubt → L2.** Incorrectly lifting L2 into L1 poisons `customizations` for future Dawn
  upgrades. L2 is always safe.
- **Structure in a config file → still config.** If a default template was modified only via the
  theme editor (section reordering, settings changes), treat it as config even if the diff looks
  structural. The template itself is admin-owned. Any genuinely new section code lives in the
  section file, which is harvestable separately.
- **A template JSON = skeleton (structure) + `settings` (content) — this splits custom templates
  too.** A template's structure is everything *outside* the `settings` objects; its content is the
  values *inside* them (section- **and** block-level, since `blocks` is a sibling of `settings`).
  So an already-harvested custom suffix template (e.g. `page.withdrawal.json`) that shows up as a
  candidate is decided mechanically: run `dawn::classify_template_json <templates/….json>`.
  - `config` — only in-`settings` values differ (heading/intro/copy, colours, paddings, block
    setting values). Theme-editor content mirrored from live; leave it in the config snapshot,
    do not re-harvest.
  - `l2` — the skeleton differs (section add/remove/reorder, `type`, `disabled`, `name`, or block
    add/remove/reorder/`type`), or the template is new/removed. Harvest the structural change as L2.
  A structural template change is never L1. Keep the store's `settings` values out of the L2 commit
  (reset them to the `customizations` baseline) so they stay config — see the `--l1-content` split
  in the `dawn-harvest` skill.
- **The operator decides.** `dawn::harvest_candidates` provides L1/L2 hints via keyword scan.
  `dawn-harvest` surfaces those hints with reasoning. The operator confirms, overrides, or marks
  a candidate as Config (content only) via `AskUserQuestion`.

Both L1 and L2 commits live in `customizations`, distinguished by commit message prefix
(`L1:` / `L2:`) and the `Inert:` trailer.

---

## 5a. Inert vs active (render-graph reachability)

A change is **inert** if publishing it does not alter the rendered output of any URL a visitor can currently reach.

**Always-reachable roots:** `layout/*.liquid`, `sections/header-group.json`, `sections/footer-group.json`, `config/settings_data.json`, `config/settings_schema.json`, and the **default templates** (`templates/index.json`, `templates/cart.json`, `templates/product.json`, `templates/collection.json`, `templates/article.json`, `templates/blog.json`, `templates/password.json`, `templates/search.json`, `templates/404.json`, `templates/page.json`), plus sections listed in those templates.

**Inert examples:** a new section / snippet / asset not referenced by any reachable file; additive-only new locale keys; a new suffix template (`page.foo.json`) with no resource bound to it.

**Active examples:** any edit to a file in the always-reachable set; a changed locale value; wiring a new section into a reachable template.

**NEEDS_JUDGMENT:** new suffix templates (`page.*.json`, `product.*.json`). Whether a resource is bound is shop-global admin state, not in git. The operator must confirm "no page/product is assigned this template" before shipping.

**Conservative default:** anything not provably inert is flagged active. The classifier (`dawn::classify_changes`) never silently calls something inert.

---

## 6. Exit-code contract

Every script in this lib uses the following exit codes. Skills **must stop and consult the user**
on codes `20` and `21`.

| Code | Constant | Meaning |
|---|---|---|
| `0` | `DAWN_OK` | Success — operation complete. |
| `10` | `DAWN_GUARD` | Guard failure — precondition not met (dirty tree, wrong branch, etc.). Fix the condition and retry. |
| `20` | `DAWN_STOP_LIVE` | **STOP — awaiting `--confirm-live`.** A live/irreversible step is next. Skill must surface this to the user and wait for explicit approval before proceeding. |
| `21` | `DAWN_STOP_JUDGMENT` | **STOP — needs human judgment.** A decision (e.g. layer classification, conflict resolution) cannot be made mechanically. Skill must present the question to the user. |
| `30` | `DAWN_VERIFY` | Verification failure — a post-op tree check failed. Inspect the diff output, correct the state manually, and re-run verification. |
