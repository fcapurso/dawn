# EU Right of Withdrawal Compliance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Zogezeept compliant with the EU "withdrawal button" obligation (Dir. (EU) 2023/2673, in force 19 Jun 2026) and CRD pre-contractual disclosure, at zero recurring cost, with partial/mixed-order support and no manual order re-keying.

**Architecture:** Offload the mandatory two-step withdrawal button to a free, order-integrated app (Retractly) for physical goods; exclude fixed-date workshops via native Shopify return rules; add a single locale-keyed L1 theme snippet for per-product pre-contractual notices; carry the legal text in native Policies + Translate & Adapt + the order-confirmation email.

**Tech Stack:** Shopify admin (return rules, Policies, Translate & Adapt, notification emails), Retractly app (free tier), Dawn theme Liquid (L1 snippet + `locales/*.json`), `theme-check`, Shopify CLI theme preview.

**Source spec:** [docs/superpowers/specs/2026-06-19-eu-right-of-withdrawal-compliance-design.md](../specs/2026-06-19-eu-right-of-withdrawal-compliance-design.md)

> **Disclaimer:** Not legal advice. All policy text in Phase 3 must be reviewed by counsel before go-live.

---

## Layer-ops workflow (how this lands safely)

Per `.claude/skills/_dawn-ops-lib/conventions.md`:

- **`current` is the LIVE storefront — never edited by hand.** It changes only via Shopify
  auto-commits or the gated `dawn-promote`.
- **Preview is via the Shopify ↔ GitHub integration.** The non-live preview theme tracks the
  `staging` branch: pushing commits to `staging` (`git push origin staging`) auto-updates the
  preview theme. We do **not** use `shopify theme push` / `shopify theme dev`.
- **Theme work is developed on a scratch branch off `staging`**, then landed on `staging` to
  preview on the linked theme — *never* on current.
- The theme changes here (`withdrawal-notice.liquid`, the `withdrawal` locale strings, and the
  `main-product.liquid` render) are **generic L1**: once validated they are lifted into
  `customizations` via **`dawn-harvest`**, then `staging` is rebuilt, then `dawn-promote`
  publishes `staging` → `current` with explicit live confirmation.
- **Shop-level admin config** (app install, metafield *definition + values*, return rules,
  Policies, model-form page, order email, translations) is **not theme code** — it is set in the
  Shopify admin and affects the shop directly. Where it must be visible/tested without going
  live, use draft/unpublished states (unpublished page, test orders).

**Dev → preview → promote sequence:**
1. Develop on the scratch branch off `staging` (done: `feat/withdrawal-notice`).
2. Land the change on `staging` and `git push origin staging` → preview theme auto-updates.
3. **Validate on the preview theme** (NL/EN render; needs the Task 4 metafields set first).
4. `dawn-harvest` — lift the generic snippet + locales + section render into `customizations` (L1).
5. Rebuild `staging` on top of `customizations` (config snapshot stays at the tip); push again.
6. `dawn-promote` — publish `staging` → `current` (gated; you confirm live).

## Ownership & validation (who does what)

| Task | Who executes | Who validates |
|---|---|---|
| 1 App free-tier gate | **You** (install/inspect) | You confirm the 5 requirements; report back |
| 2 Button wording/placement | **You** (app + theme app block) | You (incognito flow + ack email) |
| 3 Return rules | **You** (admin) | You (test workshop vs soap order) |
| 4 Metafield definition + values | **You** (admin) | You (spot-check 2 products) |
| 5 Locale strings | **Claude** | Claude (JSON lint) |
| 6 Snippet | **Claude** | Claude (`shopify theme check`) |
| 7 Render in section + preview | **Claude** writes; **you** preview | **You** (NL/EN render on test theme — needs your Task 4 metafields) |
| 8 Model form / withdrawal page | **You** (admin pages) | You |
| 9 Policies + order email | **You** (admin) | You (test order email) |
| 10 Translation pass | **You** (Translate & Adapt) | You |
| 11 E2E walkthrough | **You** (live-ish test orders) | You |
| Harvest + promote | **Claude** runs skills; **you** confirm live | You (final live check) |

> Phases 1, 3, 4 are Shopify-admin actions only you can perform. Claude executes **Phase 2**
> (the theme code) and drives the harvest/promote skills (you confirm the live step).

