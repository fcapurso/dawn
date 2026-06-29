# Dawn-harvest redesign: interactive feature harvesting — Design

**Date:** 2026-06-29
**Repo:** Dawn / Zogezeept (operated from `ops`)
**Status:** Approved design, pending implementation plan

> Context: the current `dawn-harvest` skill operates on a single file at a time and only lifts L1
> (generic) code. Two limitations surfaced: (1) a feature naturally spans multiple files (section +
> locale strings + assets) and should be harvested as one atomic commit; (2) store-specific L2
> enrichments should also live in `customizations` as discrete classified commits so they can be
> shipped independently via `dawn-ship`. This redesign addresses both.

---

## 1. Model change: `customizations` holds L1 and L2

Under the previous model `customizations` was L1-only. This design changes that:

**`customizations` is now the home for all code above vanilla** — both L1 generic features and L2
store-specific enrichments — as discrete, classified commits. The two layers are distinguished by:

- Commit message prefix: `L1:` (generic) or `L2:` (store-specific)
- `Inert:` trailer: `yes`, `no`, or `needs_judgment`

The **stranger test** still governs L1 vs L2 classification: L1 = a stranger could drop this onto
any Dawn fork unchanged; L2 = anything referencing store-specific data, metafields, branding, or
app instance IDs.

`staging` continues to hold `customizations` + a config-snapshot commit at the tip. The only
change is that `staging` may now have fewer enrichment commits of its own (since L2 enrichments
move up to `customizations` rather than living as fat staging-only commits).

### Dawn upgrade impact

`dawn-upgrade` rebases `customizations` onto the new `dawn-vanilla`. With L2 commits in
`customizations`, conflicts during this rebase are **expected** for store-specific code. The
`dawn-upgrade` SKILL.md must be updated to note this: each L2 conflict needs manual review, which
is correct behaviour — L2 code by definition has store-specific dependencies that must be
re-verified on each Dawn version.

---

## 2. Problem with the current skill

`harvest.sh <path> [--hunks]`:

- Operates on one file at a time — a feature spanning a section, its locale strings, and its
  assets requires multiple invocations with no grouping
- L1-only — store-specific enrichments have no harvest path, so they accumulate as fat unstructured
  commits on `staging`
- No analysis — the operator must already know what to harvest and in what order
- `--hunks` stops without performing the split — it is guidance to the human, not automation

---

## 3. Architecture

Three layers, each with a distinct responsibility:

| Layer | Component | Responsibility |
|---|---|---|
| **Analysis** | `dawn::harvest_candidates` (bash, in `dawn-ops.sh`) | Diff `staging` vs `customizations`, classify all changed files, emit structured candidate list |
| **Judgment** | `SKILL.md` (agent workflow) | Group files into feature commits, detect mixed files, propose L1/L2 classification, confirm via `AskUserQuestion`, drive execution |
| **Execution** | `harvest-commit.sh` (bash) | Atomically checkout files, commit to `customizations`, rebase `staging` |

The existing `harvest.sh` is **retired**. All harvest paths go through the new interactive workflow.

---

## 4. `dawn::harvest_candidates`

Added to `.claude/skills/_dawn-ops-lib/dawn-ops.sh`.

**Input:** none (reads `staging` and `customizations` from the repo).

**Output:** one line per changed file (stdout):

```
<verdict> <l1l2-hint> <path>
```

- `<verdict>`: `inert`, `active`, or `needs_judgment` — from `dawn::classify_changes` on the full
  range `customizations..staging` restricted to that path
- `<l1l2-hint>`: `L1` or `L2` — conservative keyword scan of the file's content on `staging`:
  - `L2` if the file contains store-specific markers: Zogezeept/zogezeept domain strings,
    known metafield handle patterns (e.g. `custom\.`), `.myshopify.com`, GTM IDs, or
    store-specific product-type slugs
  - `L1` otherwise (agent applies the stranger test to confirm or override)
