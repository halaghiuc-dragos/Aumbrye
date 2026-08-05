# Inventory service — improvement plan

## Current state
Grid inventory, equipment application, quick slots, and run-loot removal are on the live path. See [`../existing_codebase/inventory-service.md`](../existing_codebase/inventory-service.md). The rolled-item API is dead for `InventoryService`; castle loot never gets affixes. Pickups do not notify fetch quests. Full-grid pickup fails silently.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| INV-01 | P0 | Castle/chest/pickup loot never calls `add_rolled_item` — affix economy absent outside waves | `loot_chest.gd:72`, `world_item_pickup.gd:51`, `inventory_service.gd:90-92` (no callers) |
| INV-02 | P0 | Successful `add_item` does not call `QuestService.register_fetch` — fetch quests stuck | `inventory_service.gd:36-43`; cross-link **DLQ-02** |
| INV-03 | P1 | Full inventory: pickup/chest add returns false with no player message | `world_item_pickup.gd:50-53`, `loot_chest.gd:68-73` |
| INV-04 | P1 | `remove_run_loot` only strips grid slots — equipped run drops remain | `inventory_service.gd:170-172` |
| INV-05 | P2 | `_rarity_weight` ignores `aumbral` so rarity sort underranks it | `grid_inventory.gd:450-457` |

## Target design

### One add pipeline
```gdscript
func add_loot(item_id: String, opts: Dictionary = {}) -> bool
```
- Materials/consumables/keys → stack `add_item`.
- Equipment/weapons (and defs with `rollAffixes: true`) → `add_rolled_item` with run seed.
- Always `QuestService.register_fetch(item_id)` on success.
- On failure, emit `inventory_rejected(reason)` for HUD toast ("Inventory full").

Chests, pickups, merchant grants, and enemy equipment drops route through `add_loot`. Waves keep its separate inventory but should share the roller rules (see LOO).

### Run loot honesty
`remove_run_loot` also unequips any equipped instance whose `itemId` is in the list (or stamped `runLoot: true` on the instance at add time). Prefer instance tagging so vendor gear bought mid-run is not stripped incorrectly.

### Rarity sort
Give `aumbral` weight `6` above legendary.

## Work plan

1. **Hook `register_fetch` in `add_item` success path** — closes INV-02 / DLQ-02.
2. **Introduce `add_loot` + migrate chest/pickup/enemy drops** — closes INV-01 (depends on LOO roller fix for meaningful affixes).
3. **Toast on full grid** — closes INV-03.
4. **Tag run loot instances + strip equipped** — closes INV-04.
5. **Fix `_rarity_weight` for aumbral** — closes INV-05.

## Data and schema changes

- Optional item def key `rollAffixes` (bool) on `item-definition` schema.
- Instance key `runLoot` on save slots — tolerate absence (default false); no migrator required if default is fine.

## Acceptance criteria
- [ ] Opening a chest that grants `iron_sword` in castle mode produces a slot with `rarity` and possibly `affixes` when roller rules say so. (INV-01)
- [ ] Adding `iron_scrap` completes active `fetch_scrap`. (INV-02)
- [ ] Full grid pickup shows a HUD/hub message and leaves the world item. (INV-03)
- [ ] Death after equipping a run-tagged drop removes it from equipment. (INV-04)
- [ ] Rarity sort places aumbral above legendary. (INV-05)

## Validation
Extend `inventory_suite.gd` + `hub_m4_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `inv.add_loot.rolls_equipment` | `add_loot("castle_sword")` yields affix-capable instance |
| `inv.fetch_hook` | Accept fetch quest, add scrap, assert completed |
| `inv.full_grid_rejects` | Fill grid, `add_item` false, signal or flag set |
| `inv.rarity_weight.aumbral` | Sort order aumbral > legendary |

## Related
- Existing state: [`../existing_codebase/inventory-service.md`](../existing_codebase/inventory-service.md)
- [`loot-and-equipment.md`](loot-and-equipment.md), [`dialogue-quests.md`](dialogue-quests.md)
