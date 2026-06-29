# Dawn theme-ops — operating conventions

Single source of truth for all four skills (`dawn-backflow`, `dawn-promote`, `dawn-upgrade`,
`dawn-harvest`). Full depth: runbook at `docs/superpowers/runbook/dawn-update-and-promote.md`,
layer design at `docs/superpowers/specs/2026-06-17-dawn-repo-layer-separation-design.md`,
skills design at `docs/superpowers/specs/2026-06-18-dawn-theme-ops-skills-design.md`.

---

## 1. Branch model

```
dawn-vanilla        pristine Dawn @ a fixed upstream commit/tag — ff-only, never rebased
  └─ customizations   + L1 generic features — upstream-shaped, rebases onto new Dawn
       └─ staging     + L2 enrichments (discrete commits) + ONE config snapshot at tip
            ⇄ current   the LIVE theme — Shopify writes admin/editor commits here
```

- `dawn-vanilla` → fast-forward only (never commit, never rebase).
- `customizations` → L1 generic changes only; rebased onto `dawn-vanilla` on Dawn upgrades.
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

## 4. Config-snapshot invariant

**`staging` always ends in exactly ONE config-snapshot commit at the tip.** That commit is
*regenerable* — its content is always "whatever `current`'s config files are right now." You can
drop and recreate it freely; the real source of truth is `current`.

**Canonical config file set** (defined in `.claude/skills/_dawn-ops-lib/config-paths.txt`):

```
config/settings_data.json   config/settings_schema.json
sections/header-group.json  sections/footer-group.json
templates/index.json        templates/cart.json
templates/collection.json   templates/article.json
templates/blog.json         templates/password.json
templates/product.json
```

### Backflow routing

| Change type | Action |
|---|---|
| Config/settings churn only | **Case A:** checkout config files from `origin/current`, `--amend` the tip commit — one config commit, forever |
| New L2 enrichment (store-specific) | **Case B:** `reset --hard HEAD~1` (drop the regenerable config commit), commit the enrichment, recreate the config snapshot at the new tip |
| Generic code change (L1 candidate) | Route to `dawn-harvest` (§4 of runbook); rebase keeps config at the tip automatically |
| Locale / cosmetic churn | Ignore — Shopify re-serialization noise |

**Invariant after either case:** N stable enrichment commits + exactly one config-snapshot at the tip.

---

## 5. L1 vs L2 classification

**L1 (generic):** a stranger could drop this change onto a vanilla Dawn fork unchanged — no
store-specific products, metafields, app-instance UUIDs, branding, or copy.

**L2 (enrichment):** anything store-specific — templates tied to custom metafields, app integrations
with instance IDs, branding, copy, product-type logic.

**When in doubt → L2.** It is always safe to keep something in L2; incorrectly lifting L2 into L1
poisons `customizations` for future Dawn upgrades.

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
