# Product template simplification

**Date:** 2026-10-09 (content model revised 2026-10-11)
**Status:** Done 2026-10-12. All steps complete.

## Goal

Replace five near-identical product templates with one shared template, `product.standard`.
New products (the lip balm, Soapi) need no new template.

Shared information follows from how a product is classified, so it is never stored again on
each product:

- **What it is:** the product type ("Hand & body zeep", "Gezichtsmasker", ...). Each type
  belongs to a **category**, which holds that category's shared texts (usage, good to know).
- **Who makes it:** the vendor ("Zogezeept", "Marokkanse Amberblokjes", ...). Each vendor can
  have a **brand** entry with its brand text.

Fields on the product itself are only for what is truly unique to that product (its own usage
sentence, ingredients) and for per-product switches (hide reviews, hide stock count).

## Ground rules

1. **Nothing in use today is renamed or modified**, unless strictly necessary. That covers
   templates, theme code behaviour, metafields, pages, product options, product types, vendors
   and tags. Everything new is added alongside. Old things are removed only once nothing uses
   them anymore.
2. **All code, metafields, metaobjects and template names are in English.** Customer-facing copy
   (tab headings, texts, filter tags) is Dutch. The storefront is published in Dutch only
   (checked 2026-10-10). If English is published later, the category, brand and shipping texts
   and the new template's headings need translating like any other content.
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
| `product.3rd-party-product` | 2 of the archived products (checked in admin 2026-10-10) | Description, Waarom {merk} (page), Verzendkosten; no reviews, stock or logos |
| `product` (Dawn default) | none (checked in admin 2026-10-10) | |

Other differences today:

- **Logos:** soap, masks and bath milk show vegan and vegetarian by tag. Cruelty free and
  handmade are always on in those templates. Palm oil free is always on in the soap template
  only. Geurblokje shows no logos.
- **Reviews (Judge.me):** on every template except `geurblokje` and `3rd-party-product`.
- **Shipping text:** the same text typed into five templates.
- **Variant picker:** dropdown on every template whose products have variants.

## End state

- `product.standard`: every physical product, Zogezeept and third-party, with or without
  variants.
- `product.workshop`: unchanged.
- `product` (Dawn default): unchanged, unused.
- Deleted: `product.soap`, `product.facialmask`, `product.badzout`, `product.geurblokje`,
  `product.3rd-party-product`, and the pages that only fed tabs.

## What gets added

### Theme code (five changes to `sections/main-product.liquid`)

Rule for all five: anything a product doesn't use renders no markup at all, so it leaves no
empty band or gap on the page. None of them changes what any page shows today.

1. **"Hide when empty" setting on the collapsible tab block.** A new checkbox, off by default.
   When on, the tab is not rendered if everything it would show (its text, linked page and
   shared text from change 5) is empty after stripping HTML (dynamic sources render an empty
   `<p></p>` when the metafield is blank). Existing templates don't have the setting, so they
   behave exactly as today. Opt-in because old templates can have empty tabs today (a soap
   without usage text), and those must not change. Touches standard Dawn code. Layer: L1
   (generic).
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
5. **"Shared text" setting on the collapsible tab block.** A new dropdown, "none" by default,
   with the options: category usage, category good to know, brand text. When set, the tab
   adds that text after its own content:
   - category texts: from the `category` entry whose `product_types` list contains the
     product's type;
   - brand text: from the `brand` entry whose `vendor` equals the product's vendor.

   If no entry matches, nothing is added. Which types and vendors belong to which entry is
   stored in the entries (admin content), never in the code. Existing templates don't have the
   setting, so they behave exactly as today. Layer: L2 (store-specific).

### Metaobject definitions

All three need storefront access switched on (Settings > Custom data > Metaobject definitions >
the definition > Access: Storefronts), so the theme can read them.

**`category`**: one entry per product category, holding its shared texts.

