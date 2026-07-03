# Align Withdrawal Form With Contact Form — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the incidental drift between `sections/withdrawal-form.liquid` and `sections/contact-form.liquid` (scroll-reveal, CSS delivery, heading accessibility, field layout, per-field error handling) without touching any of the differences withdrawal's confirm-modal/email-parsing requirements genuinely force.

**Architecture:** `sections/contact-form.liquid` is the frozen baseline — it does not change. All edits land in `sections/withdrawal-form.liquid`, plus two locale files for one new translation key. No JavaScript changes: `assets/withdrawal-form.js` selects elements by `id`/`name` attributes, none of which move.

**Tech Stack:** Shopify Liquid theme (Dawn fork), `shopify theme check` for static linting, no JS/unit test framework in this repo.

**Spec:** `docs/superpowers/specs/2026-07-03-align-contact-withdrawal-forms-design.md`

---

## File structure

- Modify: `sections/withdrawal-form.liquid` — all six alignment changes.
- Modify: `locales/en.default.json` — add `withdrawal_form.title` (visually-hidden heading fallback).
- Modify: `locales/nl.json` — same key, Dutch value.
- No changes: `sections/contact-form.liquid`, `assets/withdrawal-form.js`, `assets/section-contact-form.css`.

## One note on scope vs. the spec

Spec §2b item 6 says to "reshape the control flow to mirror contact-form's nesting depth." Implemented literally, that would make the withdrawal form's fields render unconditionally after `{%- endform -%}`'s opening `if/elsif/else`, the way contact-form's do — but contact-form intentionally keeps showing its fields after a successful post, and withdrawal-form intentionally does **not** (so a customer can't accidentally resubmit a legal withdrawal request, and so `preview_success` shows a clean success-only state in the editor). That hide-everything-after-success behavior is required by the `preview_success`/`success_message` feature the spec explicitly keeps in §2a. This plan preserves withdrawal's outer `if show_success / else` structure and only upgrades the *inner* `if form.errors` block to match contact-form's fuller per-field markup (Task 4) — that's the part of "nesting" that was actually incidental drift.

---

### Task 1: Branch setup

**Files:** none (git only)

- [ ] **Step 1: Fetch and create a scratch branch off `staging`**

```bash
git fetch origin
git checkout -b align-contact-withdrawal-forms staging
```

- [ ] **Step 2: Confirm the working file matches the spec's documented baseline**

```bash
wc -l sections/withdrawal-form.liquid
grep -c "scroll-trigger\|contact__fields" sections/withdrawal-form.liquid
```

Expected: `223 sections/withdrawal-form.liquid`, then `0` (no scroll-trigger or contact__fields present yet).

No commit — this task only sets up the branch.

---

### Task 2: Relocate CSS into the `{%- style -%}` tag

**Files:**
- Modify: `sections/withdrawal-form.liquid:1-3` (insert) and `:126-192` (remove old block)

- [ ] **Step 1: Insert the `{%- style -%}` block after the asset_url line**

In `sections/withdrawal-form.liquid`, replace:

```liquid
{{ 'section-contact-form.css' | asset_url | stylesheet_tag }}

<div class="color-{{ section.settings.color_scheme }} gradient">
```

with:

