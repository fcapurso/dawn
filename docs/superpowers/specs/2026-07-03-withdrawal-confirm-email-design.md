# Withdrawal Form — Confirmation Popup Repeats Email

**Date:** 2026-07-03
**Shop:** Zogezeept (www.zogezeept.com) — Dawn theme + customizations (L0/L1/L2)
**Status:** Approved design, pending spec review → implementation plan

## 1. Goal

Reduce the risk of a mistyped email address on the withdrawal form. The two-step confirmation
popup (already shown before the form submits) should also repeat back the email address the
customer entered, alongside the order number it already repeats, so a typo is visible before
final confirmation.

## 2. Current behavior

`assets/withdrawal-form.js` (on `staging`) opens a modal before submit. The modal body comes from
the `withdrawal_form.confirm_body` locale string, which contains an `[order]` token; the script
reads the order-number input and substitutes it in before rendering.

## 3. Change

**Locale copy** (`locales/en.default.json`, `locales/nl.json`, key `withdrawal_form.confirm_body`)
— append a sentence stating where the receipt will be sent, using a new `[email]` token:

- EN: `Confirm you want to withdraw order [order]? A confirmation will be sent to [email].`
- NL: `Bevestig dat je bestelling [order] wilt herroepen? Een bevestiging wordt verstuurd naar [email].`

**Script** (`assets/withdrawal-form.js`) — mirror the existing `[order]` substitution: read
`input[name="contact[email]"]` from the form and replace `[email]` in the body template with its
value before rendering the modal.

No changes to `sections/withdrawal-form.liquid` (the `data-confirm-body` attribute already passes
the translated string through unchanged) or to the modal's HTML/CSS.

## 4. Out of scope

- Validating the email format beyond the existing `type="email"` + `required` input.
- Any change to the success message shown after submit.

## 5. Success criteria

- Opening the confirmation popup shows both the order number and the exact email address just
  typed into the email field, in NL and EN.
- If the order-number field is empty (shouldn't happen — it's required, same as email), the
  `[order]` token still degrades to empty string as it does today; `[email]` degrades the same way.
