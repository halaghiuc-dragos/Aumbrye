# Inventory service — improvement plan

## Status: FINISHED

## Current state
Grid inventory, equipment application, quick slots, and run-loot removal are on the live path. Castle chests, world pickups, and enemy global drops route through `add_loot`, which rolls affixes for equipment and stamps `runLoot` during active runs. Fetch quests hook on every successful add. Full-grid rejection surfaces `inventory_rejected` to the combat HUD and hub message label.

## Gaps (closed)
| ID | Sev | Gap | Resolution |
|----|-----|-----|------------|
| INV-01 | P0 | Castle/chest/pickup loot never called `add_rolled_item` | `add_loot` + chest/pickup/enemy migration |
| INV-02 | P0 | Successful `add_item` did not call `QuestService.register_fetch` | `_on_item_added_success` on all add paths |
| INV-03 | P1 | Full inventory: silent pickup/chest failure | `inventory_rejected` + HUD/hub listeners |
| INV-04 | P1 | `remove_run_loot` only stripped grid slots | `runLoot` tagging + `strip_equipped_run_loot` |
| INV-05 | P2 | `_rarity_weight` ignored `aumbral` | Weight `6` above legendary |

## Target design (implemented)

### One add pipeline
`add_loot(item_id, opts)` — materials/consumables/keys stack via `add_item`; equipment rolls via `add_rolled_item` with run seed; always `register_fetch` on success; emits `inventory_rejected` on failure.

### Run loot honesty
Run pickups stamp `runLoot: true`. `remove_run_loot` strips grid quantities and clears equipped instances tagged `runLoot` or matching listed ids.

### Rarity sort
`aumbral` weight `6` above legendary.

## Acceptance criteria
- [x] Chest/pickup equipment in castle mode produces rolled instances with `rarity` (INV-01)
- [x] Adding `iron_scrap` completes active `fetch_scrap` (INV-02)
- [x] Full grid pickup shows HUD/hub message and leaves the world item (INV-03)
- [x] Death after equipping run-tagged drop removes it from equipment (INV-04)
- [x] Rarity sort places aumbral above legendary (INV-05)

## Validation
`inventory_suite.gd`: `inv.add_loot.rolls_equipment`, `inv.fetch_hook`, `inv.full_grid_rejects`, `inv.rarity_weight.aumbral`, `inv.remove_run_loot.equipped`.

## Related
- Existing state: [`../existing_codebase/inventory-service.md`](../existing_codebase/inventory-service.md)
- [`loot-and-equipment.md`](loot-and-equipment.md), [`dialogue-quests.md`](dialogue-quests.md)