```liquid
{{ 'section-contact-form.css' | asset_url | stylesheet_tag }}

{%- style -%}
  .section-{{ section.id }}-padding {
    padding-top: {{ section.settings.padding_top | times: 0.75 | round: 0 }}px;
    padding-bottom: {{ section.settings.padding_bottom | times: 0.75 | round: 0 }}px;
  }
  @media screen and (min-width: 750px) {
    .section-{{ section.id }}-padding {
      padding-top: {{ section.settings.padding_top }}px;
      padding-bottom: {{ section.settings.padding_bottom }}px;
    }
  }
  .withdrawal-form__hp {
    position: absolute !important;
    left: -9999px !important;
    height: 0;
    overflow: hidden;
  }
  .withdrawal-form__help {
    display: block;
    margin-top: 0.4rem;
    opacity: 0.75;
  }
  .withdrawal-modal[hidden] {
    display: none;
  }
  .withdrawal-modal {
    position: fixed;
    inset: 0;
    display: grid;
    place-items: center;
    background: rgba(0, 0, 0, 0.5);
    z-index: 100;
  }
  .withdrawal-modal__box {
    background: rgb(var(--color-background));
    color: rgb(var(--color-foreground));
    max-width: 30rem;
    margin: 1rem;
    padding: 2rem;
    border-radius: var(--popup-corner-radius, 8px);
  }
  .withdrawal-modal__actions {
    display: flex;
    gap: 1rem;
    margin-top: 1.5rem;
    flex-wrap: wrap;
  }
  .withdrawal-modal__highlight {
    font-weight: inherit;
    color: rgb(var(--color-link));
  }
  /* Match .rte a's lighter/underlined link treatment for the merchant-authored
     mailto link in the success message, without overriding its heading font. */
  .section-{{ section.id }}-padding .form__message a {
    color: rgba(var(--color-link), var(--alpha-link));
    text-decoration: underline;
    text-underline-offset: 0.3rem;
    text-decoration-thickness: 0.1rem;
    transition: text-decoration-thickness var(--duration-short) ease;
  }
  .section-{{ section.id }}-padding .form__message a:hover {
    color: rgb(var(--color-link));
    text-decoration-thickness: 0.2rem;
  }
{%- endstyle -%}

<div class="color-{{ section.settings.color_scheme }} gradient">
```

- [ ] **Step 2: Remove the old trailing `<style>` block**

Replace:

```liquid
  </div>
</div>

<style>
  .section-{{ section.id }}-padding {
    padding-top: {{ section.settings.padding_top | times: 0.75 | round: 0 }}px;
    padding-bottom: {{ section.settings.padding_bottom | times: 0.75 | round: 0 }}px;
  }
  @media screen and (min-width: 750px) {
    .section-{{ section.id }}-padding {
      padding-top: {{ section.settings.padding_top }}px;
      padding-bottom: {{ section.settings.padding_bottom }}px;
    }
  }
  .withdrawal-form__hp {
    position: absolute !important;
    left: -9999px !important;
    height: 0;
    overflow: hidden;
  }
  .withdrawal-form__help {
    display: block;
    margin-top: 0.4rem;
    opacity: 0.75;
  }
  .withdrawal-modal[hidden] {
    display: none;
  }
  .withdrawal-modal {
    position: fixed;
    inset: 0;
    display: grid;
    place-items: center;
    background: rgba(0, 0, 0, 0.5);
    z-index: 100;
  }
  .withdrawal-modal__box {
    background: rgb(var(--color-background));
    color: rgb(var(--color-foreground));
    max-width: 30rem;
    margin: 1rem;
    padding: 2rem;
    border-radius: var(--popup-corner-radius, 8px);
  }
  .withdrawal-modal__actions {
    display: flex;
    gap: 1rem;
    margin-top: 1.5rem;
    flex-wrap: wrap;
  }
  .withdrawal-modal__highlight {
    font-weight: inherit;
    color: rgb(var(--color-link));
  }
  /* Match .rte a's lighter/underlined link treatment for the merchant-authored
     mailto link in the success message, without overriding its heading font. */
  .section-{{ section.id }}-padding .form__message a {
    color: rgba(var(--color-link), var(--alpha-link));
    text-decoration: underline;
    text-underline-offset: 0.3rem;
    text-decoration-thickness: 0.1rem;
    transition: text-decoration-thickness var(--duration-short) ease;
  }
  .section-{{ section.id }}-padding .form__message a:hover {
    color: rgb(var(--color-link));
    text-decoration-thickness: 0.2rem;
  }
</style>

<script src="{{ 'withdrawal-form.js' | asset_url }}" defer="defer"></script>
```

with:

```liquid
  </div>
</div>

<script src="{{ 'withdrawal-form.js' | asset_url }}" defer="defer"></script>
```

