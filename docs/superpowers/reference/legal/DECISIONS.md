# Withdrawal / returns legal copy — decisions & counsel notes

**Date:** 2026-07-02
**Shop:** Zogezeept
**Scope:** Workstream B of the [withdrawal completion plan](../../plans/2026-07-01-eu-withdrawal-completion.md).

The per-document files in this folder hold the actual copy. Each was committed first as a verbatim
**baseline snapshot** of the live policy, then the **proposed edits** on top (separate commit), so the
diff shows exactly what changes. Only NL is drafted (only the Dutch storefront is live).

> **Disclaimer:** Informed drafting, not legal advice. Validate the flagged clauses with counsel before publishing.

## Decisions captured

- **No product seals today.** The hygiene exemption for sealed goods (CRD Art. 16(e) / BW 6:230p) is
  NOT invoked. Returns allowed on all physical products.
- **Diminished value instead.** Soaps, bath products and masks are hygiene- and moisture-sensitive;
  if used or exposed to humidity they are unsellable, so the value reduction can reach 100%, offset
  against the refund. Soaps stay on this model permanently. Masks and bath salts too, for now; when
  sealed later, switch those to the hygiene exemption.
- **Return shipping:** consumer bears the cost (already in the AV, Art. 4).
- **Refund timing:** per the AV, within 14 days of the withdrawal notification, with the right to
  withhold until the goods are received OR the consumer proves return, whichever is earliest. The
  earlier "receipt-only" idea was dropped: it would contradict the existing AV, and the AV wording is
  the compliant one.
- **The AV already contains a full withdrawal framework** (Art. 4.4 herroepingsrecht, diminished
  value, Art. 6 refund + withholding, Bijlage 1 model form). So no parallel legal text was written;
  the Terugbetalingsbeleid is only a plain-language summary pointing to the AV.
- **Model form:** keep Bijlage 1 (EU model withdrawal form) AND reference the online withdrawal form
  in Art. 4.4. Not replaced.
- **Workshops:** exemption (fixed-date leisure, WER VI.53,12°) added to the AV. NO cancellation policy
  on the workshop page: goodwill copy removed, cancellations handled ad hoc, no expectation-raising.
- **Privacy:** one-line Google Workspace processor note added.

## Counsel review notes (do not publish)

1. **Diminished value up to 100%** (Terugbetalingsbeleid + AV Art. 4 generic clause). Framed as
   waardevermindering, which is defensible, but a policy that routinely reaches 100% could draw
   scrutiny. It must genuinely track the goods being unsellable. Consider whether to make the
   hygiene/humidity specificity explicit in the AV, or leave it only in the plain-language summary.
2. **Refund timing.** The AV uses the statutory "received or proof of return, whichever earliest",
   timed from notification. This is compliant. Note the residual edge case: if the consumer supplies
   proof of shipment and the goods have not arrived by day 14, the full refund is due without prior
   inspection. Rare for domestic returns; accepted. The "notification" is the customer's form
   submission, timestamped by the Art. 11a auto-acknowledgment.
3. **Workshop exemption.** Confirm WER VI.53,12° (and NL BW 6:230p equivalent) is the correct basis,
   and that the AV clause + the "no withdrawal right" disclosure is sufficient given no cancellation
   terms remain on the workshop page.
4. **Sealing (future).** When masks and bath salts are sealed, add the hygiene-exemption clause for
   those unsealed items and narrow the diminished-value clause accordingly.

## Where each change is published

| Document | File | Change |
|---|---|---|
| Privacybeleid | `privacybeleid.md` | +Google Workspace note |
| Terugbetalingsbeleid | `terugbetalingsbeleid.md` | rewritten summary, points to AV |
| Algemene voorwaarden | `algemene-voorwaarden.md` | +online-form ref, +workshop exemption |
| Workshop (product page) | `workshop-annulering.md` | cancellation copy removed |
| Verzendbeleid, Wettelijke kennisgeving, Contactgegevens | resp. files | baseline only, no change |
