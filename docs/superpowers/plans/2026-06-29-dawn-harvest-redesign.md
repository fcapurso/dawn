# Dawn-harvest Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-file `harvest.sh` with a three-layer interactive agent workflow: a bash analysis helper (`dawn::harvest_candidates`), a rewritten `SKILL.md` driving grouped multi-file commits via `AskUserQuestion`, and a new `harvest-commit.sh` execution primitive.

**Architecture:** `dawn::harvest_candidates` (in `dawn-ops.sh`) diffs `staging` vs `customizations`, classifies each file, and emits a structured candidate list. The `SKILL.md` groups files into proposed commits, handles hunk splits, confirms each group via `AskUserQuestion`, and calls `harvest-commit.sh` to execute. `harvest-commit.sh` atomically checks out files onto `customizations` and rebases `staging`. `conventions.md`, `dawn-upgrade/SKILL.md`, and the runbook are updated to reflect that `customizations` now holds both L1 and L2 commits.

**Tech Stack:** Bash 5, git, the existing `_dawn-ops-lib` harness (`harness.sh`, `fixture.sh`), `AskUserQuestion` in the `SKILL.md` agent context.

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `.claude/skills/_dawn-ops-lib/dawn-ops.sh` | Modify | Add `dawn::harvest_candidates` function |
| `.claude/skills/dawn-harvest/harvest-commit.sh` | Create | Atomic execution primitive: checkout files → commit to `customizations` → rebase `staging` |
| `.claude/skills/dawn-harvest/SKILL.md` | Rewrite | Interactive agent workflow: analyse → group → detect splits → confirm → execute |
| `.claude/skills/dawn-harvest/harvest.sh` | Delete | Retired |
| `.claude/skills/dawn-upgrade/SKILL.md` | Modify | Add note that L2 commits in `customizations` produce expected rebase conflicts |
| `.claude/skills/_dawn-ops-lib/conventions.md` | Modify | §1 branch model + §5 L1/L2: reflect both layers in `customizations` |
| `docs/superpowers/runbook/dawn-dev-and-release.md` | Modify | Update harvest section to describe interactive flow |
| `tests/test_harvest_candidates.sh` | Create | Tests for `dawn::harvest_candidates` |
| `tests/test_harvest.sh` | Rewrite | Tests for `harvest-commit.sh` |
| `tests/run-all.sh` | Modify | Register `test_harvest_candidates` |

---

## Task 1: Add `dawn::harvest_candidates` to `dawn-ops.sh`

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/dawn-ops.sh`

The function diffs `staging` vs `customizations` (excluding `config-paths.txt`, `docs/`, `.claude/`), runs `dawn::classify_changes` over the full range for each file to get its verdict, then does a keyword scan for L2 markers to emit an `l1l2-hint`.

L2 markers (case-insensitive keyword scan of the file content on `staging`):
- `zogezeept` (domain / branding strings)
- `custom\.` (metafield handle pattern)
- `.myshopify.com`
- `GTM-` (GTM IDs)

Each output line: `<verdict>\t<l1l2-hint>\t<path>` (tab-separated, padded for human readability).

- [ ] **Step 1: Add the function at the end of `dawn-ops.sh`** (before the last blank line if any; after `dawn::classify_changes`).

Append to `.claude/skills/_dawn-ops-lib/dawn-ops.sh`:

```bash
# Emit candidate files to harvest from staging into customizations.
# Output: one line per file: "<verdict>  <L1|L2>  <path>"
# Scope: git diff --name-only customizations staging, excluding config-paths.txt, docs/, .claude/
dawn::harvest_candidates(){
  local config_files; config_files=$(dawn::config_files)

  # Build exclusion list from config-paths.txt
  local excludes=()
  while IFS= read -r p; do [ -z "$p" ] && continue; excludes+=(":(exclude)$p"); done \
    < "$DAWN_LIB_DIR/config-paths.txt"

  local files
  files=$(git diff --name-only customizations staging \
    -- . ':(exclude)docs/' ':(exclude).claude/' "${excludes[@]}" 2>/dev/null) || true

  [ -z "$files" ] && return 0

  while IFS= read -r path; do
    [ -z "$path" ] && continue

    # Per-file verdict via classify_changes on the full range restricted to this path
    local verdict_line
    verdict_line=$(git diff --name-only customizations staging -- "$path" | head -1)
    [ -z "$verdict_line" ] && continue

    # classify_changes needs a range; use the full staging range
    local cls_out
    cls_out=$(dawn::classify_changes "customizations..staging" 2>/dev/null | grep " $path$" | head -1 || true)
    local verdict
    case "$cls_out" in
      needs_judgment*) verdict="needs_judgment" ;;
      active*)         verdict="active" ;;
      *)               verdict="inert" ;;
    esac

    # L2 keyword scan on the file content at staging
    local hint="L1"
    local content; content=$(git show "staging:$path" 2>/dev/null || true)
    if echo "$content" | grep -qiE 'zogezeept|custom\.|\.myshopify\.com|GTM-'; then
      hint="L2"
    fi

    printf "%-18s %-4s %s\n" "$verdict" "$hint" "$path"
  done <<< "$files"
}
```

- [ ] **Step 2: Verify the function loads without error**

```bash
cd /Users/filippo/Shopify/dawn
bash -c 'source .claude/skills/_dawn-ops-lib/dawn-ops.sh && echo ok'
```

Expected output: `ok`

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/dawn-ops.sh
git commit -m "feat(harvest): add dawn::harvest_candidates to dawn-ops.sh"
```