| Field | Type |
|---|---|
| `name` | single line text |
| `product_types` | list of single line text |
| `usage` | rich text |
| `good_to_know` | rich text |

**`brand`**: one entry per third-party brand.

| Field | Type |
|---|---|
| `name` | single line text |
| `vendor` | single line text |
| `about` | rich text |

**`info_text`** (already created): one-off shared text, linked directly from the template.
Fields `title` (single line text) and `body` (rich text).

**Entries** (handles in English, content in Dutch):

| Definition | Handle | Matches | Content |
|---|---|---|---|
| `category` | `soap` | "Hand & body zeep", "Handzeep" | good to know: from page `goed-om-te-weten-over-zeep`; usage: empty (soaps have their own) |
| `category` | `facial-mask` | "Gezichtsmasker" | usage: from page `gebruik-gezichtmaskers` |
| `category` | `bath-milk` | "Badmelk" | usage: from page `gebruik-badzout` |
| `category` | `fragrance-block` | "Geurblokje" | empty for now |
| `category` | `lip-balm` | "Lippenbalsem" | good to know: storage and texture of shea butter |
| `category` | `soap-holder` | "Keramisch zeepschaaltje", "Zeepbakje", "Magnetische zeephouder" (Soapi) | as needed |
| `brand` | `marokkanse-amberblokjes` | vendor "Marokkanse Amberblokjes" | from page `marokkanse-amberblokjes` |
| `brand` | `yume-ceramics` | vendor "Yume Ceramics" | from page `over-yume-ceramics` |
| `brand` | `foekje-fleur` | vendor "Foekje Fleur" | from page `over-foekje-fleur` |
| `brand` | `soapi` | vendor "Soapi" | new |
| `info_text` | `shipping-info` | (linked from the template) | today's shipping tab text |

Type and vendor names in `product_types` and `vendor` must be spelled exactly as on the
products, because there's no autocomplete there. If a product type or vendor is ever renamed,
the matching entry must be updated too, or its texts stop showing.

Entries with an empty text simply add nothing. A category entry for every type is not required,
but having one makes it easy to add shared text later. A Zogezeept brand entry is deliberately
not created: without one, Zogezeept products show no brand tab, as today.

### Product metafields

New:

