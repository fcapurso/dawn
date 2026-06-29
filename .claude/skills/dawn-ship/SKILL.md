---
name: dawn-ship
description: Ship a classified commit from customizations to the live theme (current). Use when the user says ship, push to live, ship this commit, unblock a page binding, or what can I ship.
---

## dawn-ship

Ships a **single classified commit** from `customizations` onto `current` — append-only, no force-push, churn-free. Use this to push dormant (inert) building blocks to the live theme ahead of a full promote, or to ship tested-active changes incrementally.

This skill operates from a checked-out `ops` branch (or any non-`current` branch with a clean working tree).

### Two modes

**Interactive (no commit provided):** list inert candidates and let the operator pick one.

**Direct (commit hash provided):** skip the list and ship that commit.

---

### Mode 1 — Interactive: list and pick

When the user has not specified a commit, run:

```bash
source .claude/skills/_dawn-ops-lib/dawn-ops.sh
git cherry -v refs/remotes/origin/current customizations \
  | grep '^+' | awk '{print $2}' \
  | while IFS= read -r sha; do
      body=$(git log -1 --format=%B "$sha")
      if echo "$body" | grep -q '^Inert: yes'; then
        echo "$sha  $(git log -1 --format=%s "$sha")"
      fi
    done
```

If the output is empty: report "no inert commits in customizations are waiting to be shipped" and stop.

Otherwise, present the list via `AskUserQuestion`:
- One question: "Which commit would you like to ship to the live theme?"
- Options: one per candidate showing `<short-sha>  <subject>`, plus "None / cancel"

Once the operator picks one, proceed with that SHA exactly as in Mode 2 below.

---

### Mode 2 — Direct: ship a specific commit

```bash
bash .claude/skills/dawn-ship/ship.sh <commit-ish>
```

Replace `<commit-ish>` with the SHA or branch tip you want to ship (must be reachable from `customizations`).

The interactive list shows **only `Inert: yes` commits** — `needs_judgment` and active commits are excluded. To ship those, pass the SHA directly (Mode 2) and follow the extra confirmation steps below.

---

### Exit codes and required responses

**Exit 10 (GUARD)**
The commit is not reachable from `customizations`, or another precondition failed. Report the printed reason to the user and do not proceed.

**Exit 21 (STOP-JUDGMENT — new suffix template)**
The commit adds a suffix template (`page.*.json` or `product.*.json`). **STOP.**

Tell the user:
> "This commit adds a new suffix template. Before shipping, confirm in the Shopify admin that NO page or product is currently assigned to this template."

Once the user has confirmed in admin that the template is unbound, re-run with `--confirm-live`:

```bash
bash .claude/skills/dawn-ship/ship.sh <commit-ish> --confirm-live
```

The `--confirm-live` flag signals that the operator has manually verified the template is unbound.

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
