# Intentional differences: `staging` vs `current`

`staging` is **not** byte-for-byte identical to `current` — by design. Byte-for-byte equality was
**proven** at tag `staging-byte-for-byte-proof` (commit `4d8fc47f`); the going-forward `staging`
then dropped purely-cosmetic / unused content for a clean history. **Validated 2026-06-18** by
linking `staging` to a non-live preview theme: NL/EN storefront + all custom templates/features
render flawlessly, and normal browsing produced **no** Shopify bot commits.

Any `git diff staging origin/current` shows exactly these three categories — all expected:

| Category | Files | Why it's safe to differ |
|---|---|---|
| **Churn drop** | `templates/password.json` | Reverted to vanilla. The delta was only the auto-gen banner + HTML-entity escaping + empty `settings:{}`; text was Dawn's default. No real config. |
| **Cosmetic reformatting** | ~32 base locales + `en.default.schema.json` + `config/settings_schema.json` | Auto-gen banner comment + URL escaping (`\/`) + key ordering + `theme_version` label. **Content is identical.** Shopify re-serializes these itself on the next admin edit, so carrying them adds nothing. |
| **Unused regional locales** | `locales/{bg-BG,hr-HR,lt-LT,ro-RO,sk-SK,sl-SI}.json` | Regional variants Shopify added to `current`; not in vanilla Dawn. Store maintains only NL+EN, so these are unused. Shopify won't recreate them (it doesn't fill missing locales), but their absence is invisible on the storefront. |

## Promote consequence (accept consciously at first promote)
The first promote of `staging` → `current` will: (a) reformat the live locale files (Shopify
re-churns them on next edit anyway), and (b) remove the 6 unused regional locale files. Harmless
for an NL/EN store. If ever needed, the byte-for-byte content is restorable via
`git cherry-pick 4d8fc47f` (tag `staging-byte-for-byte-proof`).

## Apps removed earlier (during inventory/app-audit, via Shopify admin)
Pandectes, Booster Apps, YMQ B2B, a popup app (`pop_36879859845.js`), PageFly — all uninstalled
and their theme files removed from `current` before the build.
