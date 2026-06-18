# Branch-zoo triage — PROPOSAL ONLY (no branch deleted by this plan)

Snapshot 2026-06-18. `upstream/*` branches are Shopify's own and are ignored here (they live on the
`upstream` remote). Disposition legend: **KEEP** / **ARCHIVE** (tag `archive/<name>` then delete) /
**DELETE** / **REVIEW** (you decide — may hold wanted work).

## New model — KEEP
| Branch | Role |
|---|---|
| `current` (+ `origin/current`) | live theme — never hand-touched |
| `dawn-vanilla` | pristine Dawn base (d2612f03) — **push to origin** |
| `customizations` | L1 generic layer — **push to origin** |
| `staging` (+ `origin/staging`) | integration + preview theme — pushed ✓ |
| `repo-cleanup` | holds all `docs/superpowers/*` (specs, plan, inventory, runbook). Keep until you decide where docs live long-term (see note). |

## Old vanilla-tracking — REVIEW
| Branch | Notes | Proposed |
|---|---|---|
| `main` / `origin/main` | old upstream-tracking branch (3 ahead of current). `dawn-vanilla` now plays the vanilla-reference role. | KEEP as a plain upstream mirror, **or** DELETE (redundant with `dawn-vanilla` + `upstream` remote). Your call. |

## Version-bump attempts — ARCHIVE then DELETE
Superseded by the new `dawn-vanilla` ff + rebase upgrade flow (runbook §3).
`update-to-3.0.0`, `update-to-7.0.0`, `update-to-11.0.0`, `update-to-12.0.0`, `update-to-13.0.1`,
`update-to-15.2.0` (already in current), and their `origin/` counterparts. Local `update-to-*` too.

## Old snapshots — ARCHIVE then DELETE
`old_current` / `origin/old_current` (47 ahead — an old copy of the live theme, pre-dates cleanup).
The original live state is already preserved at tag `pre-cleanup-backup`.

## Feature / experiment branches on origin — REVIEW (then ARCHIVE or DELETE)
Likely stale experiments; confirm none hold work you still want before removing. If a feature here
is generic and still wanted, it should become an L1 commit on `customizations` (harvest, runbook §4).

```
add-title-logic            add-typography-size-setting(/-2/-3)   add-vat-field
delivery-options-experiment  delivery_options                    feature-collection-subtitle
feature-gift-card-ui       fix-accessibility-details-summary     fix-css-rgb-syntax
fix-product-recommendations  image-banner-height                 ios-12-support
mac-sept10-test            modal-toggle-a11y                     multicolumn-links
password-iteration         price-structure                      product-review-seo
product-variants-hide-unavailable  variants-unavailable          schema-product-category
search-result-ios-fix(/-2)
```
Candidates that sound store-relevant and worth a look before deleting: `add-vat-field`,
`feature-collection-subtitle`, `delivery_options`, `product-variants-hide-unavailable`,
`variants-unavailable`, `price-structure`. The rest look like generic Dawn tweaks/experiments.

## Archive recipe (lossless — only after you approve a name)
```bash
git tag archive/<name> origin/<name>        # preserve history under a tag
git push origin archive/<name>
git push origin --delete <name>             # remove the branch
git branch -D <name>                         # local, if present
```
Tags keep the commits reachable forever, so nothing is lost; the branch list just gets clean.

## Note on where docs live long-term
`docs/superpowers/*` currently lives only on `repo-cleanup`. Options: keep it on a dedicated
`repo-cleanup`/`meta` branch (cleanest — never ships to the theme), or merge into `staging`/`current`
(Shopify ignores non-theme top-level dirs, but it clutters the theme repo). Recommend: keep on a
dedicated branch.
