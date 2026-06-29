---
name: dawn-upgrade
description: Upgrade to a new Dawn version — fast-forward dawn-vanilla then rebase customizations and staging. Use when the user says upgrade Dawn, bump Dawn version, or move to a new Dawn release.
---

## Agent operating context

Operate from the `ops` branch (never `current`). See `../_dawn-ops-lib/conventions.md` for branch conventions and exit-code contract.

## Usage

The script folds in its own prerequisites — it fetches upstream tags and checks the working tree
itself. You do **not** need to `git fetch` or pass a tag manually.

**Recommended — let it offer the choices:**
```bash
bash .claude/skills/dawn-upgrade/upgrade.sh
```
With no tag, it fetches upstream tags, lists the releases **newer than `dawn-vanilla`**, and STOPs
(exit 21). **Show the user that list and ask which release to bump to**, then re-run with their pick.

**Direct (when the user already named a release):**
```bash
bash .claude/skills/dawn-upgrade/upgrade.sh v15.4.1
```

Either way the script then:
1. Fast-forwards `dawn-vanilla` to the tag (must be a descendant — no force-push).
2. Rebases `customizations` onto `dawn-vanilla`.
3. Rebases `staging` onto `customizations`.

## Exit codes

| Code | Meaning | What to do |
|------|---------|-----------|
| 0 | Success (or "already at latest — nothing to upgrade") | Read the message. If upgraded: test on the preview theme, then run `dawn-promote`. |
| 10 | Guard triggered | Report the guard message: unknown tag, tag not ahead of `dawn-vanilla`, or dirty working tree. |
| 21 | STOP — judgment required | Either **release selection** (no tag given → show the printed candidate list and ask the user which to pick, then re-run with that tag), or a **rebase conflict** (see below). The stderr message says which. |

## On exit 21 (conflict — STOP)

**Stop immediately.** Do not attempt to resolve automatically.

> **L2 rebase conflicts are expected.** `customizations` now holds both L1 and L2 commits.
> L2 commits by definition reference store-specific code (metafields, branding, app IDs) that
> may conflict with upstream Dawn changes. Each L2 conflict needs manual review — this is correct
> behaviour, not an error. Resolve each conflict by verifying the store-specific dependency still
> holds in the new Dawn version, then `git rebase --continue`.

1. Show the user which branch conflicted (printed to stderr) and run `git status` to list conflicting files.
2. Open the conflicting files and show the conflict markers to the user.
3. Resolve the conflicts **together with the user** — do not guess intent.
4. After resolution: `git add <resolved-files> && git rebase --continue`.
5. If more conflicts arise, repeat from step 1.
6. Once the rebase completes, re-run the remaining rebase steps manually (e.g. if conflict was on `customizations`, still need to rebase `staging` onto `customizations`).

## After a successful upgrade

- Test the new version on the Shopify preview theme before promoting.
- Run `dawn-promote` to push `staging` → `current` when satisfied.
- **Locale keys:** the new Dawn's upstream locales supersede ours. Re-apply any L1-feature locale additions per `docs/superpowers/inventory/manifest-L1-locale.md`.
