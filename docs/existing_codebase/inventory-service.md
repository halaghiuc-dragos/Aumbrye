# Inventory service

`InventoryService` is the autoload that owns a `GridInventory` (6×4 default), equipment application to the player, quick slots, dungeon keys, and run-loot stripping. World pickups, chests, and enemy global drops call `add_loot`, which rolls affixes for equipment and stamps `runLoot` during active runs. Hub merchant buys still use plain `add_item` so vendor gear is not tagged as run loot.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/inventory/inventory_service.gd` | Autoload — add/equip/stats/quick slots/run loot |
| `apps/game/client/scripts/inventory/grid_inventory.gd` | Grid placement, equip dictionary, sort/filter, rolled place |
| `apps/game/client/scripts/inventory/world_item_pickup.gd` | Area3D interact pickup → `add_loot` + `RunFlow.register_loot` |
| `apps/game/client/scripts/items/equipment.gd` | Slot order, stat aggregation (used by service) |
| `apps/game/client/scripts/loot/loot_chest.gd` | Chest open → `add_loot` per entry |

## How it works

### Lifecycle
`_ready` connects `inventory.changed`, `RunBuffs.buffs_changed`, `ProgressionService.progression_changed` → `_apply_equipment_to_player`.

### Add paths
| API | Behaviour |
|-----|-----------|
| `add_item(id, qty, instance_data)` | `GridInventory.add_item`; on success `_on_item_added_success` (fetch quest, relic, achievements) |
| `add_loot(id, opts)` | Equipment/accessories roll via `add_rolled_item` with run seed; stacks use `add_item`; optional `runLoot` stamp; emits `inventory_rejected` on failure |
| `add_rolled_item(id, seed, instance_data)` | Forwards to grid roller with current run mode |
| `add_dungeon_key` / `has_dungeon_key` / `consume_dungeon_key` / `clear_dungeon_keys` | Instance metadata on `dungeon_key` item |

`GridInventory.add_item` stacks when `stackSize > 1` and no affixes; else first-fit place; copies `instance_data`; may stamp def `rarity` when non-common.

`add_rolled_item` on the grid calls `AffixRoller.roll_instance`, merges optional `instance_data`, then `_place_rolled_instance`. Waves mode uses `add_rolled_item_with_rarity` on a **separate** `waves_inventory` (`waves_run_service.gd`), not `InventoryService.add_rolled_item`.

### Pickup
`WorldItemPickup._pickup` calls `InventoryService.add_loot` then `RunFlow.register_loot(item_id)` then `queue_free`. Default export `item_id = "iron_scrap"`.

### Equipment → player
`apply_equipment_to_player_node` merges equipment + class + talent + run buffs via `get_equipment_stats`, then configures `Health`, `Stamina`, `Poise`, `WeaponController`, `Locomotion`, `Guard`, and metas `combat_defense` / `combat_damage_reduction`.

Equip from grid: `equip_from_index` uses `Equipment.slot_for_item_def`. Unequip requires free grid space.

### Quick slots
Four indices (`quick_slot_indices`, default `[-1,-1,-1,-1]`). `activate_quick_slot` refuses waves mode; otherwise equip or consume. Consumables heal via `Health.heal(def.healAmount)` default 30.

### Run loot
`remove_run_loot(item_ids)` removes up to 999 of each id from grid slots and clears equipped instances tagged `runLoot` or whose `itemId` is in the removal list. Re-applies equipment to the player after strip.

### Rejection feedback
`inventory_rejected(reason)` — `combat_hud.gd` shows a run warning banner; `hub.gd` shows the hub message label when the grid is full.

### Save
`get_save_inventory` / `apply_save_inventory` persist grid via `to_save_dict` / `from_save_dict` plus `quickSlots`. Schema version on grid dict is `1`. Instance key `runLoot` is tolerated on save slots (default false).

## Contracts

**Signals:** `inventory_changed`, `equipment_stats_changed(stats)`, `inventory_rejected(reason)`; grid also emits `changed`, `item_equipped`, `item_unequipped`.

**Autoloads:** `ItemCatalog`, `RunFlow`, `RunBuffs`, `ProgressionService`, `CharacterService`, `LocalSave`, `AffixRoller`, `ClassCatalog`, `Equipment`, `QuestService`.

**Grid defaults:** `DEFAULT_WIDTH := 6`, `DEFAULT_HEIGHT := 4`.

**Filter/sort enums:** `SORT_MODES`, `FILTER_TYPES`, `FILTER_RARITIES` — `_rarity_weight` ranks `aumbral` above `legendary`.

**Item def:** optional `rollAffixes` (bool) on `item-definition` schema forces rolling for non-equipment types.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Grid add/move/equip/unequip/consume | IMPLEMENTED | `grid_inventory.gd` |
| Equipment stats applied to player | IMPLEMENTED | `inventory_service.gd` |
| Unified `add_loot` pipeline | IMPLEMENTED | `inventory_service.gd` |
| World pickup + chest via `add_loot` | IMPLEMENTED | `world_item_pickup.gd`, `loot_chest.gd` |
| Enemy global drops via `add_loot` | IMPLEMENTED | `castle_enemy_base.gd` |
| Fetch quest hook on add | IMPLEMENTED | `_on_item_added_success` |
| Run loot strip including equipped | IMPLEMENTED | `remove_run_loot`, `strip_equipped_run_loot` |
| Full grid player feedback | IMPLEMENTED | `inventory_rejected` → HUD/hub |
| Sort by rarity for `aumbral` | IMPLEMENTED | `_rarity_weight` |

## Related
- Improvement plan: [`../actual_improvements/inventory-service.md`](../actual_improvements/inventory-service.md) — **FINISHED**
- [`loot-and-equipment.md`](loot-and-equipment.md), [`dialogue-quests.md`](dialogue-quests.md), [`local-save.md`](local-save.md), [`ui/inventory_ui.md`](ui/inventory_ui.md)
