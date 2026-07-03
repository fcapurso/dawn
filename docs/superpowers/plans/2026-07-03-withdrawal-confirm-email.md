# Withdrawal Form — Confirmation Popup Repeats Email — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The withdrawal form's pre-submit confirmation popup repeats back the email address the
customer typed, in addition to the order number it already repeats, so a typo is visible before
the customer confirms.

**Architecture:** The popup body is a locale string (`withdrawal_form.confirm_body`) containing an
`[order]` token that `assets/withdrawal-form.js` substitutes at render time. Add a second `[email]`
token to the same string, and extend the same substitution code path to read the email input and
replace that token too. No Liquid template or CSS changes are needed — `data-confirm-body` already
passes the translated string through unchanged.

**Tech Stack:** Shopify Dawn theme — Liquid sections, JSON locale files, vanilla JS (no bundler, no
test runner). Verification is manual, via the Shopify theme preview.

**Branch:** All work happens directly on `staging` (linked to the Shopify preview theme — pushes
appear there immediately), per `docs/superpowers/runbook/dawn-dev-and-release.md` §1. This repo's
`ops` branch (where this plan lives) has no theme files; check out `staging` to do the actual edits.

---

### Task 1: Check out `staging` and confirm starting state

**Files:** none (setup only)

- [ ] **Step 1: Fetch and check out `staging`**

```bash
git fetch origin
git checkout staging
git reset --hard origin/staging
```

Expected: `HEAD is now at <sha> ...` with no local changes ahead of `origin/staging`.

- [ ] **Step 2: Confirm the two target files are at the expected starting content**

```bash
grep -n "confirm_body" locales/en.default.json locales/nl.json
grep -n "function openModal\|function tryOpen" assets/withdrawal-form.js
```

Expected `confirm_body` lines:
- `en.default.json`: `"confirm_body": "Confirm you want to withdraw order [order]?",`
- `nl.json`: `"confirm_body": "Bevestig dat je bestelling [order] wilt herroepen?",`

If either file differs from this, stop and re-sync with the current spec/plan before proceeding —
someone else may have changed the copy.

---

### Task 2: Add the `[email]` token to the confirmation copy (EN + NL)

**Files:**
- Modify: `locales/en.default.json`
- Modify: `locales/nl.json`

- [ ] **Step 1: Update `locales/en.default.json`**

Change the `withdrawal_form.confirm_body` value from:

```json
"confirm_body": "Confirm you want to withdraw order [order]?",
```

to:

```json
"confirm_body": "Confirm you want to withdraw order [order]? A confirmation will be sent to [email].",
```

- [ ] **Step 2: Update `locales/nl.json`**

Change the `withdrawal_form.confirm_body` value from:

```json
"confirm_body": "Bevestig dat je bestelling [order] wilt herroepen?",
```

to:

```json
"confirm_body": "Bevestig dat je bestelling [order] wilt herroepen? Een bevestiging wordt verstuurd naar [email].",
```

- [ ] **Step 3: Validate both files are still well-formed JSON**

```bash
python3 -m json.tool locales/en.default.json > /dev/null && echo EN_OK
python3 -m json.tool locales/nl.json > /dev/null && echo NL_OK
```

Expected: `EN_OK` and `NL_OK` printed, no JSON errors.

- [ ] **Step 4: Commit**

```bash
git add locales/en.default.json locales/nl.json
git commit -m "content: add email token to withdrawal confirm-popup copy (EN/NL)"
```

---

### Task 3: Substitute the `[email]` token in the confirmation script

**Files:**
- Modify: `assets/withdrawal-form.js:20-25` (`tryOpen`)
- Modify: `assets/withdrawal-form.js:37-41` (`openModal`)

- [ ] **Step 1: Update `tryOpen` to also read the email input and pass it through**

Current code:

```javascript
  function tryOpen() {
    if (honeypotFilled()) return;
    if (document.querySelector('.withdrawal-modal')) return; // already open
    if (form.reportValidity && !form.reportValidity()) return; // native required-field check
    var orderInput = form.querySelector('input[name="contact[Order number]"]');
    openModal(orderInput && orderInput.value ? orderInput.value : '');
  }
```

Replace with:

