---
name: dawn-upgrade
description: Upgrade to a new Dawn version — fast-forward dawn-vanilla then rebase customizations and staging. Use when the user says upgrade Dawn, bump Dawn version, or move to a new Dawn release.
---

## Agent operating context

Operate from the `ops` branch (never `current`). See `../_dawn-ops-lib/conventions.md` for branch conventions and exit-code contract.

## Usage

```bash
bash .claude/skills/dawn-upgrade/upgrade.sh <tag>
# e.g. bash .claude/skills/dawn-upgrade/upgrade.sh v15.4.1
```

The script:
1. Fast-forwards `dawn-vanilla` to `<tag>` (must be a descendant — no force-push).
2. Rebases `customizations` onto `dawn-vanilla`.
3. Rebases `staging` onto `customizations`.

## Exit codes

| Code | Meaning | What to do |
|------|---------|-----------|
| 0 | Success | Test on the preview theme, then run `dawn-promote`. |
| 10 | Guard triggered | Report the guard message: tag not ahead of `dawn-vanilla`, or working tree has staged/modified tracked files. |
| 21 | STOP — judgment required | Rebase conflict. See below. |

## On exit 21 (conflict — STOP)

**Stop immediately.** Do not attempt to resolve automatically.

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
