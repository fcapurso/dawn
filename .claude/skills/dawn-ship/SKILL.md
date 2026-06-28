---
name: dawn-ship
description: Cherry-pick a classified commit from customizations onto the live theme (current). Use when the user says ship inert, ship this commit, push to live without a full promote, or unblock a page binding.
---

## dawn-ship

Ships a **single classified commit** from `customizations` onto `current` — append-only, no force-push, churn-free. Use this to push dormant (inert) building blocks to the live theme ahead of a full promote, or to ship tested-active changes incrementally.

This skill operates from a checked-out `ops` branch (or any non-`current` branch with a clean working tree).

### Running

```bash
bash .claude/skills/dawn-ship/ship.sh <commit-ish>
```

Replace `<commit-ish>` with the SHA or branch tip you want to ship (must be reachable from `customizations`).

### Exit codes and required responses

**Exit 10 (GUARD)**
The commit is not reachable from `customizations`, or another precondition failed. Report the printed reason to the user and do not proceed.

**Exit 21 (STOP-JUDGMENT — new suffix template)**
The commit adds a suffix template (`page.*.json` or `product.*.json`). **STOP.**

Tell the user:
> "This commit adds a new suffix template. Before shipping, confirm in the Shopify admin that NO page or product is currently assigned to this template. Once confirmed, re-run with `--confirm-live`."

**Exit 20 (STOP-live — awaiting human approval)**
The script has printed:
1. The classifier report (per-path `inert`/`active` labels and verdict)
2. The full diff to be shipped
3. (For active changes) A smoke-test checklist

**STOP here.** Show the operator the output and ask explicitly:
> "The above diff and classifier report describe exactly what will be shipped to the LIVE theme. Classifier verdict: [ALL_INERT / HAS_ACTIVE]. Do you approve shipping this commit to current? (yes/no)"

If the verdict is `HAS_ACTIVE`, also say:
> "This contains active changes. Please complete the smoke-test checklist above before confirming."

Only re-run with `--confirm-live` after the user has clearly said yes.

```bash
bash .claude/skills/dawn-ship/ship.sh <commit-ish> --confirm-live
```

**Exit 0 (success)**
Tell the user:
> "Commit `<sha>` has been shipped to current (live). Classifier verdict: [ALL_INERT / HAS_ACTIVE]. A rollback tag `ship-rollback/<timestamp>` was created at the pre-ship state."

Rollback command if needed:
```bash
git push --force-with-lease origin ship-rollback/<timestamp>:current
```