---

## Task 2: Write tests for `dawn::harvest_candidates`

**Files:**
- Create: `tests/test_harvest_candidates.sh`

This task uses the existing fixture harness pattern. The fixture sets up `dawn-vanilla` → `customizations` → `staging` with known files. We extend it inline (similar to `test_harvest.sh`) by adding commits to `staging` with known content.

Key test cases from the spec:
1. Orphan section (no store markers, not reachable) → `inert L1`
2. Layout file (reachable, no store markers) → `active L1`
3. File with store-specific keyword (`zogezeept`) → hint `L2`
4. Suffix template (`templates/product.soap.json`) → `needs_judgment L2`
5. Config file (in `config-paths.txt`) → **excluded** from output
6. Empty output when `staging == customizations` (nothing to harvest)

- [ ] **Step 1: Write `tests/test_harvest_candidates.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"

# --- Fixture: use the standard fixture then add staging commits for each test case ---
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"

# Add test files on staging
git checkout -q staging

# 1. Orphan section — no store markers, not in reachable set
echo '<div>widget</div>' > sections/new-widget.liquid
git add sections/new-widget.liquid; git commit -qm "add new-widget section on staging"

# 2. Layout file — always reachable (active), no store markers
mkdir -p layout; echo '<!DOCTYPE html><html></html>' > layout/theme.liquid
git add layout/theme.liquid; git commit -qm "add layout/theme.liquid on staging"

# 3. File with zogezeept domain string → L2 hint
echo 'redirect to zogezeept.com' > sections/store-info.liquid
git add sections/store-info.liquid; git commit -qm "add store-info section on staging"

# 4. Suffix template → needs_judgment + L2 hint (no store markers but suffix template)
echo '{"sections":{}}' > templates/product.soap.json
git add templates/product.soap.json; git commit -qm "add product.soap template on staging"

# 5. Config file — must be excluded (config/settings_data.json is always in config-paths.txt)
# Already present in fixture; let's add a change to it on staging to ensure it's excluded
echo '{"changed":true}' > config/settings_data.json
git add config/settings_data.json; git commit -qm "change settings_data on staging"

# Source the lib
source "$HERE/.claude/skills/_dawn-ops-lib/dawn-ops.sh"

output=$(dawn::harvest_candidates)

# 1. Orphan section → inert L1
assert_contains "orphan section inert"   "$output" "inert"
assert_contains "orphan section L1 hint" "$output" "L1"
assert_contains "orphan section path"    "$output" "sections/new-widget.liquid"

# 2. Layout → active L1
assert_contains "layout active"     "$output" "active"
assert_contains "layout L1 hint"    "$(echo "$output" | grep 'layout/theme.liquid')" "L1"

# 3. Store-specific file → L2 hint
assert_contains "store-info L2 hint" "$(echo "$output" | grep 'store-info')" "L2"

# 4. Suffix template → needs_judgment
assert_contains "product.soap needs_judgment" "$(echo "$output" | grep 'product.soap')" "needs_judgment"

# 5. Config file excluded
case "$output" in
  *"config/settings_data.json"*) _fail "config excluded" "config file appeared in output" ;;
  *) _pass "config excluded" ;;
esac

# 6. Empty output when staging == customizations
FIX2=$(bash "$HERE/tests/fixture.sh"); cd "$FIX2"
# Standard fixture: staging is ahead by 2 commits (enrichment + config snapshot);
# but those include templates/product.workshop.json and config files.
# For a clean "nothing to harvest" check, fast-forward staging to customizations.
git checkout -q staging
git reset -q --hard customizations
source "$HERE/.claude/skills/_dawn-ops-lib/dawn-ops.sh"
empty_out=$(dawn::harvest_candidates)
assert_eq "empty when in sync" "$empty_out" ""

finish
```

