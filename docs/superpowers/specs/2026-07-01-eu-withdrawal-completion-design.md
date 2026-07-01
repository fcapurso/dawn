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

Full explicit label (maximally unambiguous). Room is not a constraint — the withdrawal link is
appended to the end of the existing legal-links line (§4.4), a single wrapping row.

### 4.3 The legal links are `shop.policies` — append, don't recreate (investigated)
The footer's legal links are **not** an editable menu. They are rendered by
`{% for policy in shop.policies %}` in the bottom copyright bar (`sections/footer.liquid`), gated by
the `show_policy` setting (default `true`). Verified against the live server-rendered HTML, all seven
items come from `shop.policies`:

| Label | URL | Translated via |
|---|---|---|
| Terugbetalingsbeleid | `/policies/refund-policy` | Translate & Adapt → Policies |
| Privacybeleid | `/policies/privacy-policy` | Translate & Adapt → Policies |
| Algemene voorwaarden | `/policies/terms-of-service` | Translate & Adapt → Policies |
| Verzendbeleid | `/policies/shipping-policy` | Translate & Adapt → Policies |
| Wettelijke kennisgeving | `/policies/legal-notice` | Translate & Adapt → Policies |
| Contactgegevens | `/policies/contact-information` | Translate & Adapt → Policies |
| Cookievoorkeuren | `/policies/#shopifyReshowConsentBanner` | Shopify consent (native) |

Each link renders `{{ policy.title }}`, localized as **store content** (Translate & Adapt → Policies),
not via theme locale files. `Cookievoorkeuren` is a Shopify-**native consent policy** (the fragment
reopens the consent banner), not an app DOM injection. `shop.policies` is a **fixed, Shopify-managed
set** — there is no API to register an arbitrary "withdrawal" page as a policy.

**Conclusion:** rather than recreating the whole legal set as a menu, **leave the `shop.policies` loop
untouched and append one extra `<li>` for the withdrawal link** inside the same `<ul class="policies">`
right after the loop. The policy links keep their auto-generation and auto-localization; we add only
our own item. Smallest possible change.

### 4.4 Design — append a gated withdrawal link + optional stacked bottom
A **surgical, safely-degrading change to `sections/footer.liquid`** (chosen over a forked footer
section: smallest Dawn divergence, current look preserved, no menu to maintain).

**Theme (L1) — `sections/footer.liquid`:**
- Add footer **section settings**:
  - `show_withdrawal_link` (checkbox, default `false`) — gate.
  - `withdrawal_page` (type `page`) — the target page (resource picker → object with `.url`/`.title`).
  - `policies_own_line` (checkbox, default `false`) — stacked-layout toggle.
- **Append the link:** after the `{% for policy in shop.policies %}` loop, inside the same
  `<ul class="policies">`:
  `{%- if section.settings.show_withdrawal_link and section.settings.withdrawal_page != blank -%}`
  → one `<li>` with `<a href="{{ section.settings.withdrawal_page.url }}">{{ section.settings.withdrawal_page.title }}</a>`
  (same `copyright__content` markup as the policy items). The label is the **linked page's own title**,
  localized via Translate & Adapt → Pages — mirroring how the policy links use `policy.title`. **No
  theme locale-file change for the label.**
- **Optional stacked bottom layout:** when `policies_own_line` is on, apply a modifier class to
  `.footer__copyright` (or the `.policies` list) so the bottom renders as three rows — **payments**
  (already separate) / **copyright** / **legal links** — instead of copyright + policies flowing
  together. Small scoped CSS tweak.
- **Degrades safely:** with both toggles off, `footer.liquid` behaves exactly like vanilla Dawn —
  clean, low-divergence L1.

**Admin (merchant):**
- Set the **withdrawal page's title** to the label in each locale ("Herroep hier uw contract" /
  "Withdraw from contract here") via Translate & Adapt → Pages. (The on-page H1 is separate — it comes
  from the withdrawal-form section's own `heading` setting.)

**Theme config (L2) — `config/settings_data.json`:**
- Set the footer section's `show_withdrawal_link` on, `withdrawal_page` to the withdrawal page, and
  `policies_own_line` as desired.

### 4.5 Gating
The `footer.liquid` change **degrades to vanilla** when `show_withdrawal_link` is off, so it can land
on `current` harmlessly ahead of time. The withdrawal link appears only once the **section-setting
values (L2 config) are promoted**. The page-title translations can be set any time without affecting
the live footer (nothing renders the link until the toggle is on in promoted config). Live visibility
is controlled entirely by the deliberate promote.

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
   L1 change (the three settings + appended withdrawal `<li>` + optional stacked layout); set the
   withdrawal page's NL/EN title; enable the settings via the theme editor (L2 config). Preview via
   the Shopify↔GitHub integration; verify the withdrawal link appears at the **end** of the existing
   policy row and resolves to `/pages/herroeping`, all seven policy links + Cookievoorkeuren still
   render unchanged, the stacked layout (payments / copyright / legal links) renders when enabled,
   and it all renders in NL + EN.
2. **Harvest** — `sections/footer.liquid` is **L1** (generic, degrades to vanilla) → harvest into
   `customizations`. The already-shipped withdrawal L1 (section/asset/locales) is a verify/no-op.
3. **Backflow** config from `current` (capture live admin/config edits into the staging snapshot),
   including the footer section-setting values, so staging reflects live state before promote.
4. **Promote** `staging` → `current` (gated; explicit live confirm). This is the moment the withdrawal
   link becomes live-visible.

`current` is never hand-edited. The page-title translation and policy-text changes (Workstreams
A-admin, B) are merchant actions performed in Shopify admin, documented in the plan with exact steps.

## 7. Success criteria (full closure)

- The withdrawal function is reachable from the **footer** on every page, **no login**, clearly
  labelled ("Herroep hier uw contract" / "Withdraw from contract here"), throughout the 14-day
  window — **and not visible live until the deliberate promote**.
- The withdrawal link is **appended to the end** of the existing `shop.policies` row (all seven prior
  policy links + Cookievoorkeuren untouched and still auto-localized), its label coming from the
  withdrawal page's own title — in NL + EN. Optional stacked bottom layout (payments / copyright /
  legal links) available via toggle.
- `sections/footer.liquid` remains **generic L1** (degrades to vanilla when both new toggles are off).
- **T&C / return-refund policy**, **privacy policy**, and **workshop text** are all compliant and
  present in **NL + EN**.
- The work lands via **staging → harvest (verify) → backflow → promote**; `current` is never
  hand-edited.
- No apps, no third-party services, no external backend, no new DPA (unchanged from v2).
