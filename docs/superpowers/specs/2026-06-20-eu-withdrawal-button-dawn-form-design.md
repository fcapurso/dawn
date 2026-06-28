# EU Withdrawal Button — Dawn Form + Apps Script Design

**Date:** 2026-06-20
**Shop:** Zogezeept (www.zogezeept.com) — Dawn theme + customizations (L0/L1/L2)
**Status:** Approved design, pending spec review → implementation plan
**Supersedes:** the *withdrawal-button* portion (Layer 1) and the *product-page disclosure block* (Layer 3) of
[2026-06-19-eu-right-of-withdrawal-compliance-design.md](2026-06-19-eu-right-of-withdrawal-compliance-design.md).
The third-party-app route (Retractly) and the cart-checkbox idea are both dropped.

> **Disclaimer:** Informed input, not legal advice. Author is not a lawyer. Validate with counsel.

## 1. Goal

Implement the mandatory **withdrawal function** (the "withdrawal button", Dir. (EU) 2023/2673,
in force 19 Jun 2026) for **physical goods**, as the **simplest fully-owned, free, no-third-party,
no-backend** solution — built as clean theme work plus a small self-owned Google Apps Script.

## 2. Legal basis (the only obligation in scope)

The withdrawal function = **CRD Art. 11a** (inserted by Dir. (EU) 2023/2673), transposed as:
- **Belgium:** WER **Art. VI.61/1** (context: VI.47 = 14-day herroepingsrecht; VI.48 = info duty / +1 yr).
- **Netherlands:** BW **Art. 6:230oa**.

Operative requirements:
- A **withdrawal function**, labelled **"Herroep hier uw contract" / "Withdraw from contract here"**
  (or unambiguous equivalent), **continuously available throughout the 14-day period**,
  **no login required**, prominently placed; withdrawing **no more burdensome** than ordering.
- Lets the consumer submit a **withdrawal statement** + info to **identify themselves and the
  contract** — **order-level identification (order number) is sufficient**; item-level detail is
  **not** required at this stage (validated: art. 6:230oa / VI.61/1; the trader may follow up to
  clarify which items of a multi-item order, as *clarification*, not as a precondition that delays
  the refund).
- A **confirmation step** (the consumer confirms the withdrawal).
- An **acknowledgement of receipt on a durable medium** (email), containing **the content of the
  statement + date/time**, sent without undue delay (NL guidance leans "direct, automatisch" →
  our design is automatic).

### Out of scope (exempt)
**Workshops** are excluded from the withdrawal right *by law* (fixed-date leisure services:
**WER VI.53, 12°** / **BW 6:230p** / CRD 16(l)) → **no button required**. The existing workshop
product-page text was reviewed and judged an adequate, low-friction disclosure (see §7).

## 3. Architecture

```
Consumer ──fills──▶ Dawn native contact form (/pages/herroeping, themed, NL/EN, two-step)
                         │  submit (Shopify-native {% form 'contact' %})
                         ▼
                   Shopify sends notification email ──▶ merchant Google Workspace inbox
                         │  (Reply-To = consumer email; body carries order #)
                         ├─▶ Gmail filter labels it "withdrawal"
                         ▼
                   Google Apps Script (time-driven trigger ~1 min)
                         │  reads new labelled mail: recipient = Reply-To, order # = delimited line
                         ▼
                   Sends templated NL/EN acknowledgement to the consumer (durable medium,
                   order # + timestamp) ──▶ marks thread processed
                         │
                         ▼
                   Merchant processes the refund manually in Shopify admin
```

No apps, no form services, no external backend, no new DPA (Google Workspace DPA already covers it).

## 4. Components

### 4.1 Withdrawal form (theme, L1)
- A dedicated page (handle **`herroeping`**) hosting a **custom-built `{% form 'contact' %}`** —
  modelled on `sections/contact-form.liquid`, but a separate section/snippet
  (`withdrawal-form.liquid`) so the contact form stays untouched.
- **Fields:** name (`contact[Name]`), email (`contact[email]` → sets Reply-To), **order number**
  (`contact[Order number]`), optional free-text statement/reason, and a hidden **locale** field
  (`contact[Locale]`) so the Apps Script picks the NL/EN template.
- **Two-step:** the consumer fills the form, then a **confirmation modal** ("Please confirm you
  want to withdraw from order #…") with **Confirm / Cancel**; Confirm submits. (Satisfies the
  Art. 11a confirmation step; literal and our-styled.)
- **Bilingual:** all strings via `locales/` (`| t`), like the rest of Dawn.
- **Scope note on the page:** brief text that the function is for physical-goods orders and that
  workshops follow their own cancellation terms.
- Clean, upstreamable **L1** (no store-specific data; degrades safely).

