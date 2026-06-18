---
name: dawn-harvest
description: Lift a generic, reusable change from staging up into the customizations (L1) layer. Use when the user says harvest, this should be generic, move to customizations, or make this upstreamable.
---

## Overview

`dawn-harvest` promotes a file that currently lives only on `staging` into the `customizations` branch as a proper L1 commit, then rebases `staging` on top so the config snapshot remains the tip.

See `../_dawn-ops-lib/conventions.md` for layer definitions (L0 vanilla / L1 customizations / L2 store config).

## Prerequisites

- Must be run from the `ops` branch (or any non-`current` branch with a clean working tree).
- The target file must exist on `staging`.

## Usage

```
bash .claude/skills/dawn-harvest/harvest.sh <path> [--hunks]
```

- `<path>` — repo-relative path to the file to harvest (e.g. `assets/base.css`).
- `--hunks` — use when the file contains a mix of generic and store-specific lines that need splitting before harvesting.

## Exit codes and agent responses

| Code | Meaning | Agent action |
|------|---------|--------------|
| 0 (`DAWN_OK`) | Success | Confirm: the L1 commit landed on `customizations` and `staging`'s tip is still the config snapshot. |
| 10 (`DAWN_GUARD`) | Guard tripped | Report the reason (config/L2 file not harvestable to L1; or dirty working tree). Do not retry without resolving the guard. |
| 21 (`DAWN_STOP_JUDGMENT`) | Needs human judgment | Either the file mixes generic + store-specific lines (`--hunks` path): **STOP**, work with the user to isolate the generic hunks into a separate trimmed file, then re-run on that file. Or a rebase conflict occurred: report the conflict to the user and resolve it together before retrying. |

## L1 "stranger test"

Only harvest changes that pass the stranger test: would a Shopify merchant with a different store want this exact change? If the answer is yes — it's generic, L1-safe. If the change references store-specific data, domain names, product IDs, or config values — it belongs in L2, not L1.
