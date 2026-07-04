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

### Exit 10 — guard triggered

Report the guard message from stderr. Two possible causes:

1. **Stage-push not current.** Either staging was never pushed to the preview theme, staging has
   changed since the last push, or the preview theme received a new bot commit since the push. In
   all cases: run `dawn-stage-push` (after `dawn-backflow` if needed), then retry promote.

2. **Backflow pending.** Either `origin/current` or `origin/staging` has config edits not yet
   folded into staging. Tell the user:
   > "There are unsynced live edits that must be merged back into staging first. Run the
   > `dawn-backflow` skill, then retry `dawn-stage-push` and promote."

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
