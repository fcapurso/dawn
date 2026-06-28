# EU Right of Withdrawal Compliance — Design

**Date:** 2026-06-19
**Shop:** Zogezeept (www.zogezeept.com) — Dawn theme + customizations (L0/L1/L2 layer model)
**Status:** Approved design, pending spec review → implementation plan

> **Disclaimer:** This document is informed input, not legal advice. The author is not
> a lawyer. All policy text and compliance conclusions below should be validated by
> qualified counsel before go-live.

## 1. Context & goal

The shop sells two materially different things:

- **Physical goods** — soap bars, bath salt (`badzout`), facial masks, scent blocks
  (`geurblokje`), plus 3rd-party products.
- **Workshops** — soap-making classes given at a **fixed date**.

We must bring the shop into compliance with EU distance-selling law, in particular the
**new "withdrawal button" obligation (Directive (EU) 2023/2673), in force from 19 June
2026**, while doing the **minimum work needed to be fully compliant and free**, and —
as added value — keeping refund handling integrated with Shopify order management
(no manual re-keying) and supporting **partial / line-item withdrawals**.

### Jurisdiction
EU. Currently selling to **Belgium + Netherlands** (bilingual NL/EN), with possible
EU-wide expansion later. BE and NL transpose the same directives, so the substance is
uniform; only translation scales.

## 2. Legal basis (summary)

| Topic | Provision | Consequence for us |
|---|---|---|
| Standard right of withdrawal | CRD 2011/83/EU Art. 9 | 14-day cooling-off for physical goods |
| Diminished value | CRD Art. 14(2) | May deduct lost value of **used** goods from the refund, if the consumer was informed of the withdrawal right |
| Hygiene-sealed goods | CRD Art. 16(e) | Only usable if goods are **sealed**; we do **not** seal → not relied upon in phase 1 |
| Fixed-date leisure services | CRD Art. 16(l) | Workshops have **no statutory right of withdrawal**; standalone exemption, **no consent/acknowledgment required** |
| Pre-contractual information | CRD Art. 6 + Art. 6(9) | Must **provide/make available** info clearly before purchase; **burden of proof is on the trader**. No checkbox required. |
| Paid-order button label | CRD Art. 8(2) | Order button must read as a paid order — **Shopify checkout already complies** |
| **Withdrawal button** | **Dir. (EU) 2023/2673** | Where a statutory withdrawal right exists, must offer a **two-step electronic withdrawal function** + acknowledgement on a durable medium, from 19 June 2026 |

### Withdrawal-button requirements (2023/2673)
- **Step 1:** prominent, clearly-labelled button — *"Withdraw from contract here"* /
  NL *"Herroep hier uw contract"* — **available throughout the 14-day period**,
  **accessible without login**.
- **Withdrawal page:** consumer supplies info to identify themselves + the contract
  (order number, contact details, the items) — a pre-filled-but-editable form.
- **Step 2:** confirmation page showing order/contract details, purchase date, and a
  description of the goods/services, with a final **confirm** button.
- **After confirmation:** **automatic acknowledgement of receipt on a durable medium**
  (email), without undue delay.
- **Forbidden:** routing the consumer through customer service, surveys, or retention
  offers before processing.

### Exemption logic maps cleanly to our catalogue
| Product | Statutory withdrawal right? | Button required? |
|---|---|---|
| **Workshops** (Art. 16(l)) | No | **No** — disclosure only |
| **Physical goods** (14-day) | Yes | **Yes — mandatory** |

## 3. Policy decisions (locked)

1. **Operations:** manual handling. No date-gated self-service automation beyond what a
   free app provides; merchant approves/rejects and refunds.
2. **Workshops:** default to a **goodwill** policy — *no statutory withdrawal right
   applies; as a courtesy, cancellation is allowed up to **7 days** before the workshop
   for a full refund; thereafter non-refundable.* A **strict** alternative (all bookings
   final, non-refundable) is **also fully compliant** and shipped as ready-to-swap text.
3. **Physical goods:** standard **14-day** withdrawal **+ diminished-value deductions**
   for used/unsaleable items (Path B). Sealing goods to invoke Art. 16(e) is a documented
   **future improvement**, not phase 1.
4. **No checkout gate / acceptance checkbox** in phase 1. A clear **notice** is legally
   sufficient. (See §6 — checkbox is a documented future enhancement.)

## 4. Architecture (5 layers)

### Layer 1 — Mandatory withdrawal button → free third-party app
- **Candidate: Retractly — EU Withdrawal (free plan).** Provides the compliant no-login
  two-step button + form, automatic acknowledgement email (durable medium), **partial /
  line-item selection**, automatic deadline & order validation matched against Shopify
  orders, and **approve/reject + one-click refund with auto-restock written back to the
  order** (no manual sync). Multi-language incl. NL.
