# EU Withdrawal — Completion / Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the EU withdrawal-function topic to full compliance — add a gated footer link to the withdrawal page (appended to the existing `shop.policies` row), complete the legal text (T&C/return-refund, privacy note, workshop line), and land it live via the dawn-ops flow.

**Architecture:** A surgical, safely-degrading change to `sections/footer.liquid` adds three footer settings and appends one gated `<li>` (label = the linked page's own title) to the existing policy links list, plus an optional stacked bottom layout. The withdrawal form/page/modal/Apps Script are already built and tested (v2). Legal text and admin toggles are merchant actions Claude guides. The change lands via staging → harvest → backflow → promote.

**Tech Stack:** Dawn/Liquid, `{% schema %}` settings (`page` picker, checkboxes), `{% style %}`, `theme-check`, Shopify admin (Pages, Policies, Translate & Adapt, theme editor), dawn-ops skills (`dawn-harvest`, `dawn-backflow`, `dawn-promote`).

**Source spec:** [docs/superpowers/specs/2026-07-01-eu-withdrawal-completion-design.md](../specs/2026-07-01-eu-withdrawal-completion-design.md)

> **Disclaimer:** Not legal advice. The T&C/return-refund rewrite (Task 6) is a legal-judgment call; validate with counsel.

---

## Owner legend

- **[AGENT]** — Claude does end-to-end (theme code, git, skills, verification).
- **[MERCHANT]** — Filippo performs in Shopify admin; Claude provides exact steps / drafts content.
- **[SHARED]** — Claude verifies technically; Filippo eyeballs / authorizes.

## Verification reality
The theme has no Liquid unit-test harness. Theme tasks verify via `theme-check` (no new offenses for the changed file) + JSON schema validity + a real preview submission on staging. There is no fake test harness.

## Layer-ops workflow
Develop theme tasks (1–3) on a scratch branch off `staging`; preview by pushing to `staging` (Shopify↔GitHub integration updates the linked preview theme). After validation: `dawn-harvest` the L1 change into `customizations`, rebuild `staging`, `dawn-backflow` live config, `dawn-promote` → `current` (gated, live confirm). `current` is never hand-edited.

## File structure
| File | Responsibility | Owner |
|---|---|---|
| `sections/footer.liquid` (modify — schema) | Add `show_withdrawal_link`, `withdrawal_page`, `policies_own_line` settings | [AGENT] |
| `sections/footer.liquid` (modify — markup + style) | Append gated withdrawal `<li>` to the policies list; optional stacked layout | [AGENT] |
| Shopify page `herroeping` title (NL/EN) | Footer link label via page title | [MERCHANT] |
| Theme editor footer settings | Enable toggles + pick page (L2 config) | [MERCHANT] |
| Policies: return/refund + T&C; Privacy; Workshop page | Legal text | [MERCHANT] (Claude drafts) |

---

## Phase A — Theme (L1), scratch branch off `staging`

### Task 0: Create the scratch branch  — [AGENT]

**Files:** none

- [ ] **Step 1: Branch off staging**

```bash
git fetch origin && git checkout staging && git pull --ff-only && git checkout -b withdrawal-footer-link
```

### Task 1: Add the three footer settings — [AGENT]

**Files:** Modify `sections/footer.liquid` (schema `settings` array, immediately after the `show_policy` setting)

- [ ] **Step 1: Insert the settings after `show_policy`**

Find this block in the `{% schema %}` `"settings"` array:

```json
    {
      "type": "checkbox",
      "id": "show_policy",
      "default": true,
      "label": "t:sections.footer.settings.show_policy.label",
      "info": "t:sections.footer.settings.show_policy.info"
    },
```

Insert immediately after it (before the next `{ "type": "header", ... }`):

```json
    {
      "type": "header",
      "content": "Withdrawal link"
    },
    {
      "type": "checkbox",
      "id": "show_withdrawal_link",
      "default": false,
      "label": "Show withdrawal link in legal links",
      "info": "Appends a link (e.g. the right-of-withdrawal page) to the end of the policy links row. Label comes from the selected page's title."
    },
    {
      "type": "page",
      "id": "withdrawal_page",
      "label": "Withdrawal page"
    },
    {
      "type": "checkbox",
      "id": "policies_own_line",
      "default": false,
      "label": "Show legal links on their own line",
      "info": "Places the legal links on a separate line below the copyright notice."
    },
```

- [ ] **Step 2: Validate the schema JSON**

Run: `git show HEAD:sections/footer.liquid > /tmp/footer-orig.liquid; ruby -e "require 'json'; s=File.read('sections/footer.liquid'); JSON.parse(s[/\{% schema %\}(.+?)\{% endschema %\}/m,1]); puts 'SCHEMA OK'"`
Expected: `SCHEMA OK`

- [ ] **Step 3: theme-check (no new offenses for footer.liquid)**

Run: `shopify theme check --path . --output json 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print([o for f in d for o in f.get('offenses',[]) if 'footer.liquid' in f.get('path','')])"`
Expected: `[]`

- [ ] **Step 4: Commit**

```bash
git add sections/footer.liquid
git commit -m "feat(footer): add withdrawal-link + own-line settings (schema)"
```

### Task 2: Append the gated withdrawal link + optional stacked layout — [AGENT]

**Files:** Modify `sections/footer.liquid` (the `.footer__copyright` block near the bottom, currently the `show_policy` render block)

- [ ] **Step 1: Replace the policy-render block**

Find exactly:

```liquid
      <div class="footer__copyright caption">
        <small class="copyright__content"
          >&copy; {{ 'now' | date: '%Y' }}, {{ shop.name | link_to: routes.root_url -}}
        </small>
        <small class="copyright__content">{{ powered_by_link }}</small>
        {%- if section.settings.show_policy -%}
          <ul class="policies list-unstyled">
            {%- for policy in shop.policies -%}
              {%- if policy != blank -%}
                <li>
                  <small class="copyright__content"
                    ><a href="{{ policy.url }}">{{ policy.title | escape }}</a></small
                  >
                </li>
              {%- endif -%}
            {%- endfor -%}
          </ul>
        {%- endif -%}
      </div>
```

Replace with:

```liquid
      <div class="footer__copyright caption{% if section.settings.policies_own_line %} footer__copyright--stacked{% endif %}">
        <small class="copyright__content"
          >&copy; {{ 'now' | date: '%Y' }}, {{ shop.name | link_to: routes.root_url -}}
        </small>
        <small class="copyright__content">{{ powered_by_link }}</small>
        {%- if section.settings.show_policy or section.settings.show_withdrawal_link -%}
          <ul class="policies list-unstyled">
            {%- if section.settings.show_policy -%}
              {%- for policy in shop.policies -%}
                {%- if policy != blank -%}
                  <li>
                    <small class="copyright__content"
                      ><a href="{{ policy.url }}">{{ policy.title | escape }}</a></small
                    >
                  </li>
                {%- endif -%}
              {%- endfor -%}
            {%- endif -%}
            {%- if section.settings.show_withdrawal_link and section.settings.withdrawal_page != blank -%}
              <li>
                <small class="copyright__content"
                  ><a href="{{ section.settings.withdrawal_page.url }}">{{ section.settings.withdrawal_page.title | escape }}</a></small
                >
              </li>
            {%- endif -%}
          </ul>
        {%- endif -%}
      </div>
```

- [ ] **Step 2: Add the stacked-layout style**

Immediately before the closing `</footer>` tag (end of the section markup, before `{% schema %}`), add:

```liquid
{%- style -%}
  .footer__copyright--stacked { display: flex; flex-wrap: wrap; justify-content: center; align-items: center; }
  .footer__copyright--stacked .policies { flex-basis: 100%; margin-top: 1rem; justify-content: center; }
{%- endstyle -%}
```

- [ ] **Step 3: theme-check (no new offenses for footer.liquid)**

Run: `shopify theme check --path . --output json 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print([o for f in d for o in f.get('offenses',[]) if 'footer.liquid' in f.get('path','')])"`
Expected: `[]`

- [ ] **Step 4: Commit**

```bash
git add sections/footer.liquid
git commit -m "feat(footer): append gated withdrawal link + optional stacked legal-links line"
```

### Task 3: Preview on staging + validate — [SHARED]

**Files:** none (preview + manual test)

- [ ] **Step 1: Land on staging and push** — [AGENT]

```bash
git checkout staging && git merge --ff-only withdrawal-footer-link && git push origin staging && git checkout withdrawal-footer-link
```
(If not fast-forwardable, rebase `withdrawal-footer-link` onto `staging` first.)

- [ ] **Step 2 (MERCHANT): Set the withdrawal page title in both locales** — Shopify admin → Online Store → Pages → the withdrawal page (`herroeping`): set NL title "Herroep hier uw contract". Then Translate & Adapt → Pages → the withdrawal page → EN title "Withdraw from contract here".

- [ ] **Step 3 (MERCHANT): Enable the settings on the staging preview theme** — Theme editor (preview/staging theme) → Footer section settings → tick **Show withdrawal link in legal links**, set **Withdrawal page** to the withdrawal page, and (optional) tick **Show legal links on their own line**. Save.

- [ ] **Step 4 (SHARED): Validate in NL + EN** — open the storefront footer in both locales.
Expected: the withdrawal link appears **at the end** of the existing legal links row, labelled from the page title ("Herroep hier uw contract" / "Withdraw from contract here"), and resolves to the withdrawal page. All seven prior policy links (incl. Cookievoorkeuren) still render unchanged. If "own line" is enabled, the bottom reads as payments / copyright / legal-links rows. No login required.

---

## Phase B — Legal text (merchant; Claude drafts) — [MERCHANT]

> Policy/page content lives in Shopify admin, not the theme. Claude drafts NL + EN; Filippo reviews (counsel for the T&C/return-refund) and pastes into admin.

### Task 4: Privacy-policy one-line note — [MERCHANT] (Claude drafts)

**Files:** none (Shopify admin → Settings → Policies → Privacy policy)

- [ ] **Step 1 (AGENT): Draft the line (NL + EN)** — e.g.
  - NL: "Voor klantcommunicatie en de afhandeling van herroepingsverzoeken maken we gebruik van Google Workspace (Google Ireland Ltd.). De verwerking valt onder de bestaande Google Workspace-gegevensverwerkingsovereenkomst."
  - EN: "For customer communication and handling of withdrawal requests we use Google Workspace (Google Ireland Ltd.). This processing falls under the existing Google Workspace Data Processing Agreement."
- [ ] **Step 2 (MERCHANT): Review + paste** into the Privacy policy (NL), and its EN translation via Translate & Adapt → Policies.
- [ ] **Step 3 (SHARED): Verify** the line appears in the published privacy policy in both locales.

### Task 5: Workshop-page edit + EN check — [MERCHANT] (Claude drafts)

**Files:** none (the workshop product/page in admin)

- [ ] **Step 1 (AGENT): Draft the reassurance line** — NL: "Als de workshop niet doorgaat, krijg je het volledige bedrag terug." EN: "If the workshop does not go ahead, you receive a full refund."
- [ ] **Step 2 (MERCHANT): Add the line** to the workshop cancellation text (NL) and confirm/add the **EN** version via Translate & Adapt.
- [ ] **Step 3 (SHARED): Verify** the workshop page shows the line in both locales and an EN version of the cancellation terms exists.

### Task 6: T&C + return/refund policy review — [MERCHANT] (Claude drafts, counsel validates)

**Files:** none (Settings → Policies → Refund policy + Terms of service)

- [ ] **Step 1 (AGENT): Draft** the return/refund + T&C text (NL + EN) covering: the 14-day right of withdrawal for physical goods, how to exercise it (link to the withdrawal page), the withdrawal deadline, return conditions and who bears return costs, refund timing, and the workshop exemption (fixed-date service). Provide as reviewable drafts, not final.
- [ ] **Step 2 (MERCHANT/counsel): Review + finalize** the text (this is the legal-judgment-heavy item).
- [ ] **Step 3 (MERCHANT): Publish** into the Refund policy + Terms of service, with EN via Translate & Adapt.
- [ ] **Step 4 (SHARED): Verify** both policies read consistently with the withdrawal function in both locales.

---

## Phase C — Land (gated)

### Task 7: Harvest the footer change into `customizations` — [AGENT]

**Files:** `sections/footer.liquid` (L1)

- [ ] **Step 1: Run dawn-harvest** — invoke the `dawn-harvest` skill to classify and lift the `sections/footer.liquid` change (generic L1 — degrades to vanilla when toggles off) into `customizations` as a single commit.
- [ ] **Step 2: Verify** — confirm `customizations` contains the footer change and `theme-check` reports no new offenses.

### Task 8: Backflow live config + rebuild staging — [AGENT]

**Files:** config snapshot (L2)

- [ ] **Step 1: Run dawn-backflow** — invoke the `dawn-backflow` skill to capture live admin/config edits (including the footer section-setting values: `show_withdrawal_link`, `withdrawal_page`, `policies_own_line`) from `current` into the staging snapshot.
- [ ] **Step 2: Verify** — `staging` reflects the intended footer settings and is rebuilt on `customizations` tip.

### Task 9: Promote to live — [SHARED]

**Files:** none

- [ ] **Step 1 (MERCHANT): Confirm the legal text (Tasks 4–6) is published** and the staging preview looks correct.
- [ ] **Step 2 (SHARED): Run dawn-promote** — invoke the `dawn-promote` skill (`staging` → `current`), which requires explicit live confirmation from Filippo. This is the moment the withdrawal link becomes live-visible.
- [ ] **Step 3 (SHARED): Final live check** — the withdrawal link renders at the end of the footer legal links in NL + EN, resolves to the withdrawal page, no login; a real submission still triggers the Apps Script acknowledgement (v2, already tested).

---

## Deferred / out of scope
- Order-confirmation email link (spec §3) — intentionally dropped.
- Rebuilding the withdrawal form / modal / Apps Script — already done and tested (v2).

## Self-review
- **Spec coverage:** footer link append + gating → Tasks 1–2; page-title label → Task 3 Step 2; stacked layout → Tasks 2–3; land via harvest/backflow/promote → Tasks 7–9; privacy note → Task 4; workshop edit → Task 5; T&C/return-refund → Task 6; order-email dropped + form done → Deferred. ✓
- **Settings consistency:** `show_withdrawal_link`, `withdrawal_page`, `policies_own_line` are defined in Task 1 and used identically in Task 2 markup, Task 3 (theme editor), and Task 8 (backflow). ✓
- **Degrades to vanilla:** both new checkboxes default `false`; the `<ul>` renders only when `show_policy or show_withdrawal_link`; the withdrawal `<li>` requires `show_withdrawal_link and withdrawal_page != blank`. ✓
- **No placeholders:** full code/labels/drafts in every code+content step; verification via theme-check/JSON/preview + skill runs. ✓
