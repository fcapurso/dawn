---
name: dawn-promote
description: Publish the staging branch to the live Shopify theme (current). Use when the user says promote, go live, publish staging, or deploy the theme. Requires explicit live confirmation.
---

## dawn-promote

This skill operates from a checked-out `ops` branch. See `../_dawn-ops-lib/conventions.md` for the layer model (L0 vanilla / L1 customizations / L2 staging / current live).

### Running

```bash
bash .claude/skills/dawn-promote/promote.sh
```

### Exit codes and required responses

**Exit 10 (GUARD — backflow pending)**
Either `origin/current` or `origin/staging` (the preview theme) has edits not yet folded into
staging — config-class drift on either remote, or non-config drift (e.g. locale files) on
`origin/staging`. Report the guard message printed to stderr, which names which remote and which
kind of drift, then tell the user:
> "There are unsynced live edits that must be merged back into staging first. Run the `dawn-backflow` skill, then retry promote."

Do NOT proceed until backflow is complete.

**Exit 20 (STOP-live — awaiting human approval)**
The script has printed a diff summary of what will change on the live shop. **STOP here.** Show the user the printed diff and ask explicitly:
> "The above changes are ready to push to the LIVE shop. Do you approve? (yes/no)"

Only re-run with `--confirm-live` after the user has clearly said yes in the conversation. The agent must **never** pass `--confirm-live` autonomously.

```bash
bash .claude/skills/dawn-promote/promote.sh --confirm-live
```

**Exit 0 (success)**
Tell the user:
> "staging has been promoted to current (live). The live theme is now updated. A rollback tag `config-archive/<timestamp>` was created at the pre-promote state."

Rollback command if needed:
```bash
git push --force-with-lease origin config-archive/<timestamp>:current
```
(Replace `<timestamp>` with the tag printed during the run, or list tags with `git tag | grep config-archive/`.)