- [ ] **Step 3: Lint**

```bash
shopify theme check 2>&1 | grep -A5 "withdrawal-form.liquid"
```

Expected: no output (no offenses reference the file).

- [ ] **Step 4: Commit**

```bash
git add sections/withdrawal-form.liquid
git commit -m "Move withdrawal-form CSS into the style tag, matching contact-form"
```

---

### Task 3: Scroll-reveal animation + heading accessibility fallback

**Files:**
- Modify: `sections/withdrawal-form.liquid` (heading block + form tag)
- Modify: `locales/en.default.json`
- Modify: `locales/nl.json`

- [ ] **Step 1: Add the `withdrawal_form.title` locale key (English)**

In `locales/en.default.json`, replace:

```json
  "withdrawal_form": {
    "name_label": "Name",
```

with:

```json
  "withdrawal_form": {
    "title": "Withdrawal form",
    "name_label": "Name",
```

- [ ] **Step 2: Add the `withdrawal_form.title` locale key (Dutch)**

In `locales/nl.json`, replace:

```json
  "withdrawal_form": {
    "name_label": "Naam",
```

with:

```json
  "withdrawal_form": {
    "title": "Herroepingsformulier",
    "name_label": "Naam",
```

- [ ] **Step 3: Validate both JSON files parse**

```bash
python3 -m json.tool locales/en.default.json > /dev/null && echo OK
python3 -m json.tool locales/nl.json > /dev/null && echo OK
```

Expected: `OK` printed twice.

- [ ] **Step 4: Add scroll-trigger + heading fallback + `contact_form_class`**

In `sections/withdrawal-form.liquid`, replace:

```liquid
    {%- if section.settings.heading != blank -%}
      <h2 class="title inline-richtext {{ section.settings.heading_size }}">{{ section.settings.heading }}</h2>
    {%- endif -%}

    {%- form 'contact', id: 'WithdrawalForm', class: 'isolate' -%}
```

with:

```liquid
    {%- if section.settings.heading != blank -%}
      <h2 class="title title-wrapper--no-top-margin inline-richtext {{ section.settings.heading_size }}{% if settings.animations_reveal_on_scroll %} scroll-trigger animate--slide-in{% endif %}">
        {{ section.settings.heading }}
      </h2>
    {%- else -%}
      <h2 class="visually-hidden">{{ 'withdrawal_form.title' | t }}</h2>
    {%- endif -%}
    {%- liquid
      assign contact_form_class = 'isolate'
      if settings.animations_reveal_on_scroll
        assign contact_form_class = 'isolate scroll-trigger animate--slide-in'
      endif
    -%}

    {%- form 'contact', id: 'WithdrawalForm', class: contact_form_class -%}
```

- [ ] **Step 5: Lint**

```bash
shopify theme check 2>&1 | grep -A5 "withdrawal-form.liquid"
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add sections/withdrawal-form.liquid locales/en.default.json locales/nl.json
git commit -m "Add scroll-reveal animation and always-render-an-h2 fallback to withdrawal-form"
```

---

### Task 4: Restore the per-field error list (top error banner)

**Files:**
- Modify: `sections/withdrawal-form.liquid`

- [ ] **Step 1: Add the `<ul>` linking to the email field, matching contact-form**

Replace:

```liquid
        {%- if form.errors -%}
          <div class="form__message">
            <h2 class="form-status caption-large text-body" role="alert" tabindex="-1" autofocus>
              {{- 'icon-error.svg' | inline_asset_content -}}
              {{ 'templates.contact.form.error_heading' | t }}
            </h2>
          </div>
        {%- endif -%}
```

with:

```liquid
        {%- if form.errors -%}
          <div class="form__message">
            <h2 class="form-status caption-large text-body" role="alert" tabindex="-1" autofocus>
              {{- 'icon-error.svg' | inline_asset_content -}}
              {{ 'templates.contact.form.error_heading' | t }}
            </h2>
          </div>
          <ul class="form-status-list caption-large" role="list">
            <li>
              <a href="#WithdrawalForm-email" class="link">
                {{ form.errors.translated_fields.email | capitalize }}
                {{ form.errors.messages.email }}
              </a>
            </li>
          </ul>
        {%- endif -%}
```