- `<path>`: repo-relative path

**Scope:** `git diff --name-only customizations staging` excluding all paths in `config-paths.txt`
and excluding `docs/` and `.claude/`.

**Example output:**
```
inert     L1  sections/withdrawal.liquid
inert     L1  locales/nl.default.json
inert     L2  templates/page.withdrawal.json
active    L2  layout/theme.liquid
needs_judgment L2 templates/product.soap.json
needs_judgment L2 templates/product.workshop.json
inert     L2  templates/page.store_finder.liquid
```

**Design constraints:**
- No external dependencies (pure bash + git)
- Deterministic and testable via the fixture harness
- Output is for agent consumption — human-readable, not machine-parsed

---

## 5. SKILL.md — agent workflow

The SKILL.md instructs the agent through five steps.

### Step 1: Run analysis

```bash
source .claude/skills/_dawn-ops-lib/dawn-ops.sh
dawn::harvest_candidates
```

If the output is empty: report "nothing to harvest — staging and customizations are in sync" and
stop.

### Step 2: Group into proposed commits

The agent groups the candidate files into proposed feature commits using semantic relationships:

- **Locale grouping:** a section file (e.g. `sections/withdrawal.liquid`) groups with locale keys
  whose top-level namespace matches the section handle — detected by scanning the locale JSON files
  in the diff for keys prefixed with the section handle (e.g. `withdrawal.*`)
- **Asset grouping:** a section file groups with assets it directly references via `asset_url` —
  detected by scanning the section's content
- **Template grouping:** a suffix template (e.g. `templates/product.soap.json`) groups with any
  snippets or sections it exclusively references that are also in the candidate list
- **Independent files:** any file with no detected relationship to others is proposed as its own
  single-file commit

Staging commit history is **not used** for grouping — the diff is the net effect of all staging
work regardless of how many commits produced it.

For each proposed group, the agent:
1. Applies the stranger test to confirm or override the `l1l2-hint`
2. Drafts a commit message: `L1: <description>` or `L2: <description>`
3. Confirms the `Inert:` trailer from the classifier verdict for the group

### Step 3: Detect and plan hunk splits

For any file where the diff contains **both** generic (L1) and store-specific (L2) content:

- If the hunks are cleanly separated (non-interleaved): the agent proposes splitting the file into
  two commits — an L1 commit with the generic portion, an L2 commit with the remainder. The agent
  writes the L1-only content to a temp file for `harvest-commit.sh`
- If the hunks interleave: the agent flags the file as requiring manual separation and skips it,
  reporting exactly which lines need to be disentangled before it can be harvested

### Step 4: Confirm via AskUserQuestion

One `AskUserQuestion` call per proposed commit (in feature order, not alphabetical). Each question
shows:
- Proposed commit message
- File list with per-file classifier verdict
- L1 or L2 classification with reasoning

Options: **Approve** / **Change to L1** / **Change to L2** / **Skip** / **Edit message**

The agent processes all answers before executing any commits. If "Edit message" is chosen, the
agent asks a follow-up open-text question for the new message.

### Step 5: Execute in order

For each approved group, the agent calls `harvest-commit.sh`. Groups execute in the order the
agent determined (dependencies first — if a section is L1 and its template is L2, the section
commit comes first). After all groups: report the final `customizations` log and confirm `staging`
tip is still the config snapshot.

---

## 6. `harvest-commit.sh`

New file: `.claude/skills/dawn-harvest/harvest-commit.sh`

**Usage:**
```
harvest-commit.sh --message <msg> --files <f1> [f2 ...] [--l1-content <file>:<tmppath>]
```

- `--message`: the full commit message including the `Inert:` trailer
- `--files`: space-separated list of repo-relative paths to check out from `staging`
- `--l1-content <file>:<tmppath>`: for hunk splits — use `<tmppath>` content instead of checking
  out `<file>` from `staging` (can be specified multiple times)

