# Content: Items (EA ≤80)

## Slot targets (approximate distribution)

| Slot | Approx count |
|------|--------------|
| Weapons | 20 |
| Helmet | 8 |
| Chest | 8 |
| Gloves | 6 |
| Boots | 6 |
| Rings | 8 |
| Amulets | 6 |
| Relics | 8 |
| Consumables | 10 |
| **Total** | **≤80** |

Exact ids filled during ITEM-5.1 and ITEM-6.1. Maintain living table below as items are added.

## Living registry

| Id | Slot | Rarity baseline | Theme bias | Status |
|----|------|-----------------|------------|--------|
| `iron_sword` | weapon | common | starter | planned |
| `knight_blade` | weapon | rare | forgotten_castle | planned |
| _(add rows as authored)_ | | | | |

## Affix packs

- `content/affixes/prefixes.json`
- `content/affixes/suffixes.json`
- Rules by rarity in `content/affixes/rarity_rules.json`

## Checklist for each item

- [ ] Def JSON valid
- [ ] Icon present
- [ ] Referenced by ≥1 loot table OR merchant/recipe
- [ ] Equip applies intended stats
