# EU Withdrawal Button (Dawn form + Apps Script) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the mandatory EU withdrawal function (Art. 11a) for physical goods as a custom Dawn `{% form 'contact' %}` on `/herroeping` (themed, bilingual, two-step) whose submission Shopify emails to the merchant, with a Google Apps Script auto-sending the durable-medium acknowledgement — no apps, no backend.

**Architecture:** A theme **section** renders a native contact form with **stable (non-localized) field names** + a hidden request marker + locale; a small **asset JS** adds a confirmation-modal second step. Shopify emails the merchant (Reply-To = consumer). A **Gmail filter** labels those mails; a **Google Apps Script** time-trigger reads each, takes the recipient from Reply-To and the order # from a delimited body line, and sends a templated NL/EN acknowledgement.

**Tech Stack:** Dawn/Liquid, `{% form 'contact' %}`, vanilla JS, `locales/*.json`, `theme-check`, Shopify admin (Pages/Notifications), Gmail filters, Google Apps Script (GmailApp).

**Source spec:** [docs/superpowers/specs/2026-06-20-eu-withdrawal-button-dawn-form-design.md](../specs/2026-06-20-eu-withdrawal-button-dawn-form-design.md)

> **Disclaimer:** Not legal advice. The T&C/return-policy + privacy-policy notes remain deferred (spec §8).

---

## Layer-ops workflow
Develop theme tasks (1–4) on a scratch branch off `staging`; preview by pushing to `staging` (Shopify↔GitHub integration updates the linked preview theme). After validation: `dawn-harvest` the section + asset + locales into `customizations` (L1), rebuild `staging`, `dawn-promote` → `current` (gated, live confirm). Tasks 5–10 are **admin/Workspace actions the merchant performs** (Claude provides exact steps + the full script). `current` is never edited by hand.

## File structure
| File | Responsibility | Owner |
|---|---|---|
| `locales/en.default.json`, `locales/nl.json` (modify) | `withdrawal_form` strings (EN/NL) | Claude |
| `sections/withdrawal-form.liquid` (create) | The contact-form-backed withdrawal form (stable field names, hidden markers, modal hooks) | Claude |
| `assets/withdrawal-form.js` (create) | Two-step confirmation modal + honeypot guard | Claude |
| Shopify page `herroeping` + footer link + order-email | Entry points | Merchant |
| Gmail filter + Apps Script | Acknowledgement automation | Merchant (code from Claude) |

**Verification reality:** the theme has no Liquid unit-test harness, so theme tasks verify via `theme-check` + JSON validation + a real preview submission. Apps Script verifies via the Apps Script editor + a test email.

---

## Phase A — Theme (L1), scratch branch off `staging`

### Task 1: Add `withdrawal_form` locale strings (EN + NL)

**Files:** Modify `locales/en.default.json`, `locales/nl.json`

- [ ] **Step 1: Add the EN block** — insert as the first key after the opening `{` in `locales/en.default.json`:

```json
  "withdrawal_form": {
    "intro_html": "Use this form to withdraw from a purchase of physical goods within 14 days. Workshops are fixed-date activities and follow their own cancellation terms shown on the workshop page.",
    "name_label": "Name",
    "email_label": "Email",
    "order_number_label": "Order number",
    "order_number_help": "You can find this in your order confirmation email, e.g. #1234.",
    "statement_label": "Your withdrawal statement (optional)",
    "submit": "Withdraw from contract here",
    "confirm_title": "Confirm your withdrawal",
    "confirm_body": "Please confirm you want to withdraw from order [order]. We will send a confirmation of receipt to your email.",
    "confirm_ok": "Confirm withdrawal",
    "confirm_cancel": "Go back",
    "success": "We have received your withdrawal request and emailed you a confirmation of receipt. We will process it and contact you if we need to clarify anything."
  },
```

- [ ] **Step 2: Add the NL block** — insert as the first key after the opening `{` in `locales/nl.json`:

