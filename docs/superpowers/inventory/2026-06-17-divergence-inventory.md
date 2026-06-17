# Divergence Inventory — `v15.1.0..current`

**Generated:** 2026-06-17
**Base:** v15.1.0 (SHA `177a0ccc`)
**Current tip:** `19de43e2` (`pre-cleanup-backup` tag)
**Total changed files:** 101

## How to use this document

The **Proposed** column is Claude's recommendation with reasoning. The **User ruling** column
is blank — **you fill it in for every row** before any branch is built. You may:
- Write the proposed layer to confirm (e.g. `L1 ✓`)
- Override with a different layer (e.g. `L2a`)
- Add a note (e.g. `L1 — but drop the GTM block`)

For files marked **per-hunk**, the file mixes layers; the ruling should say which hunks go where
(or confirm the proposal).

**Layers:**
- **L1** — generic, upstream-shaped customization (rebases onto each new Dawn release)
- **L2a** — authored store asset (custom file, cherry-pickable, curated commit)
- **L2b** — config snapshot (settings_data.json, section/template JSON — one evolving commit)
- **app-residue (keep)** — app-injected file, active reference found → goes to L2a on staging permanently
- **app-residue (drop)** — app-injected file, no active reference → included in staging v1 for the lossless acceptance test, then removed in a documented curation commit (Task 7b). The `drops.md` file records every removal so any future delta vs `current` is explained.
- **locale-drift** — translation-bot churn (preserved in staging v1 for lossless test; flagged droppable commit; replaced by upstream locales at first Dawn upgrade)
- **L0-noise** — follows upstream (release-notes, etc.) — same treatment as locale-drift

**Strict L1 test:** "Could a stranger drop this file into vanilla Dawn and have it work with zero
edits?" If no → L2a minimum. On the fence → L2a (tiebreaker).

---

## Assets

| File | A/M | Proposed | Conf | Reasoning | User ruling |
|---|---|---|---|---|---|
| `assets/base.css` | M | L1 | med | Core Dawn stylesheet. Changes are likely generic tweaks (font, spacing, color vars). Per-hunk review recommended to confirm no store-specific values are hardcoded. | |
| `assets/global.js` | M | L1 | med | Core Dawn JS. Per-hunk review recommended. | |
| `assets/quick-add.css` | M | L1 | high | Generic Dawn component CSS — no store-specifics expected. | |
| `assets/theme-editor.js` | M | L1 | high | Generic Dawn editor JS. | |
| `assets/component-cart.css` | M | L1 | high | Generic Dawn component CSS. | |
| `assets/component-facets.css` | M | L1 | high | Generic Dawn component CSS. | |
| `assets/component-localization-form.css` | M | L1 | high | Generic Dawn component CSS. | |
| `assets/component-product-logos.css` | A | L2a | med | Added alongside the `custom-product-logos` block in `main-product.liquid`. That block is store-specific (tag-based logo display), so this CSS is too. Could be generalised, but L2a by tiebreaker. | |
| `assets/pandectes-reopen-logo.png` | A | app-residue | high | Pandectes cookie-consent app asset. Propose **keep** (app still has footprint in theme.liquid). | |
| `assets/pandectes-rules.min.js` | A | app-residue | high | Pandectes app JS. Propose **keep**. | |
| `assets/pandectes-settings.json` | A | app-residue | high | Pandectes app config. Propose **keep**. | |
| `assets/pop_36879859845.js` | A | app-residue | med | Popup-app asset (numeric ID suggests auto-generated). No reference found in theme.liquid or settings_data. Propose **drop** (likely unused). | |

---

## Snippets

| File | A/M | Proposed | Conf | Reasoning | User ruling |
|---|---|---|---|---|---|
| `snippets/pandectes-rules.liquid` | A | app-residue | high | Pandectes snippet; rendered directly in `layout/theme.liquid:10`. Propose **keep**. | |
| `snippets/booster-apps-common.liquid` | A | app-residue | high | Booster Apps shared snippet; included in `layout/theme.liquid:310`. Propose **keep** (still referenced). Confirm which Booster app is active in admin. | |
| `snippets/facets.liquid` | M | L1 | med | Core Dawn snippet. Per-hunk review recommended. | |
| `snippets/header-drawer.liquid` | M | L1 | med | Core Dawn snippet. Per-hunk review recommended. | |

---

## Layout

| File | A/M | Proposed | Conf | Reasoning | User ruling |
|---|---|---|---|---|---|
| `layout/theme.liquid` | M | **per-hunk** | — | Mixes three kinds of additions: (1) **app-injected** — Pandectes `{% render 'pandectes-rules' %}` and Booster Apps include (lines 10, 310); (2) **generic L1?** — `{{ shop.metafields.UnlimitedFonts.stylesheet }}` (UnlimitedFonts app or store preference?); (3) **L2a** — Google Tag Manager snippet (store-specific tracking). Proposed split: GTM + UnlimitedFonts = L2a; app renders = app-residue (keep with app files); no pure L1 hunks identified. **Please rule on GTM and UnlimitedFonts.** | |
| `layout/password.liquid` | M | L1 | med | Core layout. Per-hunk review recommended. | |

---

## Sections

