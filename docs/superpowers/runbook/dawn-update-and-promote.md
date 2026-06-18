# Dawn theme — operating runbook

How to run the layered fork day-to-day. Read `docs/superpowers/specs/2026-06-17-dawn-repo-layer-separation-design.md`
for the *why*; this file is the *how*.

## Branch model (recap)

```
dawn-vanilla   pristine Dawn @ an upstream commit/tag (currently d2612f03). Only ever fast-forwarded.
  └─ customizations   + L1 generic features (rebases onto each new Dawn). Upstream-shaped.
       └─ staging     + L2 (enrichments as discrete commits + one config snapshot). Linked to a NON-LIVE preview theme.
            ⇄ current  the LIVE theme. Shopify GitHub integration writes admin edits here.
```

**THE ONE HARD RULE: never commit, reset, or force-push to `current` by hand.** It is the live shop.
`current` only ever changes via (a) Shopify's own "Update from Shopify" auto-commits, or (b) a
deliberate **promote** (below). Every manual git operation happens on the other branches.

Useful tags: `pre-cleanup-backup` (original live state), `staging-byte-for-byte-proof` (the commit
where staging == current exactly — restore source if cosmetic locale content is ever needed).

---

## 1. Backflow — capture live admin/config edits into the layers

**When:** you (or the store) changed something via the Shopify admin/theme-editor on the live theme.
Shopify auto-commits those to `current` as "Update from Shopify…". Pull them into the layers so
`staging` stays the source of truth. **Always do this before a promote.**

```bash
git fetch origin current
git log --oneline staging..origin/current        # inspect what the bot/admin changed
```
For each changed file, route it to the right layer:
- **config** (`settings_data.json`, `*-group.json`, stock `templates/*.json`) → fold into `staging`'s
  config-snapshot commit (amend or new "config snapshot" commit on `staging`).
- **a brand-new template/page/integration** → its **own** L2 enrichment commit on `staging`
  (document prereqs in the message — see `manifest-L2-features.md`).
- **a generic code change** you'd want on bare Dawn → **harvest to `customizations`** (section 4).
- **locale/cosmetic churn** → ignore; it's Shopify re-serialization (see `drops.md`).

Practical recipe (config edits, the common case):
```bash
git checkout staging
for f in <changed-config-files>; do git checkout origin/current -- "$f"; done
git add -A && git commit -m "config snapshot: <what changed in admin>"
```

---

## 2. Promote — publish `staging` to the live theme

**Pre-flight (all must be true):**
- [ ] Backflow done (section 1) — no un-captured admin edits remain on `current`.
- [ ] `staging` tested on the preview theme.
- [ ] You accept the first-promote consequence (locale reformat + 6 unused regional locales removed —
      see `drops.md`; harmless for NL/EN).

**Promote = make `current` match `staging`, then let Shopify publish.** Because `staging` has
rewritten history, this is a force-update of `current`. Do it via the remote so the GitHub
integration picks it up:
```bash
git push origin staging                              # ensure origin/staging is current
git push --force-with-lease origin staging:current   # set origin/current to staging's tree
```
Shopify then deploys `current` to the live theme automatically. Verify the live theme, then:
```bash
git fetch origin current
git checkout current && git reset --hard origin/current   # keep local current in sync (read-only mirror)
git checkout staging
```
> `--force-with-lease` (not `--force`) so the push fails safely if `origin/current` advanced
> (i.e. an un-backflowed admin edit) — which would mean you skipped section 1.

**Rollback:** `git push --force-with-lease origin pre-cleanup-backup:current` restores the original
pre-cleanup live state; or push any earlier known-good `staging` SHA.

---

## 3. Dawn version upgrade (e.g. → v15.4.1)

```bash
git fetch upstream --tags
# 1. advance the vanilla base
git checkout dawn-vanilla && git merge --ff-only v15.4.1     # ff only; dawn-vanilla stays pristine
# 2. replay L1 onto the new Dawn (resolve conflicts once, in clean generic space)
git checkout customizations && git rebase dawn-vanilla
#    - re-apply L1-feature locale keys if upstream restructured locales (see manifest-L1-locale.md)
# 3. rebuild staging on the new customizations
git checkout staging && git rebase customizations
#    - the config snapshot + enrichment commits replay; resolve any template/schema conflicts
# 4. test on the preview theme, then backflow + promote (sections 1–2)
```
At upgrade time the new Dawn's locales supersede ours — keep upstream's, then re-add only the
L1-feature keys. The 6 regional locales return automatically if the new Dawn ships them.

---

## 4. Harvest — move a bundled change to its proper layer

A generic improvement you made (or that landed via admin) should live in `customizations`, not
drown in config. To lift file `X`:
```bash
git checkout customizations
git checkout staging -- X        # or: git checkout origin/current -- X
# trim to only the generic hunks if X also has store-specific parts (git checkout -p)
git add X && git commit -m "L1: <feature>"
git checkout staging && git rebase customizations   # bring the harvested change down into staging
```
New discrete enrichment (template/page/integration)? Same idea, but commit it on `staging` as its
own "L2 enrichment: …" commit with prereqs, rather than on `customizations`.

---

## 5. Link a branch to a preview theme (one-time, for testing)

Shopify admin → Online Store → Themes → **Add theme → Connect from GitHub** → choose the repo and
the **`staging`** branch. It installs as an **unpublished** theme. Preview it; never "Publish" it
(publishing is what `promote` does via git). Re-pushing `staging` updates the preview theme.

---

## Quick reference

| Goal | Command summary |
|---|---|
| Capture live edits | `git fetch origin current` → route files into `staging` (§1) |
| Go live | backflow → `git push --force-with-lease origin staging:current` (§2) |
| New Dawn version | ff `dawn-vanilla` → rebase `customizations` → rebase `staging` → test → promote (§3) |
| Promote rollback | `git push --force-with-lease origin pre-cleanup-backup:current` |
| Never | hand-edit / commit / push to `current` |