```json
  "withdrawal_form": {
    "intro_html": "Gebruik dit formulier om binnen 14 dagen een aankoop van fysieke producten te herroepen. Workshops zijn activiteiten op een vaste datum en volgen hun eigen annuleringsvoorwaarden op de workshoppagina.",
    "name_label": "Naam",
    "email_label": "E-mail",
    "order_number_label": "Bestelnummer",
    "order_number_help": "Dit vind je in je orderbevestiging, bv. #1234.",
    "statement_label": "Je herroepingsverklaring (optioneel)",
    "submit": "Herroep hier uw contract",
    "confirm_title": "Bevestig je herroeping",
    "confirm_body": "Bevestig dat je bestelling [order] wilt herroepen. We sturen een ontvangstbevestiging naar je e-mailadres.",
    "confirm_ok": "Herroeping bevestigen",
    "confirm_cancel": "Terug",
    "success": "We hebben je herroepingsverzoek ontvangen en een ontvangstbevestiging naar je e-mailadres gestuurd. We verwerken het en nemen contact op als we iets moeten verduidelijken."
  },
```

- [ ] **Step 3: Validate JSON**

Run: `python3 -m json.tool locales/en.default.json > /dev/null && python3 -m json.tool locales/nl.json > /dev/null && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add locales/en.default.json locales/nl.json
git commit -m "feat(i18n): withdrawal form strings (EN/NL)"
```

### Task 2: Create the withdrawal-form section

**Files:** Create `sections/withdrawal-form.liquid`

- [ ] **Step 1: Write the section**