---

## File structure

| File | Responsibility | Phase |
|---|---|---|
| `snippets/withdrawal-notice.liquid` (create) | Render the correct pre-contractual withdrawal notice per product, driven by a metafield; locale-keyed | 2 |
| `sections/main-product.liquid` (modify) | Render the snippet after the buy-buttons block | 2 |
| `locales/en.default.json` (modify) | EN strings under a new `withdrawal` namespace | 2 |
| `locales/nl.json` (modify) | NL strings under the `withdrawal` namespace | 2 |
| Shopify admin (no repo file) | App install, return rules, button placement, Policies, model form page, order email, translations | 1, 3 |

**Metafield contract (defined once, used everywhere):**
- Namespace/key: `custom.withdrawal_policy` — type **single-line text** (acts as enum)
- Allowed values: `fixed_date_service` (workshop, goodwill 7-day), `fixed_date_service_strict` (workshop, non-refundable), `standard_goods` (14-day + diminished value)
- Absent/blank → snippet renders nothing (safe default; e.g. 3rd-party products until classified)

---

## Phase 1 — Shopify admin & app (no code)

> This phase is configuration in the Shopify admin. "Verify" steps are manual UI checks. No commits.

### Task 1: Verify Retractly free tier covers the hard requirements (BLOCKING GATE)

**Files:** none (admin / app store)

- [ ] **Step 1: Install Retractly — EU Withdrawal on the free plan**

Go to https://apps.shopify.com/revoka → Install → select the **Free** plan. Do **not** start a paid trial.

- [ ] **Step 2: Confirm each hard requirement is present on the free tier**

Check, in the app admin, that ALL of the following are available without upgrading:
1. Customer-facing **two-step** withdrawal flow reachable **without login**.
2. **Automatic acknowledgement email** to the customer on submission (durable medium).
3. **Partial withdrawal** — customer can select specific line items.
4. **Order matching/validation** against Shopify orders + 14-day deadline validation.
5. **Refund write-back** to the Shopify order (one-click refund / restock).

Expected: all 5 present on Free. Record findings in a comment on this task.

- [ ] **Step 3: Decision gate**

