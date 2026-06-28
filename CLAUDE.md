# Dawn / Zogezeept — project context

> Operated from the `ops` branch (skills + docs live here). Theme branches stay pure;
> this file is intentionally only on `ops` and is never deployed.

## Store / account facts

- **Shopify plan: standard (NOT Shopify Plus).** Consequence: the **checkout** itself
  cannot be customized (no checkout UI extensions / no mandatory checkout checkboxes).
  Anything that must gate purchase (e.g. a terms / right-of-withdrawal acknowledgment)
  has to live on the **cart page + cart drawer** (gating the Checkout button), via theme
  code (L1) or a free cart-checkbox app — not in checkout.
- **Storefront: www.zogezeept.com.** Markets: Belgium + Netherlands (EU). Maintained
  locales: **Dutch + English** only.

## Pointers

- Layer / branch model + the "never touch `current`" rule:
  `.claude/skills/_dawn-ops-lib/conventions.md`
- Right-of-withdrawal compliance work:
  `docs/superpowers/specs/2026-06-19-eu-right-of-withdrawal-compliance-design.md`
  and `docs/superpowers/plans/2026-06-19-eu-right-of-withdrawal-compliance.md`
