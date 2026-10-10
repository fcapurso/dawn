# Product template simplification

**Date:** 2026-10-09
**Status:** Plan, not started

## Goal

Replace five near-identical product templates with one shared template, `product.standard`.
Each product decides which tabs, logos and reviews it shows through what is filled in on that
product, not through which template it uses. New products (the lip balm, Soapi) need no new
template.

## Ground rules

1. **Nothing in use today is renamed or modified**, unless strictly necessary. That covers
   templates, theme code behaviour, metafields, pages, product options and tags. Everything new
   is added alongside. Old things are removed only once nothing uses them anymore.
2. **All code, metafields, metaobjects and template names are in English.** Customer-facing copy
   (tab headings, texts, filter tags) is Dutch. The storefront is published in Dutch only
   (checked 2026-10-10). If English is published later, the new shared texts, the shop shipping
   text and the new template's headings need translating like any other content.
3. **Every product is tested on the new template before it is switched**, and can be switched
   back at any moment until cleanup.

## Current state (live theme, 2026-10-09)

| Template | Used by | Tabs |
|---|---|---|
| `product.soap` | 15 soaps (Hand & body zeep, Handzeep) | Gebruik (own text), Wat zit er in, Goed om te weten (page), Verzendkosten |
| `product.facialmask` | 6 face masks | Gebruik (page), Wat zit er in, Verzendkosten |
| `product.badzout` | 2 bath milks (product type "Badmelk") | Gebruik (page), Wat zit er in, Verzendkosten |
| `product.geurblokje` | 1 (Marokkanse Amberblokjes) | Wat zit er in, Waarom {merk} (page), Verzendkosten |
| `product.workshop` | 1 (Zelf zeep maken) | Wat gaan we doen, Praktische info |
| `product.3rd-party-product` | none found among published products | |
| `product` (Dawn default) | none found among published products | |

Other differences today:

- **Logos:** soap, masks and bath milk show vegan and vegetarian by tag. Cruelty free and
  handmade are always on in those templates. Palm oil free is always on in the soap template
  only. Geurblokje shows no logos.
- **Reviews (Judge.me):** on every template except `geurblokje` and `3rd-party-product`.
- **Shipping text:** the same text typed into five templates.
- **Variant picker:** dropdown on every template whose products have variants.
- Unpublished products could not be checked from the storefront.

## End state

- `product.standard`: every physical product, Zogezeept and third-party, with or without
  variants.
- `product.workshop`: unchanged.
- `product` (Dawn default): unchanged, unused.
- Deleted: `product.soap`, `product.facialmask`, `product.badzout`, `product.geurblokje`,
  `product.3rd-party-product`, and the pages that only fed tabs.

## What gets added

### Theme code (four changes to `sections/main-product.liquid`)

Rule for all four: anything a product doesn't use renders no markup at all, so it leaves no
empty band or gap on the page. None of them changes what any page shows today.

1. **"Hide when empty" setting on the collapsible tab block.** A new checkbox, off by default.
   When on, the tab is not rendered if its text and linked page are empty after stripping HTML
   (dynamic sources render an empty `<p></p>` when the metafield is blank). Existing templates
   don't have the setting, so they behave exactly as today. Opt-in because old templates can
   have empty tabs today (a soap without usage text), and those must not change. Touches
   standard Dawn code. Layer: L1 (generic).
2. **Hide Judge.me blocks per product.** In the app block branch, skip Judge.me blocks when the
   product metafield `custom.hide_reviews` is true. No product has that metafield today, so
   nothing changes until it is set. A metafield, not a tag, because tags show up in the
   storefront's tag filter. Touches standard Dawn code. Layer: L2 (store-specific).
3. **Hide the stock count per product.** In the inventory block, render nothing when the
   product metafield `custom.hide_stock` is true. No product has it today, so nothing changes
   until it is set. Dawn's variant-switch script already skips the stock line when it isn't on
   the page (checked in `assets/product-info.js`), so this causes no script errors. Touches
   the inventory block, which is Dawn code you already customized. Layer: L2 (store-specific).
