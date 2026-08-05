# Loot and equipment

Loot has three live pieces: static chest/pickup grants (`add_item`), rare global skip-item drops (`GlobalDropService`), and affix rolling (`AffixRoller`) used by **waves** inventory only. `Equipment` aggregates equipped instance stats for the player. Affix **rarity weights and affix counts** from `rarity_rules.json` are respected when rolling; per-affix **`tiers` / `itemTypes` / `weight`** are not.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/loot/affix_roller.gd` | `AffixRoller.roll_instance` / `get_affix_stat` |
| `apps/game/client/scripts/loot/rarity_registry.gd` | Tier order, mythic→aumbral alias, mode bonuses |
| `apps/game/client/scripts/loot/global_drop_service.gd` | Skip-floor item chances from `global_drops.json` |
| `apps/game/client/scripts/loot/loot_chest.gd` | Interact chest → plain `add_item` |
| `apps/game/client/scripts/items/equipment.gd` | Slots, aggregate/compare/format stats |
| `content/affixes/prefixes.json`, `suffixes.json`, `rarity_rules.json` | Affix defs + weights/counts |
| `content/loot/global_drops.json` | Skip item chances |
| `content/items/**` | Item definitions |

## How it works

### Rarity
`RarityRegistry.TIER_ORDER`: common → magic → rare → epic → legendary → aumbral (`rarity_registry.gd:5-7`). `LEGACY_ALIASES` maps `mythic`/`umbral` → `aumbral`. Mode drop bonuses: endless `0.08`, waves `0.06` on rare+ weights (`rarity_registry.gd:28-31`, applied in `AffixRoller._pick_rarity` at `affix_roller.gd:109-119`).

### `AffixRoller.roll_instance`
1. Load prefixes/suffixes/rules once (`affix_roller.gd:65-74`).
2. Pick rarity from `rarityWeights` (or forced rarity) (`_pick_rarity`, lines 109-133).
3. Affix count from `affixCounts` min/max for that rarity (`_roll_affix_count`, lines 100-106) — **respects rarity tables**.
4. Shuffle **entire** prefix+suffix pool; take first N; value = `randi_range(affix.min, affix.max)` defaulting to **1–3** (`affix_roller.gd:30-38`) — **ignores authored `tiers`**, **ignores `itemTypes`**, **ignores `weight`**.

Authored affixes look like (`prefixes.json`):

```json
{ "id": "sharp", "stat": "physicalDamage", "itemTypes": ["weapon"], "weight": 100,
  "tiers": { "common": { "min": 2, "max": 4 }, "legendary": { "min": 21, "max": 28 }, ... } }
```

### Where rolling runs
| Path | Uses roller? |
|------|----------------|
| Waves rewards | Yes — `waves_inventory.add_rolled_item_with_rarity` (`waves_run_service.gd:127`) |
| `InventoryService.add_rolled_item` | API only — **no callers** |
| Chests / world pickups / enemy global drops | No — `add_item` |
| Merchant / quest rewards | No — `add_item` |

### Global drops
`GlobalDropService.roll_enemy_drop` (`global_drop_service.gd:10-29`) reads `skipItems[]` with `itemId` + `chance`, scales by endless floor bonus and castle tier loot bonus. Called from `castle_enemy_base._try_roll_global_drop` (`castle_enemy_base.gd:342-351`); skipped in waves mode. On hit, `InventoryService.add_item(drop_id, 1)` — no affix roll (skip items are consumables).

### Chests
`LootChest.configure(placement)` copies `placement.items` (`loot_chest.gd:27-28`). `_open` adds each `itemId`/`quantity` via `add_item` and `RunFlow.register_loot` (`loot_chest.gd:63-73`).

### Equipment
`SLOT_ORDER` (`equipment.gd:6-9`): helmet, chest, gloves, boots, weapon, secondary, ring, amulet, relic. `aggregate_stats` sums def `stats` for `STAT_KEYS` plus flat elemental damage into `bonusDamage`, then resolves each instance affix through `AffixRoller.get_affix_stat` (`equipment.gd:50-59`, `140-160`). `slot_for_item_def` uses `equipmentSlot` or weapon/relic heuristics (`equipment.gd:31-41`).

## Contracts

**Content keys — rarity_rules:** `rarityWeights`, `affixCounts` (also accepts legacy `rarities`).

**Content keys — affix:** `id`, `stat`, `min`/`max` (unused in data), `tiers`, `itemTypes`, `weight`.

**Consumers of aggregate stats:** `InventoryService.apply_equipment_to_player_node`, inventory UI tooltips.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Rarity weight + affix count tables | IMPLEMENTED | `affix_roller.gd:100-133`, `rarity_rules.json` |
| Affix `tiers` / `itemTypes` / `weight` | FAKE | Authored in JSON; roller uses shuffle + default 1–3 (`affix_roller.gd:30-38`) |
| Waves rolled loot | IMPLEMENTED | `waves_run_service.gd:127` |
| Castle chest/pickup affix rolls | ABSENT | `loot_chest.gd:72`, `world_item_pickup.gd:51` |
| Global skip drops | IMPLEMENTED | `global_drop_service.gd`, `castle_enemy_base.gd:342-351` |
| Equipment slot aggregate → combat | IMPLEMENTED | `equipment.gd` + `inventory_service.gd:181-215` |
| Enemy/boss gear drop tables | ABSENT | No `dropTable` on enemy JSON consumed for gear |
| `InventoryService.add_rolled_item` | STUB | No callers |

## Related
- Improvement plan: [`../actual_improvements/loot-and-equipment.md`](../actual_improvements/loot-and-equipment.md)
- [`inventory-service.md`](inventory-service.md), [`content-data.md`](content-data.md), [`waves-run.md`](waves-run.md)