- **Hard gate before adoption:** a hands-on install must confirm the **free tier** still
  includes: two-step no-login flow, acknowledgement email, partial selection, order
  matching, and refund write-back. If the free tier no longer covers these, re-evaluate
  alternatives (e.g. Revoq) or fall back to a custom theme form (§7 risk).
- **Button placement** (per directive): site **footer**, **order-confirmation email**,
  and **customer account / order page**.

### Layer 2 — Native Shopify return & cancellation rules (free, native)
- Set the **14-day** return window for physical goods.
- Mark **workshop products as Final Sale / non-returnable** so they are excluded
  everywhere and clearly flagged.
- **Mixed-order safety net:** in a workshop+soap order, the customer can only withdraw the
  soap line; a workshop line, if submitted, is rejected at the approve step per policy.

### Layer 3 — Pre-contractual disclosure on product pages (theme / L1 — the only real code)
- A reusable, **locale-keyed** snippet `withdrawal-notice.liquid`, driven by a product
  metafield (proposed `custom.withdrawal_policy`, enum: `fixed_date_service` /
  `standard_goods`).
- **Workshop pages:** render the Art. 16(l) exclusion notice + the chosen cancellation
  policy text (goodwill default / strict alternative).
- **Physical-goods pages:** render the 14-day withdrawal right + diminished-value note +
  a link to the withdrawal flow.
- Implemented as a clean, upstreamable **L1** change; bilingual via existing `locales/`.
- Rendered on the relevant `main-product` templates (`product.soap`, `product.badzout`,
  `product.facialmask`, `product.geurblokje`, `product.workshop`, and the default/3rd-party
  template).

### Layer 4 — Shopify-admin legal artifacts (no code)
- **Policies pages** (Refund/Return + Terms) with full withdrawal info; bilingual via
  native **Translate & Adapt** (free).
- **Model withdrawal form** (CRD Annex I(B)) text published as a page (the app provides
  the functional path; the model form text is still legally expected to be available).
- **Order-confirmation email** edited to include withdrawal info + the withdrawal button
  link → also serves as the durable-medium contract confirmation.

### Layer 5 — Legal document review & bilingual rewrite
- Draft/adapt NL + EN text for: returns/refund policy, ToS withdrawal clauses, the
  workshop exclusion + cancellation policy, and the diminished-value clause.
- Flag all text for a lawyer's final check.

## 5. Scope of custom development
The mandatory button is offloaded to a free, order-integrated app, so the theme work
reduces to:
- **Layer 3:** the `withdrawal-notice.liquid` snippet + metafield + locale strings (L1).
- App **button placement** in footer / customer account.
- The **order-confirmation email** edit.

Everything else is Shopify admin configuration + legal text.

## 6. Out of scope / future enhancements (NOT phase 1)
- **Acceptance / T&C acknowledgment checkbox** at cart or checkout. Not legally required
  (a notice suffices), but provides **stronger evidence** under the Art. 6(9) burden of
  proof. Documented here as a deliberate future nice-to-have to revisit after phase 1.
- **Sealing physical goods** to rely on the Art. 16(e) hygiene exemption (would allow
  refusing opened-goods returns outright instead of applying diminished-value deductions).
- EU-wide locale expansion beyond NL/EN.

## 7. Risks & open items
- **Retractly free-tier verification** is a blocking pre-adoption gate (§4 Layer 1). If it
  fails, fallback is another free app or a custom theme two-step form (more code, must
  self-implement the acknowledgement email on a durable medium).
- **Burden of proof:** ensure the disclosure is genuinely captured in the order-confirmation
  email (durable record), not only on the live page.
- **App ↔ native returns overlap:** confirm the app's refund write-back and Shopify's
  native return rules don't double-handle; pick one as the source of truth for refunds
  (the app, given it carries the compliant customer-facing flow).

## 8. Success criteria
- A compliant **two-step withdrawal button** is reachable without login, available
  throughout the 14-day window, on physical-goods orders, with an automatic
  durable-medium acknowledgement — at **zero recurring cost**.
- **Workshops** correctly present the no-withdrawal-right notice + goodwill policy and are
  excluded from the returns/withdrawal flow.
- **Partial** and **mixed-order** withdrawals are handled without manual re-keying.
- Pre-contractual disclosure is shown **before purchase** per product type and captured in
  the order confirmation.
- Policies + model withdrawal form are published **bilingually (NL/EN)** and reviewed by
  counsel.
