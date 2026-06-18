#!/usr/bin/env bash
# Usage: FIX=$(tests/fixture.sh); cd "$FIX"   — prints the path to a fresh fixture repo.
set -euo pipefail
FIX="$(mktemp -d)"; cd "$FIX"; git init -q; git config user.email t@t; git config user.name t
mkdir -p config sections templates assets locales
seed(){ echo "$2" > "$1"; }
# --- vanilla base (acts as both dawn-vanilla and the upstream/main tip) ---
seed config/settings_data.json '{"current":{"blocks":{}}}'
seed sections/header-group.json '{"name":"header"}'
seed templates/index.json '{"sections":{}}'
seed assets/base.css '/* vanilla */'
seed sections/main-product.liquid 'VANILLA'
git add -A; git commit -qm "vanilla"; git branch dawn-vanilla
git update-ref refs/remotes/upstream/main HEAD
# --- customizations: one L1 commit ---
git checkout -q -b customizations
seed sections/main-product.liquid 'VANILLA + L1-INVENTORY'
git add -A; git commit -qm "L1: inventory status"
# --- staging: enrichment commit, then config-snapshot tip ---
git checkout -q -b staging
seed templates/product.workshop.json '{"enrichment":true}'
git add -A; git commit -qm "L2 enrichment: product.workshop template"
seed config/settings_data.json '{"staging":{"blocks":{"a":1}}}'
seed sections/header-group.json '{"name":"header","store":true}'
git add -A; git commit -qm "L2: store config snapshot"
# --- current: start equal to staging, then add an "admin" config edit (bot churn) ---
git checkout -q -b current staging
seed config/settings_data.json '{"staging":{"blocks":{"a":1,"b":2}}}'
git add -A; git commit -qm "Update from Shopify for theme dawn/current"
# simulate the remote
git update-ref refs/remotes/origin/current current
git checkout -q staging
echo "$FIX"