**Behaviour:**
1. `dawn::assert_not_current`, `dawn::assert_clean_tree`
2. Validate no file is in `config-paths.txt` (config files are never harvestable)
3. `dawn::with_branch customizations`
4. For each file: `git checkout staging -- <file>`, or write `<tmppath>` content if `--l1-content`
   provided for that file
5. `git add` all files
6. `git commit -q -m "$message"` — the `Inert:` trailer in `--message` is trusted as provided by
   the agent (already determined by `dawn::harvest_candidates` + agent judgment)
7. `git checkout -q staging`
8. `git rebase -q customizations` — on conflict, exit `DAWN_STOP_JUDGMENT` with the standard
   mid-rebase guidance

**Exit codes:** standard contract (`DAWN_OK`, `DAWN_GUARD`, `DAWN_STOP_JUDGMENT`).

The old `harvest.sh` is deleted. Tests for `harvest-commit.sh` use the fixture/harness pattern.

---

## 7. Retroactive split of the monolithic L2 commit

The current `staging` has a single fat commit `L2: store enrichments (custom product templates,
store finder, GTM, withdrawal page)` containing 9 files. After the skill is built, the very first
real use will be to run `dawn-harvest` interactively to split this commit into atomic classified L2
commits in `customizations`.

The implementation plan will include a final task: **"run `dawn-harvest` on the staging
enrichments"** — this is a usage task, not a code task, and produces the correct atomic history as
its output.

---

## 8. Components affected

| Path | Change |
|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | Add `dawn::harvest_candidates` |
| `.claude/skills/dawn-harvest/SKILL.md` | Rewrite for interactive agent workflow |
| `.claude/skills/dawn-harvest/harvest-commit.sh` | New execution primitive |
| `.claude/skills/dawn-harvest/harvest.sh` | **Delete** |
| `.claude/skills/dawn-upgrade/SKILL.md` | Add note: L2 commits in `customizations` produce expected rebase conflicts |
| `.claude/skills/_dawn-ops-lib/conventions.md` | §1 branch model, §5 L1 vs L2: reflect both layers in `customizations` |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | Update harvest step to describe interactive flow |
| `tests/test_harvest.sh` | Rewrite for `harvest-commit.sh`; add `test_harvest_candidates.sh` |
| `tests/run-all.sh` | Register `test_harvest_candidates.sh` |

---

## 9. Testing

Follow the existing fixture/harness pattern (`tests/harness.sh`, `tests/fixture.sh`).

### `test_harvest_candidates.sh`

Using a fixture with known staging commits above `customizations`:
- Assert orphan section → `inert L1`
- Assert reachable layout file → `active L1` (no store markers)
- Assert file with store-specific keyword → hint `L2`
- Assert suffix template → `needs_judgment L2`
- Assert config files are excluded from output
- Assert empty output when staging == customizations (code-only)

### `test_harvest.sh` (rewritten for `harvest-commit.sh`)

- Single-file commit: correct `Inert:` trailer, `customizations` updated, `staging` rebased
- Multi-file commit: section + locale file committed together as one atomic commit
- `--l1-content` override: correct file content lands in the commit, not the staging version
- Guard: config file in `--files` list → `DAWN_GUARD`
- Rebase conflict → `DAWN_STOP_JUDGMENT`, left in mid-rebase state with clear message

---

## 10. Success criteria

- Running `dawn-harvest` on a repo where staging has multi-file features produces a proposal
  grouping section + locale strings + assets as single commits, confirmed via `AskUserQuestion`
- The retroactive split of the monolithic L2 enrichment commit produces N atomic `L2:` commits in
  `customizations`, each shippable independently via `dawn-ship`
- `dawn-upgrade` continues to work; its SKILL.md makes clear that L2 rebase conflicts are expected
  and require manual review
- All tests pass; `dawn-ship` and `dawn-promote` are unaffected