```liquid
{{ 'section-contact-form.css' | asset_url | stylesheet_tag }}

<div class="color-{{ section.settings.color_scheme }} gradient">
  <div class="contact page-width page-width--narrow section-{{ section.id }}-padding">
    {%- if section.settings.heading != blank -%}
      <h2 class="title inline-richtext {{ section.settings.heading_size }}">{{ section.settings.heading }}</h2>
    {%- endif -%}

    <p class="withdrawal-form__intro rte">{{ 'withdrawal_form.intro_html' | t }}</p>

    {%- form 'contact', id: 'WithdrawalForm', class: 'isolate' -%}
      {%- if form.posted_successfully? -%}
        <h2 class="form-status form__message" tabindex="-1" autofocus>
          {{- 'icon-success.svg' | inline_asset_content -}}
          {{ 'withdrawal_form.success' | t }}
        </h2>
      {%- elsif form.errors -%}
        <div class="form__message">
          <h2 class="form-status caption-large text-body" role="alert" tabindex="-1" autofocus>
            {{- 'icon-error.svg' | inline_asset_content -}}
            {{ 'templates.contact.form.error_heading' | t }}
          </h2>
        </div>
      {%- endif -%}

      {%- comment -%} Stable, NON-localized field names so the notification email is parseable. {%- endcomment -%}
      <div class="field">
        <input class="field__input" type="text" id="WithdrawalForm-name" name="contact[Name]"
          value="{% if form.name %}{{ form.name }}{% elsif customer %}{{ customer.name }}{% endif %}"
          placeholder="{{ 'withdrawal_form.name_label' | t }}" autocomplete="name">
        <label class="field__label" for="WithdrawalForm-name">{{ 'withdrawal_form.name_label' | t }}</label>
      </div>

      <div class="field">
        <input class="field__input" type="email" id="WithdrawalForm-email" name="contact[email]"
          value="{% if form.email %}{{ form.email }}{% elsif customer %}{{ customer.email }}{% endif %}"
          spellcheck="false" autocapitalize="off" autocomplete="email" aria-required="true" required
          placeholder="{{ 'withdrawal_form.email_label' | t }}">
        <label class="field__label" for="WithdrawalForm-email">{{ 'withdrawal_form.email_label' | t }} <span aria-hidden="true">*</span></label>
      </div>

      <div class="field">
        <input class="field__input" type="text" id="WithdrawalForm-order" name="contact[Order number]"
          aria-required="true" required placeholder="{{ 'withdrawal_form.order_number_label' | t }}">
        <label class="field__label" for="WithdrawalForm-order">{{ 'withdrawal_form.order_number_label' | t }} <span aria-hidden="true">*</span></label>
        <small class="withdrawal-form__help">{{ 'withdrawal_form.order_number_help' | t }}</small>
      </div>

      <div class="field">
        <textarea rows="5" class="text-area field__input" id="WithdrawalForm-statement" name="contact[Withdrawal statement]"
          placeholder="{{ 'withdrawal_form.statement_label' | t }}"></textarea>
        <label class="form__label field__label" for="WithdrawalForm-statement">{{ 'withdrawal_form.statement_label' | t }}</label>
      </div>

      {%- comment -%} Hidden machine fields: marker for the Gmail filter + locale for the script. {%- endcomment -%}
      <input type="hidden" name="contact[Request type]" value="withdrawal_request">
      <input type="hidden" name="contact[Locale]" value="{{ request.locale.iso_code }}">

      {%- comment -%} Honeypot: bots fill it; humans never see it. {%- endcomment -%}
      <div class="withdrawal-form__hp" aria-hidden="true">
        <label>Website<input type="text" name="contact[Website]" tabindex="-1" autocomplete="off"></label>
      </div>

      <div class="contact__button">
        <button type="submit" class="button"
          data-withdrawal-submit
          data-confirm-title="{{ 'withdrawal_form.confirm_title' | t | escape }}"
          data-confirm-body="{{ 'withdrawal_form.confirm_body' | t | escape }}"
          data-confirm-ok="{{ 'withdrawal_form.confirm_ok' | t | escape }}"
          data-confirm-cancel="{{ 'withdrawal_form.confirm_cancel' | t | escape }}">
          {{ 'withdrawal_form.submit' | t }}
        </button>
      </div>
    {%- endform -%}
  </div>
</div>

<style>
  .section-{{ section.id }}-padding { padding-top: {{ section.settings.padding_top | times: 0.75 | round: 0 }}px; padding-bottom: {{ section.settings.padding_bottom | times: 0.75 | round: 0 }}px; }
  @media screen and (min-width: 750px) { .section-{{ section.id }}-padding { padding-top: {{ section.settings.padding_top }}px; padding-bottom: {{ section.settings.padding_bottom }}px; } }
  .withdrawal-form__hp { position: absolute !important; left: -9999px !important; height: 0; overflow: hidden; }
  .withdrawal-form__help { display: block; margin-top: 0.4rem; opacity: 0.75; }
  .withdrawal-modal[hidden] { display: none; }
  .withdrawal-modal { position: fixed; inset: 0; display: grid; place-items: center; background: rgba(0,0,0,.5); z-index: 100; }
  .withdrawal-modal__box { background: rgb(var(--color-background)); color: rgb(var(--color-foreground)); max-width: 30rem; margin: 1rem; padding: 2rem; border-radius: var(--popup-corner-radius, 8px); }
  .withdrawal-modal__actions { display: flex; gap: 1rem; margin-top: 1.5rem; flex-wrap: wrap; }
</style>

<script src="{{ 'withdrawal-form.js' | asset_url }}" defer="defer"></script>

{% schema %}
{
  "name": "Withdrawal form",
  "tag": "section",
  "class": "section",
  "disabled_on": { "groups": ["header", "footer"] },
  "settings": [
    { "type": "inline_richtext", "id": "heading", "default": "Withdraw from contract", "label": "Heading" },
    { "type": "select", "id": "heading_size", "options": [
      { "value": "h2", "label": "Medium" }, { "value": "h1", "label": "Large" }, { "value": "h0", "label": "Extra large" }
    ], "default": "h1", "label": "Heading size" },
    { "type": "color_scheme", "id": "color_scheme", "label": "Color scheme", "default": "scheme-1" },
    { "type": "header", "content": "Padding" },
    { "type": "range", "id": "padding_top", "min": 0, "max": 100, "step": 4, "unit": "px", "label": "Top padding", "default": 36 },
    { "type": "range", "id": "padding_bottom", "min": 0, "max": 100, "step": 4, "unit": "px", "label": "Bottom padding", "default": 36 }
  ],
  "presets": [ { "name": "Withdrawal form" } ]
}
{% endschema %}
```