### 4.2 Entry points (theme + admin)
- **Footer link** "Herroep hier uw contract / Withdraw from contract here" → `/pages/herroeping`
  (continuously available, no login, prominent).
- **Order-confirmation email** (Settings → Notifications): add the same link (durable record +
  discoverability).

### 4.3 Acknowledgement automation (Google Apps Script, merchant-owned)
- A **Gmail filter** labels Shopify withdrawal notifications (match on a stable subject/marker we
  set via the contact form, e.g. a fixed subject line) as `withdrawal`.
- An **Apps Script** project (~30 lines) with a **time-driven trigger (every 1 min)**:
  1. Query `label:withdrawal -label:withdrawal-done`.
  2. For each thread: recipient = message **Reply-To**; order # = a **clearly delimited line** in
     the body (e.g. `Order number: …`).
  3. Send a **templated, branded NL/EN acknowledgement** (`GmailApp.sendEmail`) from the Workspace
     domain, merging in the order # + including the timestamp.
  4. Apply label `withdrawal-done` (idempotency — never double-sends).
- Robustness: address comes from **Reply-To** (stable header), not body parsing; order # parsed
  from a fixed, delimited label line we control.

### 4.4 Processing (manual, merchant)
- Merchant reads the notification, processes the refund/return in Shopify admin. For multi-item
  orders, may reply to clarify which items (clarification, not a precondition).

## 5. Data flow & GDPR

- Personal data: consumer email + order # (+ optional name/reason). Non-special-category.
- **No new processor / no new transfer:** the data already enters Google Workspace as soon as the
  Shopify notification lands in the inbox; Apps Script only acts on mail already there, under the
  **existing Google Workspace DPA** (Apps Script runs under the same agreement). US transfer
  covered by **SCCs + EU-US DPF** (Google LLC certified) — identical to simply using Gmail for
  business.
- **Action:** add a one-line note to the privacy policy that customer-communication/withdrawal
  data is handled via Google Workspace (deferred legal-text list, §8).

## 6. Error handling & edge cases
- **Apps Script failure / no trigger:** acknowledgement not sent → merchant still has the
  notification and can reply manually (fallback). Add a simple failure alert (script emails the
  merchant on exception).
- **Unparseable order #:** script falls back to sending a generic acknowledgement (still confirms
  receipt + timestamp) and flags the thread for manual review.
- **Spam/abuse on the public form:** Dawn contact form includes basic protections; add honeypot;
  rely on manual processing to catch bogus requests (no auto-refund).
- **Gmail send limits** (Workspace ~1,500–2,000/day): far above volume.
- **Latency ~1 min:** within "without undue delay" and acceptably "direct".

## 7. Workshop disclosure (reviewed, no change required)
Live workshop text states clear cancellation terms (full refund >2 weeks; conditional within
2 weeks; runs from 5 participants). Judged an adequate, low-friction disclosure. The exemption is
automatic (VI.53,12° / 6:230p), so no explicit "no withdrawal right" line is *required*. **One
optional, win-win edit** (reassuring *and* tidies a fairness point): state that if the workshop
does not run, the full amount is refunded — *"als de workshop niet doorgaat, krijg je het volledige
bedrag terug."* Optional; not part of this build. Confirm an **EN** version of the workshop text exists.

## 8. Deferred (not this build)
- **T&C + return/refund policy** review/rewrite (NL/EN) — the load-bearing text behind the button.
- **Privacy-policy** one-line note re Google Workspace handling of withdrawal/communication data.
- Optional workshop-page edit (§7) + EN check.

## 9. Layer-ops workflow
Per `.claude/skills/_dawn-ops-lib/conventions.md`: develop the theme parts on a scratch branch off
`staging`; preview via the **Shopify↔GitHub integration** (`git push origin staging` → linked
preview theme); harvest the generic form snippet/section/locales into `customizations` (L1);
`dawn-promote` `staging`→`current` (gated, live confirm). The Apps Script + Gmail filter +
order-email edit are **admin/Workspace actions** the merchant performs (not theme code). `current`
is never edited by hand.

## 10. Success criteria
- A labelled **"Herroep hier uw contract / Withdraw from contract here"** function is reachable
  **without login**, from the **footer** and **order-confirmation email**, throughout the 14-day period.
- It collects a withdrawal statement + **order-level** identification, with a **confirmation step**.
- On submission, the consumer **automatically** receives a **durable-medium acknowledgement**
  (order # + timestamp), within ~1 minute.
- Workshops are not subject to the function; their existing disclosure stands.
- No apps, no third-party services, no external backend, no new DPA.
- Theme parts land as clean **L1**; admin/Workspace parts documented for the merchant.