| Metafield | Type | Feeds |
|---|---|---|
| `custom.good_to_know` | rich text | Goed om te weten tab (product's own text) |
| `custom.hide_reviews` | true or false | Judge.me stars and widget |
| `custom.hide_stock` | true or false | Stock count |

Existing metafields are read as they are, never changed: `descriptors.subtitle`,
`my_fields.advice_for_use`, `my_fields.ingredients`, `my_fields.discounts`. The old
`my_fields.brand_info` (page link) stays in place for the old templates until cleanup.

The `shipping-info` entry is not linked from products: the Verzendkosten tab in the template is
connected straight to it (theme editor: dynamic source > Metaobjects). Edited once under
Content > Metaobjects.

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

   | Tab heading | Own content | Shared text |
   |---|---|---|
   | Gebruik | `my_fields.advice_for_use` | category usage |
   | Wat zit er allemaal in? | `my_fields.ingredients` | |
   | Goed om te weten | `custom.good_to_know` | category good to know |
   | Waarom {{ product.vendor }} | | brand text |
   | Verzendkosten | `info_text` entry `shipping-info` | |

10. Share
11. Judge.me review widget (hidden when `custom.hide_reviews` is true)

The empty `apps` section in `product.soap` has no blocks and is not carried over.

## Content per product type

| Type | Gebruik | Wat zit er in | Goed om te weten | Waarom {merk} | Logos | Reviews | Stock |
|---|---|---|---|---|---|---|---|
| Zeep | own text | ✓ | category `soap` | | as today | ✓ | ✓ |
| Gezichtsmasker | category `facial-mask` | ✓ | optional own text: shelf life, keep dry | | as today | ✓ | ✓ |
| Badmelk | category `bath-milk` | ✓ | | | as today | ✓ | ✓ |
| Lipbalm (new) | own text | ✓ | own: shelf life after opening, keep away from heat | | per product | ✓ | ✓ |
| Geurblokje | | ✓ | | brand `marokkanse-amberblokjes` | none | hidden | hidden |
| Soapi (new) | own: fitting it | | own: material, size, care | brand `soapi` | none | your choice | your choice |
| Archived third-party (3) | | | | brand `yume-ceramics` / `foekje-fleur` | none | hidden | hidden |
| Archived soap sets (2) | as their current template shows | | | | as today | as today | as today |

Archived and draft products (admin, 2026-10-11):

| Product | Status | Product type | Vendor |
|---|---|---|---|
| Heather (the new lip balm) | Draft | Lippenbalsem | Zogezeept |
| Liefdevolle set | Archived | Hand & body zeep | Zogezeept |
| Liefdevol setje | Archived | Hand & body zeep | Zogezeept |
| Keramisch zeepschaaltje mini | Archived | Keramisch zeepschaaltje | Yume Ceramics |
| Keramisch zeepschaaltje | Archived | Keramisch zeepschaaltje | Yume Ceramics |
| Bubble Buddy | Archived | Zeepbakje | Foekje Fleur |

Archived products are migrated like the others, so that if they are ever made active again
they show everything they show today. Which template each archived product uses today is
checked in the admin before switching it.

Adding a new product: pick the right product type and vendor (or duplicate a product of the
same kind), assign `product.standard`, fill in its own texts and tags. The shared texts appear
by themselves.

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

1. **Admin check.** Done 2026-10-10: no product uses `product`; 2 archived products use
   `product.3rd-party-product`. Decision 2026-10-11: they are migrated like the others (see
   content per product type).

2. **Editor test.** Done 2026-10-10, on a duplicate of the live theme. Confirmed that a tab's
   text can be connected directly to a metaobject entry (used for shipping) and can hold
   several sources. The category and brand texts are looked up by theme code (change 5), so
   they are checked on the preview theme in step 5.

3. **Admin, additions only.** Done 2026-10-11, apart from setting the hide switches and the
   live check. Definitions and entries exist as listed above; the old setup is removed. The
   editor test had changed `product.facialmask.json` on the staging theme; staging was reset
   to `current` (force-pushed 2026-10-11).
   - Remove the setup made for the earlier content model (see "Admin setup to remove"
     below). None of it is read by the live site.
   - Create the `category` and `brand` definitions with storefront access, and their entries.
   - Create the product metafields `custom.good_to_know`, `custom.hide_reviews`,
     `custom.hide_stock`.
   Old templates don't read any of these, so the live site doesn't change.
   *Checkpoint:* live product pages unchanged.

4. **Theme on staging.** Done 2026-10-11: five code commits on `staging` (`ea74114c`,
   `6fc00d0f`, `cc81ba86`, `846da8e3`, `c6469d29`); the template was folded into the config
   snapshot `85b0b846` by backflow; stage-pushed to the preview theme. The shipping tab still
   holds typed text until it is connected to the `shipping-info` entry in the editor.
   Add the five code changes and `product.standard`. Make sure staging
   contains nothing else waiting to go live: promote publishes everything on staging.

5. **Preview theme.** Push staging to the preview theme. Open every product with
   `?view=standard` (for example `/products/zozacht?view=standard`) and compare with its
   current page. Also check that every old template looks exactly as before.
   *Checkpoint:* all products correct on `standard`, including category and brand texts; old
   templates unchanged.

6. **Go live.** Done 2026-10-11: harvested into `customizations` (`05231927` to `320dc949`),
   stage-pushed, promoted (`current` = `81e08c5f`). Rollback tag
   `config-archive/2026-10-11-173940`. Live pages unchanged; `?view=standard` works on live.
   Promote. `product.standard` is live but no product is assigned to it, so
   customers see no difference. This is the one step that changes code every product page
   uses (`sections/main-product.liquid`), so it is not covered by the per-product rollback.
   *Checkpoint:* live pages unchanged, on every old template; `?view=standard` works on live.
   *Rollback:* revert the code-change commits on staging and promote again. Products are still
   on their old templates at this point, so nothing else needs undoing.

7. **Switch products, one at a time.** For each product: add its logo tags (and set
   `custom.hide_reviews` and `custom.hide_stock` for geurblokje and the archived third-party
   products, so they look as they do today), check it once more with `?view=standard` on live, then
   assign `product.standard` in the admin.
   *Archived products* can't be opened on the storefront, so `?view=standard` doesn't work for
   them. Check them in the theme editor by picking the product in the preview. If the editor
   doesn't offer archived products, set the product to Draft (still hidden from customers),
   use the product's Preview in the admin, then set it back to Archived. Compare against the
   old template the same way, before switching.
   *Rollback:* assign the old template again.

8. **New products.** Create the lip balm and Soapi directly on `product.standard`, with their
   category and brand entries. New products must be assigned `standard` by hand; the default
   template is Dawn's.

9. **Cleanup, only when every product is on `standard` and you are fully happy with it.**
   This is the point of no return: after it, products can no longer be switched back.
   - Confirm in the admin that no product uses the old templates. Done 2026-10-12.
   - Delete `product.soap`, `product.facialmask`, `product.badzout`, `product.geurblokje`,
     `product.3rd-party-product`, both on the live theme and in the git branches (staging,
     customizations), so they don't come back with the next promote. Done 2026-10-12:
     `c11fbc4c` on `customizations`, promoted (`current` = `fbe60860`), rollback tag
     `config-archive/2026-10-12-193505`.
   - Delete the pages that only fed tabs. No redirects (decided 2026-10-12): the pages were
     never meant to be reached directly, so letting them drop out of search results is fine:
     `gebruik-gezichtmaskers`, `gebruik-badzout`, `goed-om-te-weten-over-zeep`,
     `marokkanse-amberblokjes`, `over-foekje-fleur`, `over-yume-ceramics`. Check
     `praktische-info` is unused first.
   - Delete the `my_fields.brand_info` metafield definition.
   Pages and field deleted 2026-10-12; the 7 pages return 404, are gone from the sitemap, and
   no product page links to them.

## Admin setup to remove (from the earlier content model)

Made between 2026-10-10 and 2026-10-11 for per-product links, which the revised model replaces.
Nothing on the live site reads any of it, so it can be removed at any time. Copy texts into the
new `category` and `brand` entries before deleting the entries that hold them.

- `info_text` entries `usage-facial-masks`, `usage-bath-milk`, `good-to-know-soap`,
  `brand-marokkanse-amberblokjes`, and any brand entries made for the archived products.
  Keep the `info_text` definition and its `shipping-info` entry.
- Product metafield definitions `custom.usage_shared`, `custom.good_to_know_shared`,
  `custom.brand_info`, if created. When deleting, choose to delete their values too.
- The duplicate theme used for the editor test.

Keep: `custom.good_to_know`, `custom.hide_reviews`, `custom.hide_stock` if already created
(and their values on geurblokje and the archived third-party products). Renaming the old
`my_fields.brand_info` to "Brand info (old)" in the admin is harmless and can stay.

## Left out on purpose

- **Renaming tekstzeepjes' "Style" option to "Text".** Not needed for this plan, and it changes
  something in use.
- **Changing the default `product` template.** Kept as Dawn ships it, so Dawn upgrades never
  touch our product page.
- **Merging the workshop into `product.standard`.** It would need a location block, its own
  tabs, a shipping switch and different stock settings, for a single product.
- **Per-variant tab content.** Not needed today. If it becomes needed, the workshop's location
  script is the starting point.
- **Shopify's standard product category** as the classification. It exists for tax and sales
  channels, has nothing that fits a workshop, and isn't your own grouping. Still worth setting
  for Soapi's colour swatches.