- [ ] **Step 2: Lint**

Run: `shopify theme check --path . --output json 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print([o for o in d if 'withdrawal-form.liquid' in o['path']])"`
Expected: `[]` (no offenses for the new file).

- [ ] **Step 3: Commit**

```bash
git add sections/withdrawal-form.liquid
git commit -m "feat(theme): withdrawal-form section (native contact form, stable field names)"
```

### Task 3: Create the confirmation-modal JS (two-step)

**Files:** Create `assets/withdrawal-form.js`

- [ ] **Step 1: Write the asset**

```javascript
// Two-step confirmation for the withdrawal form + honeypot guard.
(function () {
  var btn = document.querySelector('[data-withdrawal-submit]');
  if (!btn) return;
  var form = btn.closest('form');
  if (!form) return;
  var confirmed = false;

  form.addEventListener('submit', function (e) {
    // Honeypot: silently drop bot submissions.
    var hp = form.querySelector('input[name="contact[Website]"]');
    if (hp && hp.value) { e.preventDefault(); return; }
    if (confirmed) return; // second pass: let it submit

    e.preventDefault();
    var orderInput = form.querySelector('input[name="contact[Order number]"]');
    var order = orderInput && orderInput.value ? orderInput.value : '';
    openModal(order);
  });

  function openModal(order) {
    var body = (btn.getAttribute('data-confirm-body') || '').replace('[order]', order ? ('#' + order.replace(/^#/, '')) : '');
    var overlay = document.createElement('div');
    overlay.className = 'withdrawal-modal';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.innerHTML =
      '<div class="withdrawal-modal__box">' +
      '<h2>' + esc(btn.getAttribute('data-confirm-title')) + '</h2>' +
      '<p>' + esc(body) + '</p>' +
      '<div class="withdrawal-modal__actions">' +
      '<button type="button" class="button" data-ok>' + esc(btn.getAttribute('data-confirm-ok')) + '</button>' +
      '<button type="button" class="button button--secondary" data-cancel>' + esc(btn.getAttribute('data-confirm-cancel')) + '</button>' +
      '</div></div>';
    document.body.appendChild(overlay);
    var okBtn = overlay.querySelector('[data-ok]');
    okBtn.focus();
    okBtn.addEventListener('click', function () { confirmed = true; close(overlay); form.requestSubmit ? form.requestSubmit() : form.submit(); });
    overlay.querySelector('[data-cancel]').addEventListener('click', function () { close(overlay); });
    overlay.addEventListener('click', function (e) { if (e.target === overlay) close(overlay); });
    document.addEventListener('keydown', escClose);
    function escClose(e) { if (e.key === 'Escape') { close(overlay); document.removeEventListener('keydown', escClose); } }
  }

  function close(el) { if (el && el.parentNode) el.parentNode.removeChild(el); }
  function esc(s) { var d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }
})();
```

- [ ] **Step 2: Lint the theme (no JS offenses expected)**

Run: `shopify theme check --path . --output json 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print([o for o in d if 'withdrawal-form' in o['path']])"`
Expected: `[]`

- [ ] **Step 3: Commit**

```bash
git add assets/withdrawal-form.js
git commit -m "feat(theme): withdrawal-form confirmation modal + honeypot"
```

### Task 4: Preview on staging + verify the notification email format

**Files:** none (preview + manual test)

- [ ] **Step 1: Land on staging and push**

```bash
git checkout staging && git merge --ff-only <scratch-branch> && git push origin staging && git checkout ops
```
(If not fast-forwardable, rebase the scratch branch onto staging first.)

- [ ] **Step 2: Create a temporary preview page** — in the preview theme's editor, create a page using a template that includes the **Withdrawal form** section (Task 5 makes this permanent; for now add the section to any page to preview).

- [ ] **Step 3: Visual check (NL + EN)** — open the page in both locales.
Expected: form renders on-brand; clicking **"Herroep hier uw contract / Withdraw from contract here"** opens the confirmation modal showing the entered order #; **Confirm** submits; the success message shows.

