# Align Withdrawal Form With Contact Form

**Date:** 2026-07-03
**Shop:** Zogezeept (www.zogezeept.com) — Dawn theme + customizations (L0/L1/L2)
**Status:** Approved design, pending spec review → implementation plan

## 1. Goal

`sections/withdrawal-form.liquid` was hand-built by adapting `sections/contact-form.liquid`'s
markup, but a number of small differences crept in that have no functional reason to exist — most
visibly, withdrawal-form never picked up the "reveal sections on scroll" animation that
contact-form has. Align the two sections so the only remaining differences are ones withdrawal's
requirements genuinely force. `contact-form.liquid` is the frozen, vanilla-Dawn baseline — it does
not change.

## 2. Current differences and their disposition

### 2a. Keep as justified (no change)

These differences exist because withdrawal-form does something contact-form structurally cannot:

- **Stable, non-localized field names** (`contact[Name]`, `contact[Order number]`,
  `contact[Withdrawal statement]`, `contact[email]`) — required so the notification email stays
  parseable by the store's Gmail-filter automation regardless of storefront locale.
- **Order-number and withdrawal-statement fields** — content contact-form has no equivalent of.
- **Hidden `contact[Request type]` / `contact[Locale]` markers** — required by the same parsing
  automation.
- **Honeypot field (`contact[Website]`) and its check in `assets/withdrawal-form.js`** — wired into
  the confirm-modal's bot guard (`tryOpen()` bails early if the honeypot is filled). It's part of
  the modal subsystem below, not an independent add-on, so it stays with it rather than being
  stripped or backported to contact-form.
- **Two-step JS confirm modal** (`data-withdrawal-submit`, `assets/withdrawal-form.js`) — core to
  the legal withdrawal-confirmation UX designed in
  `docs/superpowers/specs/2026-06-20-eu-withdrawal-button-dawn-form-design.md` and refined in
  `docs/superpowers/specs/2026-07-03-withdrawal-confirm-email-design.md`. No contact-form
  equivalent.
- **`success_message` setting (editable text, supports a raw mailto `<a>`) and `preview_success`
  checkbox** — part of the same already-approved confirmation-copy work. The content is genuinely
  different from contact-form's static translated string (it must describe an automated
  confirmation email), and `preview_success` exists because exercising the real flow to proof the
  copy would generate an actual legal request. Not stripped.
- **`intro` richtext setting** — no contact-form equivalent to conform to; it's the
  compliance-required framing copy explaining the 14-day withdrawal window.

### 2b. Align to match contact-form (incidental drift)

These differences have no functional justification and should be brought back in line:

1. **Scroll-reveal animation** — neither the heading nor the form wrapper in withdrawal-form
   carries `{% if settings.animations_reveal_on_scroll %} scroll-trigger
   animate--slide-in{% endif %}`. Add both, mirroring contact-form's `contact_form_class`
   liquid-assign idiom exactly (`sections/contact-form.liquid:20` and `:26-31`).
2. **CSS delivery** — withdrawal-form declares its padding/modal/honeypot/help rules in a
   section-local `<style>` block at the bottom of the file. Move them into Dawn's
   `{%- style -%}...{%- endstyle -%}` tag at the top, matching contact-form's convention. Same
   output, no visual change.
3. **Heading markup** — add the `title-wrapper--no-top-margin` class (currently missing) and the
   `visually-hidden` fallback `<h2>` for when the `heading` setting is blank, so withdrawal-form
   gets the same guarantee contact-form has: an h2 always renders, even with no visible heading
   text.
4. **Field layout** — wrap the name + email fields in `.contact__fields` (the 2-column grid at
   `assets/section-contact-form.css:34`, already shared by both sections) so the two forms lay out
   fields identically on desktop (≥750px). Order-number and the statement textarea stay full-width
   below, the same way phone and comment do on contact-form.
5. **Error handling** — restore the per-field error-list pattern for the email field
   (`<ul class="form-status-list">` with a link to `#WithdrawalForm-email`), matching
   contact-form's structure 1:1. Order-number gets no equivalent list, for the same reason
   phone/comment don't on contact-form: Shopify's contact form backend only validates `email`
   server-side, so it's the only field with a `form.errors` entry to link to.
6. **Control-flow shape** — keep the `show_success` variable (still needed to OR together
   `form.posted_successfully?` and the design-mode `preview_success` check), but reshape the
   surrounding `if`/`elsif`/`else` to mirror contact-form's nesting depth, so the two files stay
   easy to diff against each other going forward.

## 3. Out of scope

- No shared snippet/partial extraction (e.g. a `snippets/_form-field.liquid`). No other Dawn
  section shares field markup via snippets; introducing that abstraction for two call sites isn't
  justified by this change.
- No changes to `sections/contact-form.liquid`.
- No locale-file cleanup — withdrawal's `withdrawal_form.*` keys and contact's
  `templates.contact.form.*` keys don't overlap, so nothing becomes unused.
- No change to the honeypot's DOM selector or to `assets/withdrawal-form.js`'s logic — only the
  surrounding Liquid/CSS structure moves.

## 4. Success criteria

- With "reveal sections on scroll" on, the Withdrawal page's heading and form animate in the same
  way the Contact page's do.
- Side-by-side screenshot at mobile and desktop widths shows matching field layout and spacing
  between the two sections (name+email paired on desktop; order-number and statement full-width).
- Withdrawal-form's heading still renders (visually hidden) if the `heading` setting is cleared.
- The confirm-modal flow (honeypot guard, order/email repeat, submit) still works end to end after
  the CSS/control-flow restructuring.
- The editor's `preview_success` toggle and the email-field error state still work.
- A line-by-line diff of the two sections' shared structure (style delivery, heading, field-pair
  layout, error handling, form-wrapper class) shows no incidental differences left — only the
  items listed in §2a.

## 5. Where this lands

Structural, generic fix with no store-specific content → an `L1:` commit on `customizations`,
following the normal harvest/ship path (`dawn-harvest` → `dawn-ship`). Not a direct edit to
`current`.