- [ ] **Step 2: Run the new test**

```bash
bash tests/test_harvest_candidates.sh
```

Expected: all assertions pass, `== N passed, 0 failed ==`

- [ ] **Step 3: Commit**

```bash
git add tests/test_harvest_candidates.sh
git commit -m "test(harvest): add test_harvest_candidates for dawn::harvest_candidates"
```

---

## Task 3: Register `test_harvest_candidates` in `run-all.sh`

**Files:**
- Modify: `tests/run-all.sh`

- [ ] **Step 1: Add `test_harvest_candidates` to the loop**

Current loop line in `tests/run-all.sh`:
```bash
for t in test_lib test_backflow test_harvest test_upgrade test_classify test_ship; do
```

Change to:
```bash
for t in test_lib test_backflow test_harvest test_upgrade test_classify test_ship test_harvest_candidates; do
```

- [ ] **Step 2: Run the full suite to confirm nothing regresses**

```bash
bash tests/run-all.sh
```

Expected: all suites report `0 failed`.

- [ ] **Step 3: Commit**

```bash
git add tests/run-all.sh
git commit -m "test: register test_harvest_candidates in run-all.sh"
```

---

## Task 4: Create `harvest-commit.sh`

**Files:**
- Create: `.claude/skills/dawn-harvest/harvest-commit.sh`

**Usage:**
```
harvest-commit.sh --message <msg> --files <f1> [f2 ...] [--l1-content <file>:<tmppath> ...]
```

Behaviour:
1. Guard: `dawn::assert_not_current`, `dawn::assert_clean_tree`
2. Guard: reject any file in `config-paths.txt` → exit `DAWN_GUARD`
3. `dawn::with_branch customizations`
4. For each `--files` entry: `git checkout staging -- <file>`, unless overridden by `--l1-content <file>:<tmppath>` (then copy tmppath content)
5. `git add` all files
6. `git commit -q -m "$message"` (message already contains the `Inert:` trailer)
7. `git checkout -q staging`
8. `git rebase -q customizations` → on conflict, exit `DAWN_STOP_JUDGMENT`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# harvest-commit.sh --message <msg> --files <f1> [f2 ...] [--l1-content <file>:<tmp> ...]
# Atomically commits files from staging into customizations, then rebases staging.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../_dawn-ops-lib" && pwd)/dawn-ops.sh"

usage(){ echo "usage: harvest-commit.sh --message <msg> --files <f1> [f2 ...] [--l1-content <file>:<tmppath> ...]" >&2; exit $DAWN_GUARD; }

msg="" files=() l1_overrides=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message)   shift; msg="$1"; shift ;;
    --files)     shift; while [[ $# -gt 0 && "$1" != --* ]]; do files+=("$1"); shift; done ;;
    --l1-content) shift; l1_overrides+=("$1"); shift ;;
    *) usage ;;
  esac
done

