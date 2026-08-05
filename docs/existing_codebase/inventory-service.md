# Inventory service

`InventoryService` is the autoload that owns a `GridInventory` (6×4 default), equipment application to the player, quick slots, dungeon keys, and run-loot stripping. World pickups and chests call into it. Affix-rolled adds exist on the API (`add_rolled_item`) but have **no gameplay callers** — castle loot uses plain `add_item`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/inventory/inventory_service.gd` | Autoload — add/equip/stats/quick slots/run loot |
| `apps/game/client/scripts/inventory/grid_inventory.gd` | Grid placement, equip dictionary, sort/filter, rolled place |
| `apps/game/client/scripts/inventory/world_item_pickup.gd` | Area3D interact pickup → `add_item` + `RunFlow.register_loot` |
| `apps/game/client/scripts/items/equipment.gd` | Slot order, stat aggregation (used by service) |
| `apps/game/client/scripts/loot/loot_chest.gd` | Chest open → `add_item` per entry |

## How it works

### Lifecycle
`_ready` (`inventory_service.gd:15-20`) connects `inventory.changed`, `RunBuffs.buffs_changed`, `ProgressionService.progression_changed` → `_apply_equipment_to_player`.

### Add paths
| API | Behaviour |
|-----|-----------|
| `add_item(id, qty, instance_data)` | `GridInventory.add_item`; if run active and def has `runRelicId`, `RunBuffs.add_relic` (`inventory_service.gd:36-43`) |
| `add_rolled_item(id, seed)` | Forwards to `inventory.add_rolled_item` with current run mode (`inventory_service.gd:90-92`) — **no callers** under `apps/` |
| `add_dungeon_key` / `has_dungeon_key` / `consume_dungeon_key` / `clear_dungeon_keys` | Instance metadata on `dungeon_key` item (`inventory_service.gd:46-87`) |

`GridInventory.add_item` (`grid_inventory.gd:97-140`): stacks when `stackSize > 1` and no affixes; else first-fit place; copies `instance_data`; may stamp def `rarity` when non-common.

`add_rolled_item` on the grid (`grid_inventory.gd:143-147`) calls `AffixRoller.roll_instance` then `_place_rolled_instance`. Waves mode uses `add_rolled_item_with_rarity` on a **separate** `waves_inventory` (`waves_run_service.gd:127`), not `InventoryService.add_rolled_item`.

### Pickup
`WorldItemPickup._pickup` (`world_item_pickup.gd:50-53`): `InventoryService.add_item` then `RunFlow.register_loot(item_id)` then `queue_free`. Default export `item_id = "iron_scrap"`. Does not call `QuestService.register_fetch`.

### Equipment → player
`apply_equipment_to_player_node` (`inventory_service.gd:181-215`) merges equipment + class + talent + run buffs via `get_equipment_stats`, then configures `Health`, `Stamina`, `Poise`, `WeaponController`, `Locomotion`, `Guard`, and metas `combat_defense` / `combat_damage_reduction`.

Equip from grid: `equip_from_index` (`grid_inventory.gd:242-262`) uses `Equipment.slot_for_item_def`. Unequip requires free grid space.

### Quick slots
Three indices (`quick_slot_indices`, default `[-1,-1,-1]`). `activate_quick_slot` refuses waves mode (`inventory_service.gd:248-250`); otherwise equip or consume. Consumables heal via `Health.heal(def.healAmount)` default 30 (`inventory_service.gd:273-284`).

### Run loot
`remove_run_loot(item_ids)` removes up to 999 of each id from slots (`inventory_service.gd:170-172`). Does not unequip matching gear.

### Save
`get_save_inventory` / `apply_save_inventory` (`inventory_service.gd:99-108`) persist grid via `to_save_dict` / `from_save_dict` plus `quickSlots`. Schema version on grid dict is `1` (`grid_inventory.gd:31-32`).

## Contracts

**Signals:** `inventory_changed`, `equipment_stats_changed(stats)`; grid also emits `changed`, `item_equipped`, `item_unequipped`.

**Autoloads:** `ItemCatalog`, `RunFlow`, `RunBuffs`, `ProgressionService`, `CharacterService`, `LocalSave`, `AffixRoller`, `ClassCatalog`, `Equipment`.

**Grid defaults:** `DEFAULT_WIDTH := 6`, `DEFAULT_HEIGHT := 4` (`grid_inventory.gd:7-8`).

**Filter/sort enums:** `SORT_MODES`, `FILTER_TYPES`, `FILTER_RARITIES` (`grid_inventory.gd:10-12`) — note filter list includes `aumbral` but `_rarity_weight` omits `aumbral`/`mythic` (returns 0) (`grid_inventory.gd:450-457`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Grid add/move/equip/unequip/consume | IMPLEMENTED | `grid_inventory.gd` |
| Equipment stats applied to player | IMPLEMENTED | `inventory_service.gd:181-215` |
| World pickup + chest plain add | IMPLEMENTED | `world_item_pickup.gd:50-53`, `loot_chest.gd:68-73` |
| Dungeon key instance metadata | IMPLEMENTED | `inventory_service.gd:46-87` |
| `InventoryService.add_rolled_item` | STUB | Defined `inventory_service.gd:90-92`; zero callers |
| Castle/chest loot affix rolling | ABSENT | Chests/pickups/enemies use `add_item` only |
| Fetch quest hook on pickup | ABSENT | No `register_fetch` call (`world_item_pickup.gd:50-53`) |
| Sort by rarity for `aumbral` | PARTIAL | Filter allows it; weight 0 (`grid_inventory.gd:450-457`) |
| Full grid = silent pickup failure | PARTIAL | `_pickup` no feedback when `add_item` returns false |

## Related
- Improvement plan: [`../actual_improvements/inventory-service.md`](../actual_improvements/inventory-service.md)
- [`loot-and-equipment.md`](loot-and-equipment.md), [`dialogue-quests.md`](dialogue-quests.md), [`local-save.md`](local-save.md), [`ui/inventory_ui.md`](ui/inventory_ui.md)
