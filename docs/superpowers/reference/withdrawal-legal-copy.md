# Withdrawal / returns legal copy (NL)

**Date:** 2026-07-02
**Shop:** Zogezeept
**Status:** Draft for merchant + counsel review, then paste into Shopify admin.
**Related:** [completion spec](../specs/2026-07-01-eu-withdrawal-completion-design.md), [completion plan](../plans/2026-07-01-eu-withdrawal-completion.md) (Workstream B / Tasks 4-6).

> **Disclaimer:** Informed drafting, not legal advice. The author is not a lawyer. Validate every clause with counsel before publishing, especially the diminished-value and refund-timing clauses flagged below.

## Decisions captured

- **No product seals today.** The hygiene exemption for sealed goods (CRD Art. 16(e) / BW 6:230p) is NOT invoked now. Returns are allowed on all physical products.
- **Diminished value instead.** For soaps, bath products and masks (hygiene- and moisture-sensitive), the consumer is liable for value lost through use or exposure to humidity; where the item becomes unsellable this can reach 100% of the price, offset against the refund. Soaps stay on this model permanently (no sealing planned). Masks and bath salts use it for now; when sealed later, they switch to the hygiene exemption (a future amendment).
- **Return shipping:** consumer bears the direct cost.
- **Refund:** within 14 days of the withdrawal notification (mandatory statutory anchor), but payment withheld until the returned goods are received and inspected (withholding right). Diminished value offset against the refund.
- **Workshops:** excluded from the withdrawal right (fixed-date leisure services); own cancellation terms.

Only NL is drafted, since only the Dutch storefront is live. Add EN via Translate & Adapt when an EN storefront launches.

---

## 1. Privacybeleid (addition)

Add to **Settings > Policies > Privacybeleid**:

> Voor klantcommunicatie en de afhandeling van herroepingsverzoeken maken we gebruik van Google Workspace (Google Ireland Ltd.). Deze verwerking valt onder de bestaande gegevensverwerkingsovereenkomst van Google Workspace.

---

## 2. Workshop annuleringsvoorwaarden (addition)

Add to the workshop cancellation text (workshop product/page):

> Als de workshop niet doorgaat, krijg je het volledige bedrag terug.

---

## 3. Algemene voorwaarden (addition / cross-reference)

Add a short reference so the T&C point to the refund policy rather than duplicating it:

> Op de uitoefening van het herroepingsrecht en op terugbetalingen is ons Terugbetalingsbeleid van toepassing. Workshops vallen onder de wettelijke uitzondering voor vrijetijdsbesteding op een bepaalde datum; daarvoor gelden de annuleringsvoorwaarden op de workshoppagina.

---

## 4. Terugbetalings- / Herroepingsbeleid (full)

Goes into **Settings > Policies > Terugbetalingsbeleid**.

### Herroepingsrecht bij fysieke producten

Je hebt het recht om je aankoop van fysieke producten binnen 14 dagen zonder opgave van reden te herroepen. De herroepingstermijn verstrijkt 14 dagen na de dag waarop jij (of een door jou aangewezen derde) het product fysiek in bezit krijgt. Bij een bestelling met meerdere producten die apart worden geleverd, geldt de termijn vanaf ontvangst van het laatste product.

### Hoe herroep je?

Om je herroepingsrecht uit te oefenen, gebruik je bij voorkeur ons herroepingsformulier (zie de pagina Herroeping). Vermeld daarbij je bestelnummer. Je ontvangt van ons zonder vertraging een ontvangstbevestiging. Om de herroepingstermijn na te leven volstaat het dat je je mededeling verstuurt voor het verstrijken van de 14 dagen.

### Terugzenden

Je stuurt de producten zonder onnodige vertraging terug, en in elk geval binnen 14 dagen nadat je de herroeping hebt gemeld. De directe kosten van het terugzenden zijn voor jouw rekening.

### Staat van de producten en waardevermindering

Je mag de producten uitpakken en beoordelen zoals je dat in een winkel zou doen. Je bent aansprakelijk voor de waardevermindering die het gevolg is van een behandeling die verder gaat dan nodig om de aard en de kenmerken van het product vast te stellen.

Onze producten (zepen, badproducten, maskers) zijn hygiene- en vochtgevoelig. Wanneer een product is gebruikt of aan vocht is blootgesteld, kunnen wij het niet opnieuw verkopen en gaat de waarde ervan volledig verloren. In dat geval kan de waardevermindering oplopen tot 100% van de aankoopprijs, en verrekenen wij die met de terug te betalen som.

### Terugbetaling

Na een geldige herroeping betalen wij je terug binnen 14 dagen nadat je ons van je herroeping in kennis hebt gesteld. Wij mogen wachten met terugbetalen tot wij de teruggezonden producten hebben ontvangen. Na ontvangst inspecteren wij de producten om een eventuele waardevermindering vast te stellen. Wij betalen terug met hetzelfde betaalmiddel als waarmee je hebt betaald, tenzij uitdrukkelijk anders met jou afgesproken. Een eventuele waardevermindering zoals hierboven omschreven wordt met de terugbetaling verrekend.

### Uitzondering: workshops

Workshops zijn activiteiten op een vaste datum en vallen onder de wettelijke uitzondering op het herroepingsrecht voor vrijetijdsbesteding op een bepaalde datum. Daarvoor gelden de annuleringsvoorwaarden op de workshoppagina.

---

## Counsel review notes (do not publish)

1. **Refund timing (section 4, Terugbetaling).** This follows the statute: reimburse within 14 days of the withdrawal notification (CRD Art. 13(1); transposed BW 6:230r / WER VI.51), with the right to withhold payment until the goods are received (CRD Art. 13(3)). In the normal case (customer sends the parcel back without separately supplying proof of shipment) the withholding right runs until the goods physically arrive, so you inspect on receipt and deduct diminished value before paying. Residual edge case: if the customer supplies proof of shipment AND the goods have not arrived by day 14 from notification, you must refund the full amount by day 14 without inspection. Rare for domestic returns; accepted. The 14-day deadline is mandatory and cannot be re-anchored to a later "acceptance" step. Confirm the exact BE/NL article numbers with counsel.
   - Note: the withdrawal "notification" is the customer's form submission; our automatic acknowledgment (Art. 11a durable-medium receipt) timestamps it. The clock legally starts there regardless of phrasing, and the auto-ack is itself a legal requirement, not an admission to avoid.
2. **Diminished value up to 100% (section 4).** Framed as waardevermindering, which is defensible, but a policy that routinely reaches 100% could draw scrutiny. It must genuinely track the goods being unsellable. Confirm wording.
3. **Sealing (future).** When masks and bath salts are sealed, add the hygiene-exemption clause for those unsealed items and narrow the diminished-value clause accordingly.
