# L1 locale contributions (sub-file — applied surgically in Task 4)

Locale files are whole-file **upstream-reconcile** (not in the file manifests). But a few keys
*inside* them belong to L1 features and must ride with `customizations` so L1 is self-contained
(drops onto bare Dawn and renders text, not raw `t:` keys).

**These are added surgically** to `dawn-vanilla`'s clean locale files on the `customizations` branch
— NOT by checking out `current`'s whole file (which would drag in banner/escaping/upstream churn).
They do **not** affect `staging`/byte-for-byte: staging pulls the full live locale files wholesale.

## Storefront keys (customer-facing) — REQUIRED for L1

Path root: `products.product`. The inventory change **restructures** the flat `inventory_*` keys
into nested `inventory.items.*` + `inventory.places.*`, and adds `pickup_availability.pick_up_unavailable`.

### `locales/en.default.json`
```
products.product.pickup_availability.pick_up_unavailable = "Pickup currently unavailable"
products.product.inventory.items.inventory_in_stock = "In stock"
products.product.inventory.items.inventory_in_stock_show_count = "{{ quantity }} in stock"
products.product.inventory.items.inventory_low_stock = "Low stock"
products.product.inventory.items.inventory_low_stock_show_count = "Low stock: {{ quantity }} left"
products.product.inventory.items.inventory_out_of_stock = "Out of stock"
products.product.inventory.items.inventory_out_of_stock_continue_selling = "In stock"
products.product.inventory.places.inventory_in_stock = "Places available"
products.product.inventory.places.inventory_in_stock_show_count = "Still {{ quantity }} places available"
products.product.inventory.places.inventory_low_stock = "Only a few places available"
products.product.inventory.places.inventory_low_stock_show_count = "Only {{ quantity }} places left"
products.product.inventory.places.inventory_out_of_stock = "Fully booked"
products.product.inventory.places.inventory_out_of_stock_continue_selling = "Places available"
```
(Remove the old flat `inventory_in_stock`/`inventory_low_stock`/`inventory_out_of_stock`(+`_show_count`/`_continue_selling`) keys that the nested block replaces.)

### `locales/nl.json`
```
products.product.pickup_availability.pick_up_unavailable = "Afhaling is momenteel niet beschikbaar"
products.product.inventory.items.inventory_in_stock = "Op voorraad"
products.product.inventory.items.inventory_in_stock_show_count = "{{ quantity }} op voorraad"
products.product.inventory.items.inventory_low_stock = "Voorraad laag"
products.product.inventory.items.inventory_low_stock_show_count = "Lage voorraad: nog maar {{ quantity }}"
products.product.inventory.items.inventory_out_of_stock = "Niet op voorraad"
products.product.inventory.items.inventory_out_of_stock_continue_selling = "Op voorraad"
products.product.inventory.places.inventory_in_stock = "Nog plaatsen beschikbaar"
products.product.inventory.places.inventory_in_stock_show_count = "Nog {{ quantity }} plaatsen beschikbaar"
products.product.inventory.places.inventory_low_stock = "Nog maar enkele plaatsen beschikbaar"
products.product.inventory.places.inventory_low_stock_show_count = "Nog maar {{ quantity }} plaatsen beschikbaar"
products.product.inventory.places.inventory_out_of_stock = "Volgeboekt"
products.product.inventory.places.inventory_out_of_stock_continue_selling = "Nog plaatsen beschikbaar"
```

## Schema-label keys (admin theme-editor only) — OPTIONAL, English only

Path root: `sections.main-product.blocks.inventory.settings`. Cosmetic (merchant-facing editor
labels). Add to `en.default.schema.json` only; Dutch admin labels intentionally skipped.
```
availability_type.label = "Availability type"; options__1.label="Items"; options__2.label="Places"
high_stock_threshold.label = "High inventory threshold"; .info = "Only show inventory count below this threshold."
low_stock_threshold.label = "Low inventory threshold"; .info = "Choose 0 to always show in stock if available."
```

## Which feature commit each set rides with (Task 4)

- **pickup feature commit** ← `pick_up_unavailable` (en + nl)
- **inventory feature commit** ← `inventory.items/places` (en + nl) + the schema labels (en schema)
- product-logos feature commit ← no locale keys