```javascript
  function tryOpen() {
    if (honeypotFilled()) return;
    if (document.querySelector('.withdrawal-modal')) return; // already open
    if (form.reportValidity && !form.reportValidity()) return; // native required-field check
    var orderInput = form.querySelector('input[name="contact[Order number]"]');
    var emailInput = form.querySelector('input[name="contact[email]"]');
    openModal(
      orderInput && orderInput.value ? orderInput.value : '',
      emailInput && emailInput.value ? emailInput.value : ''
    );
  }
```

- [ ] **Step 2: Update `openModal` to accept the email and substitute the new token**

Current code:

```javascript
  function openModal(order) {
    var bodyTpl = btn.getAttribute('data-confirm-body') || '';
    var orderText = order ? '#' + order.replace(/^#/, '') : '';
    var body = bodyTpl.replace('[order]', orderText);
```

Replace with:

```javascript
  function openModal(order, email) {
    var bodyTpl = btn.getAttribute('data-confirm-body') || '';
    var orderText = order ? '#' + order.replace(/^#/, '') : '';
    var body = bodyTpl.replace('[order]', orderText).replace('[email]', email || '');
```

(The rest of `openModal` — building `overlay.innerHTML` from `body`, wiring up `[data-ok]` /
`[data-cancel]`, focus handling — is unchanged. `body` already flows into `esc(body)` a few lines
down, so the substituted email is still HTML-escaped before insertion; no new XSS surface.)

- [ ] **Step 3: Commit**

```bash
git add assets/withdrawal-form.js
git commit -m "feat: repeat customer's email in the withdrawal confirm popup"
```

---

### Task 4: Manually verify on the Shopify preview theme

**Files:** none (verification only)

- [ ] **Step 1: Push `staging` so the preview theme picks up the change**

```bash
git push origin staging
```

Expected: push succeeds (no force needed — this is a plain fast-forward of two new commits).

- [ ] **Step 2: Open the withdrawal page in the Shopify theme editor preview**

Use the theme editor's preview (not a bare shareable `?preview_theme_id=` link — per
[[shopify-preview-post-forms]], the shareable link drops preview context on POST; the editor
preview keeps it). This flow doesn't submit anything though — the popup opens on the *pre-submit*
button click — so a shareable preview link works fine for this specific check too, since it never
reaches the POST step you're not testing here.

- [ ] **Step 3: Verify the English confirmation popup**

On the EN version of the page:
1. Fill in an order number, e.g. `1234`.
2. Fill in an email address, e.g. `jane@example.com`.
3. Click "Withdraw from contract here".

Expected popup body: `Confirm you want to withdraw order #1234? A confirmation will be sent to jane@example.com.`

Click "Go back" to close the popup without submitting.

- [ ] **Step 4: Verify the Dutch confirmation popup**

Switch to the NL version of the page, repeat with the same order number and email.

Expected popup body: `Bevestig dat je bestelling #1234 wilt herroepen? Een bevestiging wordt verstuurd naar jane@example.com.`

Click "Terug" to close the popup without submitting.

- [ ] **Step 5: Verify a malformed email never reaches the popup**

Type an invalid email (e.g. `not-an-email`, no `@`) into the email field, fill in the order number,
click "Withdraw from contract here" (EN) / "Herroep hier uw contract" (NL).

Expected: the browser's native inline validation bubble appears on the email field (e.g. "Please
include an '@' in the email address.") and the confirmation popup does **not** open. This confirms
the existing `type="email"` + `reportValidity()` gate (documented in the spec's out-of-scope
section) still works unchanged.

---

### Task 5: Next steps (not part of this plan)

This plan intentionally stops at a verified change on `staging`. Two follow-up actions are separate,
deliberate steps the user runs themselves when ready:

- **`dawn-harvest`** — classify these two commits (locale content + JS behavior) from `staging` into
  `customizations`. The JS/behavior commit is L1 (generic, reusable); the locale-copy commit is
  content and may be judged L1 or Config depending on how the harvest classifier treats copy-only
  locale changes — let the interactive harvest flow decide.
- **`dawn-promote`** — only after harvest, to make the change live on `current`.

Do not run either automatically as part of this plan.
