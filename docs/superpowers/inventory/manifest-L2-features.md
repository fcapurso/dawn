# L2 split: portable enrichments vs config snapshot

L2 (store-specific) divides into two kinds, mirroring the L1/L2 idea one level down:

- **L2-portable enrichments** (`manifest-L2-files.txt`) — discrete files you *could* drop onto a
  bare, unconfigured Dawn to gain a capability, **given documented prerequisites** (metafields,
  apps, admin config). Each gets its **own commit whose message states its prerequisites**.
- **L2-config** (`manifest-L2-config.txt`) — `settings_data.json` + section-group/stock-template
  JSON: the serialized "Zogezeept look." One snapshot commit. Not portable; it *is* the store.

Note: an enrichment being "applied" still needs its prereqs configured in the admin (metafields
defined, app installed, template suffix assigned to products, page created). The commit gives the
code + the checklist; it does not (and cannot) recreate admin-side data.

## Portable enrichment commits & their prerequisites

### Custom product templates (one commit each — independently addable)
All require: the **`subtitle`** metafield (`product.metafields.descriptors.subtitle`) and the
template suffix assigned to the relevant products in admin. Per-template extras:

| Commit (file) | Additional prerequisites |
|---|---|
| `product.workshop.json` | metafields `custom.location`, `my_fields.advice_for_use`, `my_fields.ingredients`; **Judge.me** app; uses **"places"** inventory availability (bookable) |
| `product.soap.json` | metafields `my_fields.advice_for_use`, `my_fields.ingredients`; **Judge.me** app |
| `product.geurblokje.json` | metafields `my_fields.brand_info`, `my_fields.discounts`, `my_fields.ingredients` |
| `product.badzout.json` | metafield `my_fields.ingredients` |
| `product.facialmask.json` | metafield `my_fields.ingredients` |
| `product.3rd-party-product.json` | metafield `my_fields.brand_info` |

### Other enrichments (one commit each)
| Commit (file) | Prerequisites |
|---|---|
| `page.store_finder.liquid` | **Simple Store Finder** app; metafields `shop.metafields.simple_store_finder.stores_css` + `.stores_text`; a Page using the `store_finder` template suffix |
| `layout/theme.liquid` — GTM hunk | a Google Tag Manager container (currently `GTM-PF8JBN6S`) |
| `layout/theme.liquid` — UnlimitedFonts hunk | **UnlimitedFonts** app; `shop.metafields.UnlimitedFonts.stylesheet` |

## Config snapshot (single commit, no prereq list — it's the store state)
`config/settings_data.json`, `sections/header-group.json`, `sections/footer-group.json`,
`templates/{index,cart,collection,article,blog,product}.json`.
