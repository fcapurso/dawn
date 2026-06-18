# Curated drops from staging

Files present in `current` (and proven lossless by the Task 7 acceptance test) that are
intentionally **not** carried forward into `staging`. Any `git diff staging origin/current`
showing these is expected and explained here.

| File | Action | Reason | Verified |
|---|---|---|---|
| `templates/password.json` | reverted to vanilla Dawn | Pure churn: auto-generated banner comment + HTML-entity un-escaping (`<\/p>`→`</p>`) + empty `settings:{}` objects + trailing-newline. The text is Dawn's vanilla default ("Be the first to know when we launch."). No store-specific config. | Diff inspected 2026-06-18 — only churn, no real settings. |

## Apps removed earlier (during inventory/app-audit, via Shopify admin — not part of this commit)
Pandectes, Booster Apps, YMQ B2B, a popup app (`pop_36879859845.js`), PageFly — all uninstalled
and their theme files removed from `current` before the build. See the app audit in the inventory.
