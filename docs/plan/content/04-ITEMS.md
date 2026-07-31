# Content: Items (EA ≤80)

## Slot targets (approximate distribution)

| Slot | Approx count | M6 actual (catalog) |
|------|--------------|---------------------|
| Weapons | 20 | ~20 |
| Helmet | 8 | ~8 |
| Chest | 8 | ~8 |
| Gloves | 6 | ~6 |
| Boots | 6 | ~6 |
| Rings | 8 | ~8 |
| Amulets | 6 | ~6 |
| Relics | 8 | 11 (catalog relics array) |
| Consumables | 10 | 5 |
| Materials | — | 5 |
| **Total** | **≤80** | **79** (equipment+consumables+relics) |

Source of truth: `content/items/catalog.json`. On-disk JSON under `content/items/equipment|consumables|materials/` must match catalog entries.

## Status

**ITEM-6.1 complete** — catalog at 79 items (≤80 cap). Theme uniques for frozen/cathedral added. Affix pool expanded for epic+. Automated: `m6.items.catalog_cap`, `m6.items.unique_*`.

## Affix packs

- `content/affixes/prefixes.json`
- `content/affixes/suffixes.json`
- Rules by rarity in `content/affixes/rarity_rules.json`

## Checklist for each item

- [x] Def JSON valid (schema + catalog consistency)
- [ ] Icon present (placeholder OK for EA blockout)
- [x] Referenced by ≥1 loot table OR merchant/recipe (theme loot tables)
- [x] Equip applies intended stats (automated inventory tests)

## Partial / deferred

- Mythic per-item unique behavior (affix counts only)
- Full consumable roster to 10 slots (5 in catalog)
