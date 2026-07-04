---
name: dawn-stage-push
description: Push the reconciled staging branch to the preview theme (origin/staging) so it can be tested live before promote. Use when the user says stage-push, push to staging, push to preview, or test staging before going live.
---

## dawn-stage-push

This skill operates from a checked-out `ops` branch. See `../_dawn-ops-lib/conventions.md` for the
layer model (L0 vanilla / L1 customizations / L2 staging / current live) and the three-stage
release flow (`backflow → stage-push → promote`).

Pushes local `staging` to `origin/staging` (the preview theme) only. Nothing touches `current` —
this is not a live release, so there is no `--confirm-live` gate. It is still a force-push, so the
same drift guard and staging-cleanliness check that `dawn-promote` uses apply here first.

### Running

```bash
bash .claude/skills/dawn-stage-push/stage-push.sh
```

### Exit codes and required responses

**Exit 10 (GUARD)**

Either:
- **Backflow pending** — `origin/current` or `origin/staging` has edits not yet folded into
  staging (config-class or non-config drift). Tell the user:
  > "There are unsynced live edits that must be merged back into staging first. Run the
  > `dawn-backflow` skill, then retry stage-push."
- **Staging not clean** — `assert_staging_clean` failed (staging has diverged from
  `customizations`, or its tip isn't a config-snapshot commit). Report the guard message printed
  to stderr and follow its instructions (rebase onto `customizations`, or re-run `dawn-backflow`
  to recreate the snapshot).

Do NOT proceed until the guard condition is resolved — re-run `dawn-backflow` (or fix staging) and
retry `dawn-stage-push` from the top.

**Exit 0 (success)**

Tell the user:
> "staging has been pushed to origin/staging (the preview theme). Test it there, then run
> dawn-promote when you're ready to go live."

No live-confirm step is required here — nothing customer-facing changes until `dawn-promote` runs.