- [ ] **Step 2: Lint**

```bash
shopify theme check 2>&1 | grep -A5 "withdrawal-form.liquid"
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add sections/withdrawal-form.liquid
git commit -m "Restore per-field error list for withdrawal-form's email field"
```

---

### Task 5: Group name + email into `.contact__fields`, add inline email error UI

**Files:**
- Modify: `sections/withdrawal-form.liquid`

- [ ] **Step 1: Wrap name + email, add `field--with-error` + `aria-invalid`/`aria-describedby` + inline error `<small>`**

Replace:

```liquid
      {%- comment -%} Stable, NON-localized field names so the notification email is parseable. {%- endcomment -%}
      <div class="field">
        <input
          class="field__input"
          type="text"
          id="WithdrawalForm-name"
          name="contact[Name]"
          value="{% if form.name %}{{ form.name }}{% elsif customer %}{{ customer.name }}{% endif %}"
          placeholder="{{ 'withdrawal_form.name_label' | t }}"
          autocomplete="name"
        >
        <label class="field__label" for="WithdrawalForm-name">{{ 'withdrawal_form.name_label' | t }}</label>
      </div>

      <div class="field">
        <input
          class="field__input"
          type="email"
          id="WithdrawalForm-email"
          name="contact[email]"
          value="{% if form.email %}{{ form.email }}{% elsif customer %}{{ customer.email }}{% endif %}"
          spellcheck="false"
          autocapitalize="off"
          autocomplete="email"
          aria-required="true"
          required
          placeholder="{{ 'withdrawal_form.email_label' | t }}"
        >
        <label class="field__label" for="WithdrawalForm-email">
          {{- 'withdrawal_form.email_label' | t }} <span aria-hidden="true">*</span></label
        >
      </div>
```

with:

```liquid
      {%- comment -%} Stable, NON-localized field names so the notification email is parseable. {%- endcomment -%}
      <div class="contact__fields">
        <div class="field">
          <input
            class="field__input"
            type="text"
            id="WithdrawalForm-name"
            name="contact[Name]"
            value="{% if form.name %}{{ form.name }}{% elsif customer %}{{ customer.name }}{% endif %}"
            placeholder="{{ 'withdrawal_form.name_label' | t }}"
            autocomplete="name"
          >
          <label class="field__label" for="WithdrawalForm-name">{{ 'withdrawal_form.name_label' | t }}</label>
        </div>

        <div class="field field--with-error">
          <input
            class="field__input"
            type="email"
            id="WithdrawalForm-email"
            name="contact[email]"
            value="{% if form.email %}{{ form.email }}{% elsif customer %}{{ customer.email }}{% endif %}"
            spellcheck="false"
            autocapitalize="off"
            autocomplete="email"
            aria-required="true"
            {% if form.errors contains 'email' %}
              aria-invalid="true"
              aria-describedby="WithdrawalForm-email-error"
            {% endif %}
            required
            placeholder="{{ 'withdrawal_form.email_label' | t }}"
          >
          <label class="field__label" for="WithdrawalForm-email">
            {{- 'withdrawal_form.email_label' | t }} <span aria-hidden="true">*</span></label
          >
          {%- if form.errors contains 'email' -%}
            <small class="contact__field-error" id="WithdrawalForm-email-error">
              <span class="visually-hidden">{{ 'accessibility.error' | t }}</span>
              <span class="form__message">
                <span class="svg-wrapper">
                  {{- 'icon-error.svg' | inline_asset_content -}}
                </span>
                {{- form.errors.translated_fields.email | capitalize }}
                {{ form.errors.messages.email -}}
              </span>
            </small>
          {%- endif -%}
        </div>
      </div>
```

- [ ] **Step 2: Lint**