| File | A/M | Proposed | Conf | Reasoning | User ruling |
|---|---|---|---|---|---|
| `sections/header.liquid` | M | L1 | med | Core section. Per-hunk review recommended. | |
| `sections/main-product.liquid` | M | **per-hunk** | — | Two distinct additions: (1) **L1** — inventory-status enhancements (`availability_type`, `high_stock_threshold`, `inventory_status_prefix`) — generic, configurable, no store references; (2) **L2a** — `custom-product-logos` block (tag-based logo display with `selected_image_1/2`, `product_tag_1/2`) — store-specific concept even if the code is clean. Also references `component-product-logos.css`. Proposed split: inventory-status hunks → L1; product-logos block → L2a. | |
| `sections/pickup-availability.liquid` | M | L1 | med | "Adjust pickup availability for items present in only 1 location" per commit history. Generic enhancement — no store-specific references expected. | |
| `sections/email-signup-banner.liquid` | M | L1 | med | Core section. Per-hunk review recommended. | |
| `sections/header-group.json` | M | L2b | high | Section/block placement config snapshot. | |
| `sections/footer-group.json` | M | L2b | high | Section/block placement config snapshot. | |

---

## Templates

| File | A/M | Proposed | Conf | Reasoning | User ruling |
|---|---|---|---|---|---|
| `templates/product.workshop.json` | A | L2a | high | Custom store product template. | |
| `templates/product.soap.json` | A | L2a | high | Custom store product template. | |
| `templates/product.geurblokje.json` | A | L2a | high | Custom store product template. | |
| `templates/product.badzout.json` | A | L2a | high | Custom store product template. | |
| `templates/product.facialmask.json` | A | L2a | high | Custom store product template. | |
| `templates/product.3rd-party-product.json` | A | L2a | high | Custom store product template. | |
| `templates/page.store_finder.liquid` | A | L2a | med | Store-finder page template. Likely a custom page or app-powered (no clear app match). Propose L2a — confirm whether it's still used/needed. | |
| `templates/search.ymq.b2b.liquid` | A | app-residue | high | YMQ B2B app search template. Propose **keep** pending admin confirmation. | |
| `templates/index.json` | M | L2b | high | Homepage layout config snapshot. | |
| `templates/cart.json` | M | L2b | high | Template layout config. | |
| `templates/collection.json` | M | L2b | high | Template layout config. | |
| `templates/article.json` | M | L2b | high | Template layout config. | |
| `templates/blog.json` | M | L2b | high | Template layout config. | |
| `templates/password.json` | M | L2b | high | Template layout config. | |
| `templates/product.json` | M | L2b | high | Default product layout config. | |

---

## Config

| File | A/M | Proposed | Conf | Reasoning | User ruling |
|---|---|---|---|---|---|
| `config/settings_data.json` | M | L2b | high | The primary config snapshot. All theme settings, section/block configuration for the live store. | |
| `config/settings_schema.json` | M | **per-hunk** | low | May mix generic schema additions (new settings fields, color scheme definitions) with store-specific defaults. Per-hunk review needed. Propose: new generic schema fields → L1; hardcoded store values → L2b. | |

---

## Locales (58 files)

| Files | A/M | Proposed | Conf | Reasoning | User ruling |
|---|---|---|---|---|---|
| `locales/*.json` and `locales/*.schema.json` (58 files) | M | locale-drift | high | Translation-bot churn on top of v15.1.0. These are upstream changes that didn't make it into the v15.1.0 tag but arrived via "Update from Shopify" auto-syncs. Policy: preserve in a flagged droppable commit now; replace with the full upstream locale set at the first Dawn upgrade. | |
| `translation.yml` | M | locale-drift | med | Translation config churn. Same policy as locales. | |

---

## Other

| File | A/M | Proposed | Conf | Reasoning | User ruling |
|---|---|---|---|---|---|
| `release-notes.md` | M | L0-noise | high | Dawn release notes — follows upstream, not yours. Carry as locale-drift-style droppable alongside the locale commit. | |

---

## App audit

*Code + config inference only — confirm each app's status in Shopify admin (Settings → Apps).*

| App | Theme footprint | Still referenced? | Notes | Admin status (you fill in) |
|---|---|---|---|---|
| **Pandectes** (cookie consent) | `snippets/pandectes-rules.liquid`, `assets/pandectes-*.{png,js,json}`, rendered in `layout/theme.liquid:10` | Yes — active render in theme.liquid | Proposed: **keep all files** | |
| **Booster Apps** | `snippets/booster-apps-common.liquid`, included in `layout/theme.liquid:310` | Yes — active include in theme.liquid | Shared snippet; identify which Booster product is installed | |
| **YMQ B2B** | `templates/search.ymq.b2b.liquid` | Template exists; no reference found in theme.liquid | Proposed: **keep** pending admin confirmation — if uninstalled/unused, move to drop | |
| **Popup app** (`pop_36879859845`) | `assets/pop_36879859845.js` | **No reference found** in theme.liquid or settings_data.json | Proposed: **drop** (numeric-ID asset with no active reference — almost certainly orphaned) | |
| **UnlimitedFonts** (or font app) | `{{ shop.metafields.UnlimitedFonts.stylesheet }}` in `layout/theme.liquid` | Yes — metafield render | Unclear if this is an installed app or a manual metafield. Confirm in admin. | |
| **Google Tag Manager** | GTM snippet in `layout/theme.liquid` | Yes — hardcoded | Not a Shopify app — store-specific tracking. Classify as L2a (store config injected into layout). | |
| **PageFly** (page builder) | **None** (removed from current tree) | No — `pagefly-main-css.liquid` appears in history but is not tracked | Almost certainly uninstalled. Confirm in admin and delete the app if so. | |

---

## Summary counts (proposed, before your rulings)

| Layer | Count |
|---|---|
| L1 (whole-file) | ~9 |
| L1 (per-hunk, mixed) | ~5 files |
| L2a | ~9 |
| L2b | ~12 |
| app-residue (keep proposed) | ~5 |
| app-residue (drop proposed) | ~1 |
| locale-drift | ~59 |
| L0-noise | 1 |
| **Total** | **101** |
