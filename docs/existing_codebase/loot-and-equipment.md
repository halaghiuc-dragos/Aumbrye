# Loot and equipment

Loot has four live pieces: unified grants via `InventoryService.add_loot`, static chest/pickup placement, rare global skip-item drops (`GlobalDropService`), and affix rolling (`AffixRoller`) shared by castle and waves inventories. `Equipment` aggregates equipped instance stats for the player. Affix **rarity weights, affix counts, tiers, itemTypes, and weight** are all honored when rolling.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/loot/affix_roller.gd` | `AffixRoller.roll_instance` / `get_affix_stat` |
| `apps/game/client/scripts/loot/rarity_registry.gd` | Tier order, mythic→aumbral alias, mode bonuses |
| `apps/game/client/scripts/loot/global_drop_service.gd` | Skip-floor item chances from `global_drops.json` |
| `apps/game/client/scripts/loot/loot_table_loader.gd` | External per-biome loot tables under `content/loot/tables/` |
| `apps/game/client/scripts/loot/loot_chest.gd` | Interact chest → `InventoryService.add_loot` |
| `apps/game/client/scripts/inventory/world_item_pickup.gd` | World pickup → `add_loot` |
| `apps/game/client/scripts/inventory/inventory_service.gd` | `add_loot`, `add_rolled_item`, equipment apply |
| `apps/game/client/scripts/items/equipment.gd` | Slots, aggregate/compare/format stats |
| `content/affixes/prefixes.json`, `suffixes.json`, `rarity_rules.json` | Affix defs + weights/counts |
| `content/loot/global_drops.json` | Skip item chances |
| `content/loot/tables/<biome_id>.json` | Optional external biome chest tables |
| `content/items/**` | Item definitions |

## How it works

### Rarity
`RarityRegistry.TIER_ORDER`: common → magic → rare → epic → legendary → aumbral (`rarity_registry.gd:5-13`). `LEGACY_ALIASES` maps legacy `mythic`/`umbral` → `aumbral` for content migration only; `rarity_rules.json` uses `aumbral` exclusively. Mode drop bonuses: endless `0.08`, waves `0.06` on rare+ weights (`rarity_registry.gd:39-42`, applied in `AffixRoller._pick_rarity`).

### `AffixRoller.roll_instance`
1. Load prefixes/suffixes/rules once (`affix_roller.gd:70-79`).
2. Pick rarity from `rarityWeights` (or forced rarity) (`_pick_rarity`).
3. Affix count from `affixCounts` min/max for that rarity (`_roll_affix_count`).
4. Build pool filtered by `itemTypes`; weighted pick without replacement (`_build_affix_pool`, `_pick_weighted_affixes`).
5. Value from `tiers[normalize(rarity)]` with aumbral/mythic/legendary fallback (`_roll_tier_value`).

### `InventoryService.add_loot`
Routes consumables/materials through `add_item`; weapons/armor/accessories (or `rollAffixes: true`) through `add_rolled_item` with run-seeded rolls. Emits `inventory_rejected` on full grid. Chest entries may pass `"roll": true` to force rolling.

### Where rolling runs
| Path | Uses roller? |
|------|----------------|
| Waves rewards | Yes — `waves_inventory.add_rolled_item_with_rarity` |
| Castle chests / world pickups / merchant buys | Yes — `InventoryService.add_loot` |
| Enemy global skip drops | No — consumables via `add_item` |

### Biome loot tables
`BiomeRegistry.get_biome` resolves `lootTables` from inline biome JSON, `lootTablePath`, or `content/loot/tables/<biome_id>.json` via `LootTableLoader`. `ProcgenLootRoller.roll_chest` reads resolved tables. `forgotten_castle` uses `content/loot/tables/forgotten_castle.json`.

### Global drops
`GlobalDropService.roll_enemy_drop` reads `skipItems[]` with `itemId` + `chance`, scales by endless floor bonus and castle tier loot bonus. Called from `castle_enemy_base._try_roll_global_drop`; skipped in waves mode. On hit, `InventoryService.add_item(drop_id, 1)` — no affix roll (skip items are consumables).

### Chests
`LootChest.configure(placement)` copies `placement.items`. `_open` grants each entry via `add_loot` (equipment auto-rolls) and `RunFlow.register_loot`.

### Equipment
`SLOT_ORDER` (`equipment.gd:6-16`): helmet, chest, gloves, boots, weapon, secondary, ring, amulet, relic. `aggregate_stats` sums def `stats` for `STAT_KEYS`, folds base and affix flat elemental damage (`physicalDamage`, `fireDamage`, etc.) into `bonusDamage`, then resolves other affix stats through `AffixRoller.get_affix_stat`. `CombatStatModifiers.flat_damage_bonus` reads `bonusDamage` in `WeaponController`.

## Contracts

**Content keys — rarity_rules:** `rarityWeights`, `affixCounts` (also accepts legacy `rarities`).

**Content keys — affix:** `id`, `stat`, `tiers`, `itemTypes`, `weight`.

**Content keys — loot table:** `schemaVersion`, `biomeId`, `lootTables.{treasure,secret,side,armory}[]` with `itemId`, `quantity`, `weight`, optional `minTier`.

**Consumers of aggregate stats:** `InventoryService.apply_equipment_to_player_node`, inventory UI tooltips, `WeaponController`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Rarity weight + affix count tables | IMPLEMENTED | `affix_roller.gd`, `rarity_rules.json` |
| Affix `tiers` / `itemTypes` / `weight` | IMPLEMENTED | `_roll_tier_value`, `_pick_weighted_affixes` |
| Waves rolled loot | IMPLEMENTED | `waves_run_service.gd` |
| Castle chest/pickup/merchant affix rolls | IMPLEMENTED | `add_loot`, `loot_chest.gd`, `world_item_pickup.gd`, `merchant_service.gd` |
| External biome loot tables | IMPLEMENTED (1 biome) | `content/loot/tables/forgotten_castle.json`, `loot_table_loader.gd` |
| Elemental affix → combat damage | IMPLEMENTED | `equipment.gd` FLAT_DAMAGE affix fold; `weapon_controller.gd:458` |
| Global skip drops | IMPLEMENTED | `global_drop_service.gd`, `castle_enemy_base.gd` |
| Equipment slot aggregate → combat | IMPLEMENTED | `equipment.gd` + `inventory_service.gd` |
| Enemy gear drop tables | ABSENT | No `dropTable` on enemy JSON consumed for gear |
| `mythic` in rarity_rules | REMOVED | `aumbral` only; `validate.mjs` guard |

## Related
- Improvement plan: [`../actual_improvements/loot-and-equipment.md`](../actual_improvements/loot-and-equipment.md) — **FINISHED**
- [`inventory-service.md`](inventory-service.md), [`content-data.md`](content-data.md), [`waves-run.md`](waves-run.md)
