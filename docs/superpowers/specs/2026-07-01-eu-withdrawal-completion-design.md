# EU Withdrawal — Completion / Closure Design

**Date:** 2026-07-01
**Shop:** Zogezeept (www.zogezeept.com) — Dawn theme + customizations (L0/L1/L2)
**Status:** Approved design, pending spec review → implementation plan
**Builds on:** [2026-06-20-eu-withdrawal-button-dawn-form-design.md](2026-06-20-eu-withdrawal-button-dawn-form-design.md)
(the v2 build). This document closes the remaining gaps to *full* compliance and lands the
work live properly.

> **Disclaimer:** Informed input, not legal advice. Author is not a lawyer. Validate with counsel.

## 1. Goal

Close the withdrawal-function topic entirely: add a **discoverable footer entry point**, complete
the **load-bearing legal text**, and **land the work live** via the proper dawn-ops flow. The form,
page template, two-step confirmation modal, locale strings, and Google Apps Script acknowledgement
are already built and tested (v2 build, Tasks 1–4 + 8–10). This plan covers only what remains.

## 2. What is already done (not in scope)

- **Theme L1:** `sections/withdrawal-form.liquid`, `assets/withdrawal-form.js`, `withdrawal_form`
  locale strings (EN/NL) — built, harvested into `customizations`, present on all branches.
- **Theme L2:** `templates/page.withdrawal.json` — present on `customizations`, `staging`, `current`.
- **Acknowledgement automation:** Gmail filter + labels + Apps Script time-trigger — built, tested,
  edge cases verified (honeypot → `withdrawal-review`, missing order # → `withdrawal-review`,
  receipt-only wording). **Done.**
- **Note on `current`:** the L1/L2 theme code was shipped to `current` early, deliberately, so the
  `page.withdrawal` template could be bound to a real page while building. This is not live-visible
  yet because there is no entry point to it. The proper land (Workstream C) redoes the flow cleanly.

## 3. Explicitly out of scope

- **Order-confirmation email link** (v2 spec §4.2): **dropped.** The footer link alone satisfies the
  "continuously available, no login, throughout the 14-day period" requirement. The order-email link
  was belt-and-suspenders discoverability; skipped to keep scope tight.
- **Rebuilding the form / modal / Apps Script:** untouched — already compliant and tested.

## 4. Workstream A — Footer entry point

### 4.1 Requirement
Under CRD **Art. 11a** (Dir. (EU) 2023/2673), the withdrawal function must be **clearly labelled,
prominently placed, continuously available throughout the 14-day period, no login required**, and
withdrawing **no more burdensome than ordering**. "Prominent" means clearly labelled and consistently
reachable — **not** visually aggressive. The footer legal/policy area is the established, accepted
home: it is where consumers expect return/legal mechanisms, it is present on every page, and it sits
beside the refund and terms links. Placing it in the buying flow is deliberately avoided (it would
nudge cancellation at point of sale with no compliance upside).

### 4.2 Label
- **NL:** "Herroep hier uw contract"
- **EN:** "Withdraw from contract here"

Full explicit label (maximally unambiguous). Crowding — the reason a shorter label was considered —
is resolved by the two-column split (§4.3), so the full label fits.

### 4.3 Two-column footer split
The current footer "Quick links" column (block `footer-0`) is bound to the store-global **`footer`
linklist**, which already holds 7 legal links (Terugbetalingsbeleid, Privacybeleid, Algemene
voorwaarden, Verzendbeleid, Wettelijke kennisgeving, Contactgegevens, Cookievoorkeuren). Adding an
8th — especially a long label — would unbalance the column. Dawn's footer natively supports multiple
`link_list` blocks rendered as separate columns.

**Design:** split the legal links into two balanced columns (~4 + 4, withdrawal item included) using a
**second `link_list` block** in the footer section.

This decomposes into two distinct change types:

| Change | Type | Where it lives | Owner |
|---|---|---|---|
| Create a second linklist; distribute the 7 legal links across the two lists; add the withdrawal item | **Admin / Navigation** (store-global, not in the repo) | Shopify admin → Navigation | Merchant |
| Add the second `link_list` block to the footer section; set its `menu` to the new linklist; reorder blocks | **Theme config (L2)** | `config/settings_data.json` | Theme (via customizer/backflow) |

### 4.4 Sequencing gotcha (load-bearing)
**Linklists are store-global and shared by every theme; footer blocks are per-theme config.**
Consequence:

- If the withdrawal item is added to the **existing** `footer` linklist, it appears on the **live**
  site **immediately** — before the deliberate promote — because the live theme's `footer-0` block
  already renders that linklist.
- To keep it gated until promote: put the withdrawal item in the **new second linklist**, whose
  column only renders once the **second `link_list` block** is promoted to `current`. The linklist
  prep (admin) can happen at any time; live visibility is controlled entirely by the theme-config
  promote.

The plan MUST place the withdrawal item in the new (not-yet-rendered) linklist, not the existing one.

## 5. Workstream B — Legal text (full scope)

1. **T&C + return/refund policy** — review and rewrite (NL/EN). This is the substantive text the
   button depends on (what the consumer is exercising, deadlines, return conditions, refund timing).
   Heaviest item; benefits from legal judgment / counsel review.
2. **Privacy policy** — add a one-line note (NL/EN) that customer-communication / withdrawal data is
   handled via Google Workspace (per v2 spec §5; no new processor, existing DPA).
3. **Workshop page** — add the reassuring "if the workshop does not run, the full amount is refunded"
   line (*"als de workshop niet doorgaat, krijg je het volledige bedrag terug."*); confirm an **EN**
   version of the workshop cancellation text exists.

Policy pages (T&C, return/refund, privacy) are Shopify **admin content** (Settings → Policies /
Pages), not theme code. The workshop-page text is product/page content (admin), reviewed against the
existing live copy.

## 6. Workstream C — Proper land (dawn-ops flow)

Per `.claude/skills/_dawn-ops-lib/conventions.md` and the dawn-ops skills:

1. **Implement + test on `staging`** — make the footer L2 config change (second `link_list` block)
   and preview via the Shopify↔GitHub integration; verify the two-column footer renders cleanly in
   NL + EN and the withdrawal link resolves to `/pages/herroeping`.
2. **Harvest** — the L1 theme code (section/asset/locales) is already in `customizations`; this is a
   verify/no-op. The footer change is **L2 config**, which flows via config snapshot, not an L1
   harvest.
3. **Backflow** config from `current` (capture live admin/config edits into the staging snapshot) so
   staging reflects live state before promote.
4. **Promote** `staging` → `current` (gated; explicit live confirm). This is the moment the footer
   entry point — and therefore the withdrawal function — becomes live-visible.

`current` is never hand-edited. The admin/Navigation and policy-text changes (Workstreams A-admin, B)
are merchant actions performed in Shopify admin, documented in the plan with exact steps.

## 7. Success criteria (full closure)

- The withdrawal function is reachable from the **footer** on every page, **no login**, clearly
  labelled ("Herroep hier uw contract" / "Withdraw from contract here"), throughout the 14-day
  window — **and not visible live until the deliberate promote**.
- The footer renders as **two balanced legal columns** (no crowding) in NL + EN.
- **T&C / return-refund policy**, **privacy policy**, and **workshop text** are all compliant and
  present in **NL + EN**.
- The work lands via **staging → harvest (verify) → backflow → promote**; `current` is never
  hand-edited.
- No apps, no third-party services, no external backend, no new DPA (unchanged from v2).