```bash
shopify theme check 2>&1 | grep -A5 "withdrawal-form.liquid"
```

Expected: no output.

- [ ] **Step 3: Full-file sanity check**

```bash
grep -c "scroll-trigger" sections/withdrawal-form.liquid   # expect 2 (heading + form wrapper)
grep -c "contact__fields" sections/withdrawal-form.liquid  # expect 1 (the opening div's class attribute; the closing </div> has no class text to match)
grep -c "{%- style -%}" sections/withdrawal-form.liquid    # expect 1
grep -c "<style>" sections/withdrawal-form.liquid          # expect 0
```

- [ ] **Step 4: Commit**

```bash
git add sections/withdrawal-form.liquid
git commit -m "Group withdrawal-form name+email fields and add inline email error state"
```

---

### Task 6: Manual verification against the spec's success criteria

**Files:** none (verification only)

- [ ] **Step 1: Launch the app for local preview**

Invoke the `run` skill (or whatever this project's established preview workflow is) to serve the theme with these changes live.

- [ ] **Step 2: Scroll-reveal parity**

With the theme setting "Reveal sections on scroll" on (Theme settings → Animations — default is on and not overridden in `config/settings_data.json`), load the Withdrawal page and the Contact page. Confirm both the heading and the form slide in the same way on scroll. If the form sits within the initial viewport (short page), confirm instead — by inspecting the rendered HTML — that both headings/forms carry `scroll-trigger animate--slide-in` classes identically, since the animation itself may not be visually perceptible above the fold (this matches contact-form's existing behavior, not a bug).

- [ ] **Step 3: Layout parity**

Screenshot both pages at mobile (375px) and desktop (1280px) widths. Confirm: on desktop, withdrawal-form's name + email fields sit side by side in the same 2-column layout as contact-form's name + email; on mobile, both stack full-width. Confirm order-number and the statement textarea remain full-width on both breakpoints, matching contact-form's phone/comment layout.

- [ ] **Step 4: Heading fallback**

In the theme editor, temporarily clear the withdrawal-form section's "Heading" setting. Confirm the page still renders an `<h2 class="visually-hidden">Withdrawal form</h2>` (inspect via dev tools — it's not visually visible by design). Restore the heading setting afterward.

- [ ] **Step 5: Confirm-modal flow still works end to end**

Fill in name, email, order number, submit. Confirm the two-step modal opens (repeating order number and email), confirming closes it and submits, cancelling returns to the form without submitting.

- [ ] **Step 6: Honeypot still guards the modal**

In dev tools, set the hidden `contact[Website]` input's value to any non-empty string, then click submit. Confirm the modal does *not* open (matches `assets/withdrawal-form.js`'s `honeypotFilled()` check — unchanged by this plan, but worth confirming the DOM restructuring in Task 5 didn't break the selector).

- [ ] **Step 7: `preview_success` still works**

In the theme editor, check "Preview confirmation message in the editor." Confirm only the success message renders (fields, intro, and button are hidden) — same as before this change, since Task 5/Task 3's restructuring didn't touch the `show_success` branch.

No commit — this task is verification only. If any check fails, fix the relevant task above and re-verify before proceeding.

---

### Task 7: Harvest into `customizations`

**Files:** none (branch operation)

- [ ] **Step 1: Push the scratch branch**

```bash
git push -u origin align-contact-withdrawal-forms
```

- [ ] **Step 2: Run the harvest workflow**

Invoke the `dawn-harvest` skill to classify and lift this branch's commits into `customizations`. Expect it to classify all of them as `L1:` (generic, no store-specific content), per §5 of the spec.

- [ ] **Step 3: Confirm the result**

```bash
git log --oneline -6 customizations
```

Expected: the withdrawal-form alignment work appears as one or more `L1:` commits at the tip of `customizations`.

- [ ] **Step 4: Clean up the scratch branch**

```bash
git branch -d align-contact-withdrawal-forms
git push origin --delete align-contact-withdrawal-forms
```

(Only after confirming Step 3 — don't delete before the harvest lands.)