[[ -z "$msg" ]]        && { echo "GUARD: --message is required" >&2; exit $DAWN_GUARD; }
[[ ${#files[@]} -eq 0 ]] && { echo "GUARD: --files requires at least one path" >&2; exit $DAWN_GUARD; }

dawn::assert_not_current || exit $DAWN_GUARD
dawn::assert_clean_tree  || exit $DAWN_GUARD

# Guard: reject config files
while IFS= read -r c; do
  for f in "${files[@]}"; do
    if [[ "$f" = "$c" ]]; then
      echo "GUARD: $f is a config file — config files are not harvestable" >&2
      exit $DAWN_GUARD
    fi
  done
done < <(dawn::config_files)

dawn::with_branch customizations || exit $DAWN_GUARD

# Build a lookup for l1-content overrides: override["file"]="tmppath"
declare -A override=()
for entry in "${l1_overrides[@]}"; do
  key="${entry%%:*}"; val="${entry#*:}"
  override["$key"]="$val"
done

for f in "${files[@]}"; do
  if [[ -n "${override[$f]+set}" ]]; then
    tmp="${override[$f]}"
    mkdir -p "$(dirname "$f")"
    cp "$tmp" "$f"
    git add "$f"
  else
    git checkout staging -- "$f"
  fi
done

git add "${files[@]}"
git commit -q -m "$msg"

git checkout -q staging
git rebase -q customizations || {
  echo "STOP: rebase conflict bringing harvest commit into staging." >&2
  echo "Resolve conflicts, then: git rebase --continue (or git rebase --abort to undo)." >&2
  exit $DAWN_STOP_JUDGMENT
}
echo "Committed to customizations and rebased staging."
exit $DAWN_OK
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x .claude/skills/dawn-harvest/harvest-commit.sh
```

- [ ] **Step 3: Smoke-test loads without error**

```bash
bash -n .claude/skills/dawn-harvest/harvest-commit.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/dawn-harvest/harvest-commit.sh
git commit -m "feat(harvest): add harvest-commit.sh execution primitive"
```

---

## Task 5: Rewrite `tests/test_harvest.sh` for `harvest-commit.sh`

**Files:**
- Modify: `tests/test_harvest.sh`

Replace the old `harvest.sh` tests with tests for `harvest-commit.sh`. Keep the same file; completely rewrite its contents.

Test cases:
1. Single-file commit: correct `Inert:` trailer present in customizations log, staging rebased, config snapshot still at tip
2. Multi-file commit: section + locale file committed together as one atomic commit
3. `--l1-content` override: the overridden file content lands in the commit (not the staging version)
4. Guard: config file in `--files` → exit code 10
5. Rebase conflict → exit code 21, left in mid-rebase state with a clear message

- [ ] **Step 1: Rewrite `tests/test_harvest.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"; source "$HERE/tests/harness.sh"
SH="$HERE/.claude/skills/dawn-harvest/harvest-commit.sh"

# ── Test 1: single-file commit ────────────────────────────────────────────────
FIX=$(bash "$HERE/tests/fixture.sh"); cd "$FIX"
git checkout -q staging
echo '<div>generic widget</div>' > sections/new-widget.liquid
git add sections/new-widget.liquid; git commit -qm "add new-widget on staging"

assert_rc "single-file ok" 0 bash "$SH" \
  --message "L1: add new-widget section

Inert: yes" \
  --files sections/new-widget.liquid

# File is in customizations
assert_eq "in customizations" \
  "$(git show customizations:sections/new-widget.liquid)" \
  '<div>generic widget</div>'

# Inert trailer present
trailer=$(git log -1 --format=%B customizations | grep '^Inert:')
assert_eq "Inert trailer" "$trailer" "Inert: yes"

# staging config snapshot still at tip
git checkout -q staging
assert_contains "config tip preserved" "$(git log -1 --format=%s)" "config"

# ── Test 2: multi-file commit ─────────────────────────────────────────────────
FIX2=$(bash "$HERE/tests/fixture.sh"); cd "$FIX2"
git checkout -q staging
mkdir -p locales
echo '<section>withdrawal</section>' > sections/withdrawal.liquid
printf '{"withdrawal":{"title":"Withdrawal"}}' > locales/nl.default.json
git add sections/withdrawal.liquid locales/nl.default.json
git commit -qm "add withdrawal section + locale on staging"

assert_rc "multi-file ok" 0 bash "$SH" \
  --message "L1: add withdrawal section with locale strings

Inert: yes" \
  --files sections/withdrawal.liquid locales/nl.default.json

# Both files land in one commit on customizations
count=$(git diff-tree --no-commit-id -r --name-only customizations | wc -l | tr -d ' ')
assert_eq "two files in one commit" "$count" "2"

assert_eq "section in customizations" \
  "$(git show customizations:sections/withdrawal.liquid)" \
  '<section>withdrawal</section>'

assert_eq "locale in customizations" \
  "$(git show customizations:locales/nl.default.json)" \
  '{"withdrawal":{"title":"Withdrawal"}}'

# ── Test 3: --l1-content override ────────────────────────────────────────────
FIX3=$(bash "$HERE/tests/fixture.sh"); cd "$FIX3"
git checkout -q staging
echo 'STORE-SPECIFIC CONTENT' > sections/mixed.liquid
git add sections/mixed.liquid; git commit -qm "add mixed section on staging"

# Create a tmp file with only the generic (L1) portion
TMP=$(mktemp); echo 'GENERIC ONLY' > "$TMP"

assert_rc "l1-content override ok" 0 bash "$SH" \
  --message "L1: add generic portion of mixed section

Inert: yes" \
  --files sections/mixed.liquid \
  --l1-content "sections/mixed.liquid:$TMP"

rm -f "$TMP"

# The customizations commit has the tmp content, not the staging version
assert_eq "l1-content in customizations" \
  "$(git show customizations:sections/mixed.liquid)" \
  "GENERIC ONLY"

# ── Test 4: guard — config file rejected ──────────────────────────────────────
FIX4=$(bash "$HERE/tests/fixture.sh"); cd "$FIX4"
assert_rc "guard config file" 10 bash "$SH" \
  --message "L1: should fail

Inert: yes" \
  --files config/settings_data.json

# ── Test 5: rebase conflict → DAWN_STOP_JUDGMENT ─────────────────────────────
FIX5=$(bash "$HERE/tests/fixture.sh"); cd "$FIX5"
git checkout -q staging

# Write to a file that also exists differently on customizations
# (customizations has "VANILLA + L1-INVENTORY" in sections/main-product.liquid)
echo 'CONFLICTING STAGING CHANGE' > sections/main-product.liquid
git add sections/main-product.liquid; git commit -qm "conflicting change on staging"

# Put a different version on customizations to guarantee conflict
git checkout -q customizations
echo 'CONFLICTING CUSTOMIZATIONS CHANGE' > sections/main-product.liquid
git add sections/main-product.liquid; git commit -qm "conflicting change on customizations"
git checkout -q staging

assert_rc "rebase conflict stop-judgment" 21 bash "$SH" \
  --message "L1: conflicting change

Inert: no" \
  --files sections/main-product.liquid

# Clean up mid-rebase state
git rebase --abort 2>/dev/null || true

finish
```

- [ ] **Step 2: Run the rewritten tests**

```bash
bash tests/test_harvest.sh
```

Expected: all 8 assertions pass, `0 failed`.

- [ ] **Step 3: Commit**

```bash
git add tests/test_harvest.sh
git commit -m "test(harvest): rewrite test_harvest.sh for harvest-commit.sh"
```

---

## Task 6: Delete `harvest.sh`

**Files:**
- Delete: `.claude/skills/dawn-harvest/harvest.sh`

- [ ] **Step 1: Delete the old script**

```bash
git rm .claude/skills/dawn-harvest/harvest.sh
```

- [ ] **Step 2: Confirm nothing in the test suite references it**

```bash
grep -r "harvest\.sh" tests/ .claude/skills/ || echo "no references found"
```

Expected: `no references found` (or only the deleted file in `git status`).

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(harvest): delete retired harvest.sh"
```

---

## Task 7: Rewrite `dawn-harvest/SKILL.md`

**Files:**
- Modify: `.claude/skills/dawn-harvest/SKILL.md`

The new SKILL.md drives the five-step interactive agent workflow. It replaces all references to `harvest.sh` with the new two-script architecture. It instructs the agent to use `AskUserQuestion` for confirmation.

- [ ] **Step 1: Rewrite the file**

```markdown
---
name: dawn-harvest
description: Lift a generic, reusable change from staging up into the customizations (L1) layer. Use when the user says harvest, this should be generic, move to customizations, or make this upstreamable.
---

## Overview

`dawn-harvest` analyses changes between `staging` and `customizations`, groups related files into
proposed feature commits, classifies each as L1 (generic) or L2 (store-specific), confirms with
the operator via `AskUserQuestion`, then commits each group atomically into `customizations` and
rebases `staging`.

`customizations` holds **both L1 and L2 commits** distinguished by their prefix (`L1:` / `L2:`)
and `Inert:` trailer. See `../_dawn-ops-lib/conventions.md` for the full layer model.

## Prerequisites

- Run from the `ops` branch (or any branch that is not `current`) with a clean working tree.
- `staging` and `customizations` must exist locally.

## Step 1 — Run analysis

```bash
source .claude/skills/_dawn-ops-lib/dawn-ops.sh
dawn::harvest_candidates
```

If output is empty: report "nothing to harvest — staging and customizations are in sync" and stop.

## Step 2 — Group files into proposed commits

Using the candidate list from Step 1, group files by semantic relationship:

- **Locale grouping:** a section file (e.g. `sections/withdrawal.liquid`) groups with locale keys
  whose top-level namespace matches the section handle — detected by scanning locale JSON files in
  the candidate list for top-level keys prefixed with the section handle (e.g. `withdrawal`).
- **Asset grouping:** a section file groups with assets it directly references via `{{ '...' | asset_url }}` — detected by scanning the section's content on `staging`.
- **Template grouping:** a suffix template (e.g. `templates/product.soap.json`) groups with snippets
  or sections it exclusively references that also appear in the candidate list.
- **Independent files:** any file with no detected relationship to others is proposed as its own
  single-file commit.

**Do not use staging commit history for grouping.** The diff is the net effect of all staging work.

For each proposed group:
1. Apply the **stranger test** to confirm or override the `l1l2-hint`: L1 = a stranger could drop
   this onto any Dawn fork unchanged; L2 = store-specific (branding, metafields, app IDs, copy).
   When in doubt → L2.
2. Draft a commit message: `L1: <description>` or `L2: <description>`.
3. Set the `Inert:` trailer based on the classifier verdict for the group's files (`inert` →
   `Inert: yes`; `active` → `Inert: no`; `needs_judgment` → `Inert: needs_judgment`). If files
   within a group have mixed verdicts, use the most conservative: `active` beats `inert`;
   `needs_judgment` beats both.

## Step 3 — Detect and plan hunk splits

For any file where the diff contains **both** generic (L1) and store-specific (L2) content:

- If the hunks are cleanly separated (non-interleaved): propose splitting the file into two
  commits — an L1 commit with the generic portion, an L2 commit with the remainder. Write the
  L1-only content to a temp file and pass it via `--l1-content` to `harvest-commit.sh`.
- If the hunks interleave: flag the file as requiring manual separation and **skip it**, reporting
  exactly which lines need to be disentangled before it can be harvested.

## Step 4 — Confirm via AskUserQuestion

Call `AskUserQuestion` once per proposed commit (in dependency order: if a section is L1 and
its template is L2, the section comes first). Each question must show:

- Proposed commit message (including `Inert:` trailer)
- File list with per-file classifier verdict
- L1 or L2 classification with one-sentence reasoning

Options: **Approve** / **Change to L1** / **Change to L2** / **Skip** / **Edit message**

Process **all answers** before executing any commits. If "Edit message" is chosen, ask a
follow-up open-text question for the replacement message.

## Step 5 — Execute in order

For each approved group, call:

```bash
bash .claude/skills/dawn-harvest/harvest-commit.sh \
  --message "<full commit message with Inert: trailer>" \
  --files <file1> [file2 ...] \
  [--l1-content <file>:<tmppath>]   # only for hunk-split overrides
```

After all groups: show the final `git log --oneline customizations` and confirm `staging`'s tip is
still the config-snapshot commit.

## Exit codes

| Code | Meaning | Agent action |
|------|---------|--------------|
| 0 (`DAWN_OK`) | Success | Confirm commit landed on `customizations` and `staging` tip is config snapshot. |
| 10 (`DAWN_GUARD`) | Guard tripped | Report the reason (config file; dirty tree; wrong branch). Do not retry without resolving. |
| 21 (`DAWN_STOP_JUDGMENT`) | Needs human judgment | A rebase conflict occurred. You are left on `staging` with a rebase in progress. Resolve with the user, then `git rebase --continue`, or `git rebase --abort` to back out. |
```

- [ ] **Step 2: Verify the file was written correctly**

```bash
head -5 .claude/skills/dawn-harvest/SKILL.md
```

Expected: the `---` frontmatter lines and `name: dawn-harvest`.

- [ ] **Step 3: Run the full test suite to confirm nothing broke**

```bash
bash tests/run-all.sh
```

Expected: all suites pass.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/dawn-harvest/SKILL.md
git commit -m "feat(harvest): rewrite SKILL.md for interactive agent workflow"
```

---

## Task 8: Update `conventions.md` — branch model and L1/L2 sections

**Files:**
- Modify: `.claude/skills/_dawn-ops-lib/conventions.md`

Two sections need updating:

**§1 Branch model** — the diagram and bullets currently say `customizations` holds "L1 generic features only". Change to "L1 + L2 commits".

**§5 L1 vs L2 classification** — the final paragraph ("When in doubt → L2") is fine; add a sentence clarifying that both L1 and L2 commits live in `customizations`, distinguished by their prefix and `Inert:` trailer.

- [ ] **Step 1: Update §1 branch model diagram and bullet**

In `.claude/skills/_dawn-ops-lib/conventions.md`, find:

```
  └─ customizations   + L1 generic features — upstream-shaped, rebases onto new Dawn
```

Replace with:

```
  └─ customizations   + L1 generic features and L2 store-specific enrichments — both as discrete classified commits; rebases onto new Dawn
```

Find:

```
- `customizations` → L1 generic changes only; rebased onto `dawn-vanilla` on Dawn upgrades.
```

Replace with:

```
- `customizations` → L1 generic changes **and** L2 store-specific enrichments, each as a discrete classified commit (prefix `L1:` / `L2:`, `Inert:` trailer); rebased onto `dawn-vanilla` on Dawn upgrades.
```

- [ ] **Step 2: Update §5 L1 vs L2 — add clarifying sentence**

Find the end of §5 (after "When in doubt → L2. It is always safe..."):

```
**When in doubt → L2.** It is always safe to keep something in L2; incorrectly lifting L2 into L1
poisons `customizations` for future Dawn upgrades.
```

Replace with:

```
**When in doubt → L2.** It is always safe to keep something in L2; incorrectly lifting L2 into L1
poisons `customizations` for future Dawn upgrades.

Both L1 and L2 commits live in `customizations`, distinguished by their commit message prefix
(`L1:` / `L2:`) and the `Inert:` trailer set by `dawn::harvest_candidates` and the agent.
```

- [ ] **Step 3: Verify file reads cleanly**

```bash
grep -n "L1\|L2\|customizations" .claude/skills/_dawn-ops-lib/conventions.md | head -20
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/_dawn-ops-lib/conventions.md
git commit -m "docs(conventions): reflect L1+L2 in customizations (branch model + classification)"
```

---

## Task 9: Update `dawn-upgrade/SKILL.md` — L2 rebase conflict note

**Files:**
- Modify: `.claude/skills/dawn-upgrade/SKILL.md`

Add a note that with L2 commits now in `customizations`, rebase conflicts during `dawn-upgrade` are expected for store-specific code and require manual review.

- [ ] **Step 1: Read the existing rebase/conflict section**

```bash
grep -n "rebase\|conflict\|L2\|customizations" .claude/skills/dawn-upgrade/SKILL.md
```

- [ ] **Step 2: Add the L2 conflict note**

After the existing step that says "Rebases `customizations` onto `dawn-vanilla`" (or the equivalent conflict-handling paragraph), add:

```
> **L2 rebase conflicts are expected.** `customizations` now holds both L1 and L2 commits.
> L2 commits by definition reference store-specific code (metafields, branding, app IDs) that
> may conflict with upstream Dawn changes. Each L2 conflict needs manual review — this is correct
> behaviour, not an error. Resolve each conflict by verifying the store-specific dependency still
> holds in the new Dawn version, then `git rebase --continue`.
```

Place this note immediately before or after the existing conflict-handling instruction in the upgrade skill.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/dawn-upgrade/SKILL.md
git commit -m "docs(upgrade): note L2 rebase conflicts are expected after harvest redesign"
```

---

## Task 10: Update `dawn-dev-and-release.md` runbook — harvest section

**Files:**
- Modify: `docs/superpowers/runbook/dawn-dev-and-release.md`

The runbook's "Harvest generic pieces" section still references `harvest.sh` and describes a per-file flow. Update it to describe the interactive agent flow.

- [ ] **Step 1: Find the harvest section**

```bash
grep -n "harvest\|harvest\.sh" docs/superpowers/runbook/dawn-dev-and-release.md
```

- [ ] **Step 2: Rewrite the harvest section**

Find the existing harvest section (around lines 44-55 based on the earlier read). Replace:

```markdown
### 2. Harvest generic pieces

When a change is **generic** (passes the "stranger test" — any Dawn merchant could use it unchanged), lift it into `customizations`:

```bash
# From ops branch, with a clean working tree:
bash .claude/skills/dawn-harvest/harvest.sh sections/withdrawal.liquid
```

Harvest produces an atomic commit with an `Inert: yes/no` trailer. If a file mixes generic and store-specific lines, use `--hunks` to split first.
```

With:

```markdown
### 2. Harvest pieces to `customizations`

`dawn-harvest` analyses all differences between `staging` and `customizations`, groups related
files (section + locale strings + assets) into proposed commits, and prompts you to classify each
as L1 (generic) or L2 (store-specific) before committing.

Run it from `ops` with a clean working tree:

```
# Just invoke the skill — the agent drives the rest interactively.
dawn-harvest
```

- The agent runs `dawn::harvest_candidates` to classify candidates, then proposes groupings.
- You confirm (or adjust) each proposed commit via `AskUserQuestion` before anything is written.
- Both L1 and L2 commits land in `customizations` with an `Inert:` trailer. L2 commits produce
  expected rebase conflicts during `dawn-upgrade` — each one requires manual review.
- Files that mix generic and store-specific hunks are flagged for manual separation before harvest.
```

- [ ] **Step 3: Update the skill-reference table**

Find the table row for `dawn-harvest`:

```
| `dawn-harvest` | Lifts a generic file from `staging` into `customizations` as an atomic, classified L1 commit | After finishing a reusable feature on staging |
```

Replace with:

```
| `dawn-harvest` | Analyses staging vs customizations, groups files into proposed L1/L2 commits, confirms interactively, then commits each group atomically into `customizations` and rebases `staging` | After finishing features on staging |
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/runbook/dawn-dev-and-release.md
git commit -m "docs(runbook): update harvest section for interactive agent workflow"
```

---

## Task 11: Run the full test suite

This is a final sanity check before the usage task.

- [ ] **Step 1: Run all tests**

```bash
bash tests/run-all.sh
```

Expected output ends with `0 failed` for every suite. If any suite fails, fix it before proceeding.

- [ ] **Step 2: Verify `harvest-commit.sh` is executable and `harvest.sh` is gone**

```bash
ls -la .claude/skills/dawn-harvest/
```

Expected: `harvest-commit.sh` present and executable (`-rwxr-xr-x`); `harvest.sh` absent.

---

## Task 12: Usage — run `dawn-harvest` to split the monolithic L2 commit

> **This is a usage task, not a code task.** It produces the correct atomic history as its output.

The current `staging` branch has a single fat commit `6e3a16ad` containing 9 files:
- Custom product templates (soap, workshop, etc.)
- Store finder section/template
- GTM integration
- Withdrawal page

These are all L2 (store-specific). The goal is to run `dawn-harvest` interactively and split this
into atomic classified `L2:` commits in `customizations`, each independently shippable via `dawn-ship`.

- [ ] **Step 1: Check out `ops` and confirm clean working tree**

```bash
git checkout ops
git status
```

Expected: `nothing to commit, working tree clean`

- [ ] **Step 2: Invoke the `dawn-harvest` skill**

Launch Claude Code (or ask the agent) to run the `dawn-harvest` skill. The agent will:
1. Run `dawn::harvest_candidates` on the repo
2. Inspect staging commit `6e3a16ad` — 9 files, all L2 (zogezeept-specific content)
3. Group files: store-finder (section + template), withdrawal (section + template + locale),
   GTM (layout or snippet), custom product templates (each as its own commit or grouped by type)
4. Propose L2 commits with appropriate `Inert:` trailers (suffix templates → `needs_judgment`)
5. Confirm each via `AskUserQuestion`
6. Call `harvest-commit.sh` for each approved group

- [ ] **Step 3: After the skill completes, verify the result**

```bash
git log --oneline customizations
```

Expected: multiple atomic `L2:` commits, each covering one feature (store-finder, withdrawal,
GTM, product templates), with `Inert:` trailers visible in the full log:

```bash
git log --format="%s%n%b" customizations | grep -E "^L[12]:|^Inert:"
```

- [ ] **Step 4: Confirm `staging` tip is still the config snapshot**

```bash
git log -1 --format=%s staging
```

Expected: a message containing "config" or "snapshot".

- [ ] **Step 5: Confirm `dawn-ship` can reference the new commits**

```bash
# Each new customizations commit should be classifiable
git log --oneline customizations | grep "^" | head -10
```

Verify that `dawn-ship` is unblocked by checking that at least one commit has `Inert: yes` (can
be shipped without smoke test):

```bash
git log --format="%B" customizations | grep "^Inert:" | head -10
```

---

## Self-review

**Spec coverage check:**

| Spec section | Covered by |
|---|---|
| §1 Model change: customizations holds L1+L2 | Tasks 8, 9, 10 |
| §2 Problem with current skill | Task 6 (retire harvest.sh) |
| §3 Architecture (3-layer) | Tasks 1, 4, 7 |
| §4 `dawn::harvest_candidates` | Tasks 1, 2, 3 |
| §5 SKILL.md 5-step workflow | Task 7 |
| §5 Step 1 empty-output case | Task 7 (SKILL.md) |
| §5 Step 2 grouping rules | Task 7 |
| §5 Step 3 hunk split detection | Task 7 |
| §5 Step 4 AskUserQuestion | Task 7 |
| §5 Step 5 execute in order | Task 7 |
| §6 harvest-commit.sh | Tasks 4, 5 |
| §7 Retroactive L2 split | Task 12 |
| §8 Components affected | All tasks |
| §9 test_harvest_candidates | Tasks 2, 3 |
| §9 test_harvest (rewritten) | Task 5 |
| §10 Success criteria | Tasks 11, 12 |

**Placeholder scan:** No TBD, TODO, or "similar to Task N" references found. All steps include concrete commands and expected output.

**Type/name consistency:** `dawn::harvest_candidates` named consistently in Tasks 1, 2, 3, 7. `harvest-commit.sh` named consistently in Tasks 4, 5, 6, 7. `--l1-content` flag named consistently in Tasks 4, 5, 7.