If all 5 are present → proceed.
If any required item (1–4, refund nice-to-have) is paywalled → STOP and escalate: re-evaluate Revoq (https://apps.shopify.com/eu-withdrawal-form) or trigger the custom-form fallback (out of scope for this plan; needs a new spec). Do not proceed to Task 2 with a non-compliant free tier.

### Task 2: Configure the withdrawal button wording & placement

**Files:** none (app settings + theme editor app block)

- [ ] **Step 1: Set the button label**

In the app settings, set the button/link label to NL **"Herroep hier uw contract"** and EN **"Withdraw from contract here"** (use the app's per-language fields).

- [ ] **Step 2: Place the entry points**

Enable the withdrawal entry point in: (a) the site **footer** (app block or a footer link to the app's withdrawal page), (b) the **order-confirmation email** (Task 9 adds the link), and (c) the **customer account / order page** if the app offers it.

- [ ] **Step 3: Verify availability without login**

In an incognito window, open the footer link → confirm the two-step flow loads and accepts an order number + email without requiring login. Submit a test withdrawal on a test order → confirm the acknowledgement email arrives.

Expected: flow reachable logged-out; acknowledgement email received.

### Task 3: Configure native Shopify return & cancellation rules

**Files:** none (Settings → Returns / Policies → Return rules)

- [ ] **Step 1: Set the default return window**

Settings → Policies → Return rules → set return window to **14 days** for the shop default.

- [ ] **Step 2: Mark workshops as Final Sale / non-returnable**

Add a return rule exception making the **workshop** product(s) (and any future workshop collection) **Final Sale** so they cannot be returned/cancelled via the native flow.

- [ ] **Step 3: Verify exclusion**

On a test workshop order, confirm the native self-serve returns UI shows the workshop line as non-returnable. On a test soap order, confirm the soap line is returnable within 14 days.

Expected: workshops excluded; physical goods eligible.

### Task 4: Set the product `custom.withdrawal_policy` metafield definition + values

**Files:** none (Settings → Custom data → Products)

- [ ] **Step 1: Create the metafield definition**

Settings → Custom data → Products → Add definition: namespace.key **`custom.withdrawal_policy`**, name "Withdrawal policy", type **Single line text**. (Optionally restrict to a list of choices: `fixed_date_service`, `fixed_date_service_strict`, `standard_goods`.)

- [ ] **Step 2: Assign values to products**

Set: all **soap / badzout / facialmask / geurblokje** physical products → `standard_goods`; **workshop** product(s) → `fixed_date_service` (goodwill default). Leave 3rd-party products blank until classified.

- [ ] **Step 3: Verify**

Open a soap product and a workshop product in admin → confirm the metafield value is set as above.

Expected: values present; the Phase-2 snippet will read them.

---

## Phase 2 — Theme L1: pre-contractual notice snippet

> Verification here uses `theme-check` (lint) + Shopify CLI preview render, since the repo has no Liquid unit-test harness. Commit after each task.

### Task 5: Add the `withdrawal` locale strings (EN + NL)

**Files:**
- Modify: `locales/en.default.json`
- Modify: `locales/nl.json`

- [ ] **Step 1: Add the EN namespace**

In `locales/en.default.json`, add a top-level `"withdrawal"` object (alongside existing keys like `"products"`):

```json
  "withdrawal": {
    "fixed_date_heading": "Cancellation policy",
    "fixed_date_goodwill_html": "This is a fixed-date leisure activity. The statutory 14-day right of withdrawal does not apply (EU Consumer Rights Directive, Art. 16(l)). As a courtesy, you may cancel up to 7 days before the workshop for a full refund; after that, bookings are non-refundable.",
    "fixed_date_strict_html": "This is a fixed-date leisure activity. The statutory 14-day right of withdrawal does not apply (EU Consumer Rights Directive, Art. 16(l)). All bookings are final and non-refundable.",
    "standard_heading": "Right of withdrawal",
    "standard_body_html": "You have the right to withdraw from this purchase within 14 days without giving any reason. Used items that can no longer be sold may have their refund reduced to reflect the loss in value.",
    "standard_link_label": "Withdraw from contract here"
  },
```

- [ ] **Step 2: Add the NL namespace**

In `locales/nl.json`, add the matching `"withdrawal"` object:

```json
  "withdrawal": {
    "fixed_date_heading": "Annuleringsbeleid",
    "fixed_date_goodwill_html": "Dit is een vrijetijdsactiviteit op een vaste datum. Het wettelijke herroepingsrecht van 14 dagen is niet van toepassing (EU-richtlijn consumentenrechten, art. 16(l)). Als tegemoetkoming kunt u tot 7 dagen vóór de workshop kosteloos annuleren; daarna zijn boekingen niet-restitueerbaar.",
    "fixed_date_strict_html": "Dit is een vrijetijdsactiviteit op een vaste datum. Het wettelijke herroepingsrecht van 14 dagen is niet van toepassing (EU-richtlijn consumentenrechten, art. 16(l)). Alle boekingen zijn definitief en niet-restitueerbaar.",
    "standard_heading": "Herroepingsrecht",
    "standard_body_html": "U hebt het recht om binnen 14 dagen zonder opgave van redenen deze aankoop te herroepen. Voor gebruikte artikelen die niet meer verkocht kunnen worden, kan de terugbetaling worden verminderd met het waardeverlies.",
    "standard_link_label": "Herroep hier uw contract"
  },
```

- [ ] **Step 3: Validate JSON**

Run: `python3 -m json.tool locales/en.default.json > /dev/null && python3 -m json.tool locales/nl.json > /dev/null && echo OK`
Expected: `OK` (no JSON syntax errors).

- [ ] **Step 4: Commit**

```bash
git add locales/en.default.json locales/nl.json
git commit -m "feat(i18n): add withdrawal notice strings (EN/NL)"
```

### Task 6: Create the `withdrawal-notice.liquid` snippet

**Files:**
- Create: `snippets/withdrawal-notice.liquid`

- [ ] **Step 1: Write the snippet**

Create `snippets/withdrawal-notice.liquid` with:

```liquid
{%- comment -%}
  Renders the pre-contractual right-of-withdrawal notice for a product,
  driven by the product metafield custom.withdrawal_policy.
  Accepts: product (required), withdrawal_url (optional, link to the app's withdrawal page)
  Values: fixed_date_service | fixed_date_service_strict | standard_goods
  Blank/absent -> renders nothing.
{%- endcomment -%}
{%- assign policy = product.metafields.custom.withdrawal_policy.value -%}
{%- if policy != blank -%}
  <div class="withdrawal-notice" data-withdrawal-policy="{{ policy }}">
    {%- if policy == 'fixed_date_service' or policy == 'fixed_date_service_strict' -%}
      <h2 class="withdrawal-notice__heading">{{ 'withdrawal.fixed_date_heading' | t }}</h2>
      <p class="withdrawal-notice__body rte">
        {%- if policy == 'fixed_date_service_strict' -%}
          {{ 'withdrawal.fixed_date_strict_html' | t }}
        {%- else -%}
          {{ 'withdrawal.fixed_date_goodwill_html' | t }}
        {%- endif -%}
      </p>
    {%- elsif policy == 'standard_goods' -%}
      <h2 class="withdrawal-notice__heading">{{ 'withdrawal.standard_heading' | t }}</h2>
      <p class="withdrawal-notice__body rte">{{ 'withdrawal.standard_body_html' | t }}</p>
      {%- if withdrawal_url != blank -%}
        <p class="withdrawal-notice__link">
          <a href="{{ withdrawal_url }}">{{ 'withdrawal.standard_link_label' | t }}</a>
        </p>
      {%- endif -%}
    {%- endif -%}
  </div>
{%- endif -%}
```

- [ ] **Step 2: Lint the snippet**

Run: `shopify theme check snippets/withdrawal-notice.liquid` (or `theme-check snippets/withdrawal-notice.liquid` if the standalone binary is installed).
Expected: no errors for the new file (pre-existing repo offenses unrelated to this file are acceptable).

- [ ] **Step 3: Commit**

```bash
git add snippets/withdrawal-notice.liquid
git commit -m "feat(theme): add withdrawal-notice snippet (metafield-driven, L1)"
```

### Task 7: Render the snippet on the product page

**Files:**
- Modify: `sections/main-product.liquid` (after the buy-buttons render, ~line 478-485)

- [ ] **Step 1: Locate the buy-buttons render**

Run: `grep -n "render 'buy-buttons'" sections/main-product.liquid`
Expected: one match around line 478. Find the closing `%}` / `-%}` of that `render` tag and the end of its enclosing block.

- [ ] **Step 2: Insert the snippet render after the buy-buttons block**

Immediately after the `{%- render 'buy-buttons', ... -%}` tag closes, add:

```liquid
                {%- render 'withdrawal-notice', product: product, withdrawal_url: settings.withdrawal_page_url -%}
```

If `settings.withdrawal_page_url` is not a defined theme setting, instead pass the app's withdrawal page path directly, e.g.:

```liquid
                {%- render 'withdrawal-notice', product: product, withdrawal_url: routes.root_url | append: 'pages/herroeping' -%}
```

Use whichever matches the actual app withdrawal page slug created in Phase 3 (Task 8). Keep one form only.

- [ ] **Step 3: Lint**

Run: `shopify theme check sections/main-product.liquid`
Expected: no new errors introduced by the added line.

- [ ] **Step 4: Preview render — physical good**

Preview is via the **Shopify ↔ GitHub integration**: the non-live preview theme tracks the
`staging` branch. To preview, land these commits on `staging` and push:
`git push origin staging` → the linked preview theme auto-updates (no `shopify theme push`).
Then open a **soap** product page in NL and EN on the preview theme.
Expected: the "Herroepingsrecht / Right of withdrawal" notice appears with the 14-day + diminished-value text and the withdrawal link.

- [ ] **Step 5: Preview render — workshop**

Open a **workshop** product page in NL and EN.
Expected: the "Annuleringsbeleid / Cancellation policy" notice appears with the goodwill 7-day text and **no** withdrawal link.

- [ ] **Step 6: Preview render — unclassified product**

Open a product with a blank `custom.withdrawal_policy`.
Expected: no notice block renders.

- [ ] **Step 7: Commit**

```bash
git add sections/main-product.liquid
git commit -m "feat(theme): render withdrawal-notice on product page"
```

---

## Phase 3 — Legal artifacts & bilingual text (admin + counsel)

> Configuration + content. Draft text in repo for review, publish in admin. The drafts below are starting points for counsel, not final.

### Task 8: Publish the model withdrawal form & withdrawal page

**Files:** none (Online Store → Pages)

- [ ] **Step 1: Create the withdrawal page**

Create a page with handle **`herroeping`** (NL) / its EN translation, containing the **model withdrawal form** text (CRD Annex I(B)) and a clear pointer/link to the app's two-step withdrawal flow.

- [ ] **Step 2: Align the theme link**

Ensure the slug used here matches `withdrawal_url` passed in Task 7, Step 2. Adjust one or the other so they agree.

- [ ] **Step 3: Verify**

Open the page logged-out in NL and EN → confirm the model form text and the link to the withdrawal flow are present.

### Task 9: Update Policies and the order-confirmation email

**Files:** none (Settings → Policies; Settings → Notifications)

- [ ] **Step 1: Update the Refund/Return policy**

In Settings → Policies → Refund policy, add: the 14-day right of withdrawal for physical goods; the diminished-value clause for used items; the workshop Art. 16(l) exclusion + the goodwill 7-day cancellation terms; and a reference to the withdrawal button/page.

- [ ] **Step 2: Update Terms of Service**

Add matching withdrawal clauses (right, exceptions, how to exercise via the button) to the Terms of Service policy.

- [ ] **Step 3: Edit the order-confirmation email**

Settings → Notifications → Order confirmation: add a section with the withdrawal information and a **link to the withdrawal flow** (durable-medium confirmation).

- [ ] **Step 4: Verify**

Place a test order → confirm the order-confirmation email contains the withdrawal info + working link.

### Task 10: Bilingual translation pass

**Files:** none (Translate & Adapt app)

- [ ] **Step 1: Install Translate & Adapt (free) if not present**

- [ ] **Step 2: Translate the new artifacts**

Translate the withdrawal page, the Policies, and the order-confirmation email additions into NL and EN. (Theme snippet strings are already bilingual via `locales/`.)

- [ ] **Step 3: Verify**

Switch storefront locale NL↔EN and confirm the page, policies, and product notices all render in the selected language.

---

## Phase 4 — End-to-end verification

### Task 11: Compliance walkthrough against success criteria

**Files:** none

- [ ] **Step 1: Physical-goods withdrawal (full)**

Logged-out, from the footer link, withdraw a full soap order via the two-step flow → confirm acknowledgement email + refund written back to the Shopify order.

- [ ] **Step 2: Partial withdrawal**

On a multi-item soap order, withdraw **one** line item → confirm only that line is refunded and the order reflects it.

- [ ] **Step 3: Mixed order**

On a workshop+soap order, confirm the workshop line cannot be withdrawn (rejected/ineligible) while the soap line can.

- [ ] **Step 4: Disclosure-before-purchase**

Confirm both product types show the correct notice on the PDP (NL + EN) and that the order-confirmation email carries the withdrawal info.

- [ ] **Step 5: Record results**

Tick each success criterion in the spec (§8). Note any gaps for follow-up.

---

## Future enhancements (NOT in this plan — see spec §6)
- Acceptance/T&C **acknowledgment checkbox** at cart/checkout (stronger Art. 6(9) evidence; not legally required). Revisit after Phase 4.
- **Sealing** physical goods to rely on Art. 16(e) (refuse opened-goods returns outright).
- EU-wide locale expansion beyond NL/EN.

---

## Self-review notes
- **Spec coverage:** Layer 1→Tasks 1-2; Layer 2→Task 3; Layer 3→Tasks 4-7; Layer 4→Tasks 8-9; Layer 5→Tasks 9-10; success criteria→Task 11; future items carried to the bottom. ✓
- **Metafield naming** is consistent (`custom.withdrawal_policy`, values `fixed_date_service` / `fixed_date_service_strict` / `standard_goods`) across Tasks 4, 6, 7. ✓
- **Locale keys** used in Task 6 (`withdrawal.fixed_date_heading`, `fixed_date_goodwill_html`, `fixed_date_strict_html`, `standard_heading`, `standard_body_html`, `standard_link_label`) all defined in Task 5. ✓
- **Verification reality:** theme layer uses theme-check + preview (no Liquid unit harness in repo) — stated explicitly. ✓