- [ ] **Step 4: Verify the notification email body is parseable** — submit a real test (use a test order #). Open the email Shopify sends to the store address.
Expected: the body contains stable lines including `Order number: <value>`, `Request type: withdrawal_request`, `Locale: nl` (or `en`), and the **Reply-To is the address entered**. Record the exact line format of `Order number:` for the Apps Script regex.

---

## Phase B — Admin entry points (merchant)

### Task 5: Publish the `/herroeping` page

- [ ] **Step 1:** Online Store → Pages → Add page, title NL "Herroeping" (and EN translation), handle **`herroeping`**.
- [ ] **Step 2:** Assign a template that renders the **Withdrawal form** section (create a `page.withdrawal` template in the theme editor and add the section), or add the section to the page via the editor.
- [ ] **Step 3 (verify):** open `/pages/herroeping` logged-out in NL and EN → form renders, no login required.

### Task 6: Footer link

- [ ] **Step 1:** Online Store → Navigation → edit the **Footer menu** → add an item labelled **"Herroep hier uw contract"** (EN: "Withdraw from contract here") linking to `/pages/herroeping`. Translate the label via Translate & Adapt.
- [ ] **Step 2 (verify):** the link shows in the footer on every page (continuous availability) in both locales.

### Task 7: Order-confirmation email link

- [ ] **Step 1:** Settings → Notifications → Order confirmation → add a line linking to `/pages/herroeping` with the label "Herroep hier uw contract / Withdraw from contract here".
- [ ] **Step 2 (verify):** place a test order → the confirmation email contains the working link.

---

## Phase C — Google Workspace acknowledgement (merchant)

### Task 8: Gmail filter + labels

- [ ] **Step 1:** In Gmail (the store-notification mailbox) create labels `withdrawal`, `withdrawal-done`, `withdrawal-review`, `withdrawal-error`.
- [ ] **Step 2:** Create a filter — **Has the words:** `withdrawal_request` (matches the hidden `Request type` field) → **Apply label:** `withdrawal` (and optionally "Skip Inbox" off, so you still see them).
- [ ] **Step 3 (verify):** the Task-4 test email is now labelled `withdrawal`.

### Task 9: Apps Script acknowledgement

- [ ] **Step 1:** Go to script.google.com → New project → paste the script below. Adjust `ORDER_RE` only if Task 4 Step 4 showed a different `Order number:` line format.

```javascript
// Auto-acknowledges withdrawal requests (Art. 11a receipt). Idempotent via labels.
var SENDER_NAME = 'Zo Gezeept';
var ORDER_RE = /Order number:\s*#?\s*([A-Za-z0-9\-]+)/i;
var LOCALE_RE = /Locale:\s*([a-z]{2})/i;
var HONEYPOT_RE = /Website:\s*(\S.*)/i;

function processWithdrawals() {
  var src = GmailApp.getUserLabelByName('withdrawal');
  var done = GmailApp.getUserLabelByName('withdrawal-done');
  var review = GmailApp.getUserLabelByName('withdrawal-review');
  var errLabel = GmailApp.getUserLabelByName('withdrawal-error');
  var threads = GmailApp.search('label:withdrawal -label:withdrawal-done -label:withdrawal-review -label:withdrawal-error', 0, 50);

  threads.forEach(function (thread) {
    try {
      var msg = thread.getMessages()[0];
      var body = msg.getPlainBody();
      if (HONEYPOT_RE.test(body)) { thread.addLabel(review); return; } // bot
      var to = (msg.getReplyTo() || '').trim();
      var order = (body.match(ORDER_RE) || [])[1] || '';
      var loc = ((body.match(LOCALE_RE) || [])[1] || '').toLowerCase();
      if (!to || !order) { thread.addLabel(review); return; } // needs manual handling
      sendAck(to, order, loc);
      thread.addLabel(done);
    } catch (e) {
      thread.addLabel(errLabel);
      GmailApp.sendEmail(Session.getActiveUser().getEmail(), 'Withdrawal ack error', String(e));
    }
  });
}

function sendAck(to, order, loc) {
  var nl = loc.indexOf('nl') === 0;
  var subject = nl
    ? 'Ontvangstbevestiging herroeping — bestelling #' + order
    : 'Withdrawal request received — order #' + order;
  var html = nl
    ? '<p>Beste klant,</p><p>We hebben je herroepingsverzoek voor bestelling <strong>#' + order +
      '</strong> ontvangen op ' + nowStr('nl') + '. Dit is een ontvangstbevestiging; we verwerken je verzoek en nemen contact op als we iets moeten verduidelijken.</p><p>Met vriendelijke groet,<br>' + SENDER_NAME + '</p>'
    : '<p>Dear customer,</p><p>We have received your withdrawal request for order <strong>#' + order +
      '</strong> on ' + nowStr('en') + '. This is a confirmation of receipt; we will process your request and contact you if anything needs clarifying.</p><p>Kind regards,<br>' + SENDER_NAME + '</p>';
  GmailApp.sendEmail(to, subject, html.replace(/<[^>]+>/g, ''), { htmlBody: html, name: SENDER_NAME });
}

function nowStr(loc) {
  var tz = Session.getScriptTimeZone();
  return Utilities.formatDate(new Date(), tz, "yyyy-MM-dd HH:mm '(" + tz + ")'");
}
```

- [ ] **Step 2:** Run `processWithdrawals` once manually → approve the GmailApp permission scopes.
- [ ] **Step 3:** Triggers (clock icon) → Add trigger → `processWithdrawals`, **Time-driven → Minutes timer → Every minute**.
- [ ] **Step 4 (verify):** with the Task-4 test thread labelled `withdrawal`, run once → the test thread gets `withdrawal-done` and the **submitted email address receives the acknowledgement** (NL or EN per locale), containing the order # + timestamp, worded as *receipt* (not acceptance).

### Task 10: End-to-end + edge cases

- [ ] **Step 1:** Full happy path — submit on `/herroeping` (real-looking order #) → within ~1 min the acknowledgement arrives at the submitted email.
- [ ] **Step 2:** Honeypot — fill the hidden `Website` field via devtools and submit → no acknowledgement; thread labelled `withdrawal-review`.
- [ ] **Step 3:** Missing/garbled order # — submit with order # blank-ish → thread labelled `withdrawal-review` (no auto-send), you handle manually.
- [ ] **Step 4:** Confirm the acknowledgement wording is **receipt-only** (no "confirmed/refunded") per spec §6.

---

## Phase D — Land (gated)
- [ ] `dawn-harvest` → lift `sections/withdrawal-form.liquid`, `assets/withdrawal-form.js`, and the `withdrawal_form` locale strings into `customizations` (L1).
- [ ] Rebuild `staging` on `customizations` (config snapshot at tip); push.
- [ ] `dawn-promote` → `staging` → `current` (gated; live confirm).

## Deferred (spec §8 — not this plan)
- T&C + return/refund policy review (NL/EN).
- Privacy-policy one-line note: withdrawal/communication data handled via Google Workspace.
- Optional workshop-page edit ("if the workshop doesn't run, full refund") + EN check.

---

## Self-review
- **Spec coverage:** function/label/availability → Tasks 2,5,6,7; statement + order-level id → Task 2; two-step → Task 3; acknowledgement (durable, content+timestamp, receipt-only) → Task 9; no-login → Task 5; bilingual → Tasks 1,9; GDPR/no-new-processor → inherent (Workspace); workshops exempt → out of scope; deferred items → listed. ✓
- **Field-name consistency:** `contact[Order number]`, `contact[email]`, `contact[Request type]`=`withdrawal_request`, `contact[Locale]`, `contact[Website]` (honeypot) are used identically across Tasks 2, 4, 8, 9. ✓
- **Parser consistency:** `ORDER_RE`/`LOCALE_RE`/`HONEYPOT_RE` match the field labels emitted by Task 2; Task 4 Step 4 captures the real format to confirm/adjust. ✓
- **No placeholders:** full code in every code step; verification via theme-check/JSON/preview/Apps-Script (no fake test harness). ✓
