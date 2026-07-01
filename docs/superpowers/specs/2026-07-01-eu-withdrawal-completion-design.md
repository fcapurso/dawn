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

Full explicit label (maximally unambiguous). Room is not a constraint — the withdrawal link joins the
existing legal-links line (§4.4), which is a single wrapping row.

### 4.3 Why the legal links must become menu-driven (investigated)
The footer's legal links are **not** an editable menu today. They are rendered by
`{% for policy in shop.policies %}` in the bottom copyright bar (`sections/footer.liquid`), gated by
the `show_policy` setting (default `true`). Verified against the live server-rendered HTML, all seven
items come from `shop.policies`:

| Label | URL |
|---|---|
| Terugbetalingsbeleid | `/policies/refund-policy` |
| Privacybeleid | `/policies/privacy-policy` |
| Algemene voorwaarden | `/policies/terms-of-service` |
| Verzendbeleid | `/policies/shipping-policy` |
| Wettelijke kennisgeving | `/policies/legal-notice` |
| Contactgegevens | `/policies/contact-information` |
| Cookievoorkeuren | `/policies/#shopifyReshowConsentBanner` |

**`Cookievoorkeuren` is a Shopify-native consent policy, not an app DOM injection** (the fragment
reopens the consent banner). `shop.policies` is a **fixed, Shopify-managed set** — there is no API to
register an arbitrary "withdrawal" page as a policy. Therefore the only way to place the withdrawal
link *among* the legal links is to stop rendering the auto policy row and drive the legal links from
an **editable menu** instead. (This was validated: the "just inject it like the cookie link" idea is
not available to us.)

### 4.4 Design — menu-driven legal links + stacked bottom (Route 2)
A **surgical change to `sections/footer.liquid`** (chosen over a full forked footer section: smallest
Dawn divergence, tiny/easy upgrade conflicts, current look preserved). Three coordinated changes:

**Theme (L1) — `sections/footer.liquid`:**
- Add a footer **section setting** `legal_menu` (type `link_list`); keep `show_policy`.
- In the bottom copyright bar, render the legal links from the menu when set, else fall back to
  `shop.policies`:
  `{%- if section.settings.legal_menu != blank -%}` render `legal_menu.links` (same
  `<ul class="policies">` markup/position/style) `{%- elsif section.settings.show_policy -%}` render
  `shop.policies` (unchanged vanilla behavior).
- **Stacked bottom layout:** restructure `.footer__copyright` so the bottom renders as three rows —
  **payments** (already separate) / **copyright** (own line) / **legal links** (own line) — instead
  of copyright + policies flowing together. Small scoped CSS/markup tweak.
- **Degrades safely:** with no `legal_menu` configured it behaves exactly like vanilla Dawn, keeping
  the change generic and upstreamable (clean L1).

**Admin / Navigation (store-global, merchant):**
- Create a menu (e.g. handle `footer-legal`) containing the six policy links + Cookievoorkeuren
  (`/policies/#shopifyReshowConsentBanner`) + the **withdrawal link** (`/pages/herroeping`), with the
  withdrawal link **at the end** of the list.
- Set NL/EN labels via Translate & Adapt (menu-driving loses `shop.policies` auto title localization,
  so labels are maintained manually — acceptable, both locales are maintained anyway).

**Theme config (L2) — `config/settings_data.json`:**
- Bind the footer section's `legal_menu` to the `footer-legal` menu; `show_policy` becomes redundant.

### 4.5 Gating
The `footer.liquid` change **degrades to vanilla** when `legal_menu` is unset, so it can land on
`current` harmlessly ahead of time. The legal row only switches to the menu — and the withdrawal link
only appears — once the **`legal_menu` config binding (L2) is promoted**. The admin menu can be
prepared at any time without affecting the live footer (nothing points at it until the config binds).
Live visibility is controlled entirely by the deliberate promote.

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

1. **Implement + test on `staging`** — on a scratch branch off `staging`: make the `footer.liquid`
   L1 change (`legal_menu` setting + menu-driven legal links + stacked bottom layout); create the
   `footer-legal` admin menu; bind `legal_menu` via the theme editor (L2 config). Preview via the
   Shopify↔GitHub integration; verify the bottom renders as payments / copyright / legal-links rows,
   all seven policy links + Cookievoorkeuren still resolve, the withdrawal link sits at the end and
   resolves to `/pages/herroeping`, and it all renders in NL + EN.
2. **Harvest** — `sections/footer.liquid` is **L1** (generic, degrades to vanilla) → harvest into
   `customizations`. The already-shipped withdrawal L1 (section/asset/locales) is a verify/no-op.
3. **Backflow** config from `current` (capture live admin/config edits into the staging snapshot),
   including the `legal_menu` binding + `show_policy` state, so staging reflects live state before
   promote.
4. **Promote** `staging` → `current` (gated; explicit live confirm). This is the moment the legal row
   switches to the menu and the withdrawal function becomes live-visible.

`current` is never hand-edited. The admin/Navigation (`footer-legal` menu) and policy-text changes
(Workstreams A-admin, B) are merchant actions performed in Shopify admin, documented in the plan with
exact steps.

## 7. Success criteria (full closure)

- The withdrawal function is reachable from the **footer** on every page, **no login**, clearly
  labelled ("Herroep hier uw contract" / "Withdraw from contract here"), throughout the 14-day
  window — **and not visible live until the deliberate promote**.
- The footer bottom renders as three stacked rows (**payments / copyright / legal links**); the legal
  links are menu-driven, all seven prior policy links + Cookievoorkeuren still present and resolving,
  with the withdrawal link at the end — in NL + EN.
- `sections/footer.liquid` remains **generic L1** (degrades to vanilla `shop.policies` when no
  `legal_menu` is configured).
- **T&C / return-refund policy**, **privacy policy**, and **workshop text** are all compliant and
  present in **NL + EN**.
- The work lands via **staging → harvest (verify) → backflow → promote**; `current` is never
  hand-edited.
- No apps, no third-party services, no external backend, no new DPA (unchanged from v2).