4. **No empty logo band.** Today the logo block always outputs its container, which has a
   20px margin above and below (`assets/component-product-logos.css`), so a product with no
   matching logos would get an empty 40px band. Change: output the container only when at
   least one logo applies to the product. Not opt-in, because no product shows an empty logo
   area today: every template with the logo block has logos that are always on. Touches your
   own logo block code. Layer: L1 (generic).

### Metaobject definition `info_text`

Shared text that many products point to. Replaces the pages behind tabs.

| Field | Type |
|---|---|
| `title` | single line text |
| `body` | rich text |

Entries (handles in English, content in Dutch, copied from today's pages):

| Handle | Copied from page |
|---|---|
| `usage-facial-masks` | `gebruik-gezichtmaskers` |
| `usage-bath-milk` | `gebruik-badzout` |
| `good-to-know-soap` | `goed-om-te-weten-over-zeep` |
| `brand-marokkanse-amberblokjes` | `marokkanse-amberblokjes` |
| `brand-soapi` | new |

### New product metafields

| Metafield | Type | Feeds |
|---|---|---|
| `custom.usage_shared` | metaobject reference (`info_text`) | Gebruik tab |
| `custom.good_to_know` | rich text | Goed om te weten tab |
| `custom.good_to_know_shared` | metaobject reference (`info_text`) | Goed om te weten tab |
| `custom.brand` | metaobject reference (`info_text`) | Waarom {merk} tab |
| `custom.hide_reviews` | true or false | Judge.me stars and widget |
| `custom.hide_stock` | true or false | Stock count |

Existing metafields are read as they are, never changed: `descriptors.subtitle`,
`my_fields.advice_for_use`, `my_fields.ingredients`, `my_fields.discounts`. The old
`my_fields.brand_info` (page link) stays in place for the old templates until cleanup.

### New shop metafield

| Metafield | Type | Feeds |
|---|---|---|
| `custom.shipping_info` | rich text | Verzendkosten tab |

Edited once under Settings > Custom data > Shop. Content copied from today's shipping text.

### New product tags (logos)

`palmolievrij`, `dierproefvrij`, `handgemaakt`. These are customer-facing: the storefront has
a tag filter, so they appear there as filter options (like `vegan` and `hypoallergeen` today).
Each tag is added only to products that show that logo today. Tags are added when a product
is switched (step 7), not before, so the filter only changes as products move.

### New template `product.standard`

Same section settings, block settings and related products as the current templates. Block
order:

1. Vendor, title, subtitle
2. Judge.me stars (hidden when `custom.hide_reviews` is true)
3. Price, discount line (`my_fields.discounts`, shown only when filled in)
4. Variant picker (dropdown)
5. Stock count (items, thresholds 5 / 5, as today; hidden when `custom.hide_stock` is true)
6. Quantity, buy buttons
7. "Over {product}", description
8. Logos: vegan (tag `vegan`), vegetarian (`vegetarian`), palm oil free (`palmolievrij`),
   cruelty free (`dierproefvrij`), handmade (`handgemaakt`). The block holds 5 logos; all 5
   are used. No logos for a product means no logo area at all.
9. Tabs, all with "Hide when empty" on:

   | Tab heading | Shows |
   |---|---|
   | Gebruik | `my_fields.advice_for_use` + `custom.usage_shared` |
   | Wat zit er allemaal in? | `my_fields.ingredients` |
   | Goed om te weten | `custom.good_to_know` + `custom.good_to_know_shared` |
   | Waarom {{ product.vendor }} | `custom.brand` |
   | Verzendkosten | shop `custom.shipping_info` |

10. Share
11. Judge.me review widget (hidden when `custom.hide_reviews` is true)

The empty `apps` section in `product.soap` has no blocks and is not carried over.

## Content per product type

| Type | Gebruik | Wat zit er in | Goed om te weten | Waarom {merk} | Logos | Reviews | Stock |
|---|---|---|---|---|---|---|---|
| Zeep | own text | ✓ | `good-to-know-soap` | | as today | ✓ | ✓ |
| Gezichtsmasker | `usage-facial-masks` | ✓ | optional: shelf life, keep dry | | as today | ✓ | ✓ |
| Badmelk | `usage-bath-milk` | ✓ | | | as today | ✓ | ✓ |
| Lipbalm (new) | own text | ✓ | own: shelf life after opening, keep away from heat | | per product | ✓ | ✓ |
| Geurblokje | | ✓ | | `brand-marokkanse-amberblokjes` | none | hidden | hidden |
| Soapi (new) | own: fitting it | | own: material, size, care | `brand-soapi` | none | your choice | your choice |

## Variants

- **Products without variants:** Dawn hides the picker automatically. Nothing to do.
- **Content is per product, never per variant.** When a customer switches variant, Dawn only
  refreshes price, stock, SKU and the buy button. Tabs, logos and custom text stay as they
  were. Tab text must cover all variants (for example all geurblokje scents, all Soapi
  colours). Variants that differ in a logo property (vegan or not) belong in separate
  products.
- **Picker:** dropdown, as today. Soapi's colours show a small swatch inside the dropdown when
  its option is set up as a colour.
- **Images:** "hide other variants' media" stays on. Each variant needs its own image.
- **Engraved soaps:** keep their own stock per engraving. Option names are left as they are.

## Migration steps

Each step has a checkpoint. Nothing before step 9 removes or changes anything customers rely
on.

1. **Admin check.** Confirm no draft or hidden product is assigned `product.3rd-party-product`
   or `product`.
   *Checkpoint:* list of products per template matches the current state table.

2. **Editor test.** On a duplicate of the live theme, check that a tab's text can be connected
   to a field inside a linked metaobject (`custom.usage_shared` > `body`) and to a shop
   metafield.
   *If not:* extend the tab code change so the block reads the linked text directly. Still
   additive.

3. **Admin, additions only.** Create the `info_text` definition and its entries, the new
   product metafield definitions, and the shop metafield `custom.shipping_info`. Fill in the
   new metafields on every product. Old templates don't read any of these, so the live site
   doesn't change.
   *Checkpoint:* live product pages unchanged.

4. **Theme on staging.** Add the two code changes and `product.standard`. Make sure staging
   contains nothing else waiting to go live: promote publishes everything on staging.

5. **Preview theme.** Push staging to the preview theme. Open every product with
   `?view=standard` (for example `/products/zozacht?view=standard`) and compare with its
   current page. Also check that every old template looks exactly as before.
   *Checkpoint:* all products correct on `standard`; old templates unchanged.

6. **Go live.** Promote. `product.standard` is live but no product is assigned to it, so
   customers see no difference. This is the one step that changes code every product page
   uses (`sections/main-product.liquid`), so it is not covered by the per-product rollback.
   *Checkpoint:* live pages unchanged, on every old template; `?view=standard` works on live.
   *Rollback:* revert the code-change commits on staging and promote again. Products are still
   on their old templates at this point, so nothing else needs undoing.

7. **Switch products, one at a time.** For each product: add its logo tags (and set
   `custom.hide_reviews` and `custom.hide_stock` for geurblokje, so it looks as it does today),
   check it once more with `?view=standard` on live, then assign `product.standard` in the
   admin.
   *Rollback:* assign the old template again.

8. **New products.** Create the lip balm and Soapi directly on `product.standard`. New
   products must be assigned `standard` by hand; the default template is Dawn's.

9. **Cleanup, only when every product is on `standard` and you are fully happy with it.**
   This is the point of no return: after it, products can no longer be switched back.
   - Confirm in the admin that no product uses the old templates.
   - Delete `product.soap`, `product.facialmask`, `product.badzout`, `product.geurblokje`,
     `product.3rd-party-product`, both on the live theme and in the git branches (staging,
     customizations), so they don't come back with the next promote.
   - Delete the pages that only fed tabs, with a redirect for each (they are in the sitemap):
     `gebruik-gezichtmaskers`, `gebruik-badzout`, `goed-om-te-weten-over-zeep`,
     `marokkanse-amberblokjes`, `over-foekje-fleur`, `over-yume-ceramics`. Check
     `praktische-info` is unused first.
   - Delete the `my_fields.brand_info` metafield definition.

## Left out on purpose

- **Renaming tekstzeepjes' "Style" option to "Text".** Not needed for this plan, and it changes
  something in use.
- **Changing the default `product` template.** Kept as Dawn ships it, so Dawn upgrades never
  touch our product page.
- **Per-variant tab content.** Not needed today. If it becomes needed, the workshop's location
  script is the starting point.
