# NPC and hub services

Four hub services back the vendor UIs: `MerchantService` (buy/sell), `BlacksmithService` (upgrade, repair, unlock, respec), `StorageService` (a second grid inventory), and the catalogs that feed them. `NpcBase` and `NpcCatalog` turn `content/npcs/*.json` into the three hub NPCs. `StorageService` is an autoload; the rest are `static`-only `RefCounted` classes.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/hub/merchant_service.gd` | `MerchantService` â€” save-backed per-merchant stock, `get_slot_sell_price`, `buy_item`, `sell_item(inv_index, quantity)` |
| `apps/game/client/scripts/hub/merchant_catalog.gd` | `MerchantCatalog` â€” loads `content/merchant/*.json`; `reload()` / `is_loaded()` |
| `apps/game/client/scripts/hub/blacksmith_service.gd` | `BlacksmithService` â€” upgrade, durability, repair, unlock, talent respec |
| `apps/game/client/scripts/hub/recipe_catalog.gd` | `RecipeCatalog` â€” `upgrade`, `repair`, `unlock` queries; `upgrade_stat_bonus`; `reload()` / `is_loaded()` |
| `apps/game/client/scripts/hub/storage_service.gd` | `StorageService` autoload â€” 8Ã—6 `GridInventory`, whole-slot transfers, deferred autosave |
| `apps/game/client/scripts/items/equipment.gd` | `Equipment.upgrade_multiplier`, `Equipment.slot_stats` â€” stat path for upgrades and 0 durability |
| `apps/game/client/scripts/npc/npc_base.gd` | `NpcBase` â€” greet-then-shop with `_greeted_this_visit` reset on zone exit |
| `apps/game/client/scripts/npc/npc_catalog.gd` | `NpcCatalog` â€” loads `content/npcs/*.json`; `reload()` / `is_loaded()` |
| `apps/game/client/scripts/loot/rarity_registry.gd` | `RarityRegistry.sell_multiplier` â€” sell price scaling by tier |
| `apps/game/client/scripts/hub/hub_diorama.gd` | `HubDiorama._position_npcs_from_content` â€” reads NPC `position` from catalog |
| `content/npcs/*.json` | 3 files: `blacksmith_aldric`, `merchant_elara`, `warden_mira` |
| `content/merchant/*.json` | 2 files: `hub_merchant` (6 rows), `dungeon_merchant` (3 rows) |
| `content/recipes/*.json` | 5 files: 2 `upgrade`, 1 `repair`, 2 `unlock` |

## How it works

### NPCs
`NpcCatalog._ensure_loaded` (`npc_catalog.gd:34-58`) walks `content/npcs`, loads each `.json`, and sets `_loaded` when complete. `reload()` clears and re-walks.

`NpcBase._on_interacted` (`npc_base.gd:51-72`) for `blacksmith` and `merchant`: if `dialogueId` is set and `_greeted_this_visit` is false, emits `dialogue_requested` once; otherwise emits `shop_requested`. `_greeted_this_visit` resets on `InteractArea.player_exited`.

`HubDiorama._position_npcs_from_content` (`hub_diorama.gd:821-836`) applies each `hub_npc`'s catalog `position` after diorama dressing.

| File | `id` | `displayName` | `interactType` | `dialogueId` | `position` |
|------|------|---------------|----------------|--------------|------------|
| `blacksmith_aldric.json` | `blacksmith_aldric` | Aldric the Blacksmith | `blacksmith` | `aldric_greeting` | `(-14.9, 0, -3.4)` |
| `merchant_elara.json` | `merchant_elara` | Elara the Merchant | `merchant` | `elara_greeting` | `(-12, 0, 11.2)` |
| `warden_mira.json` | `warden_mira` | Warden Mira | `dialogue` | `mira_greeting` | `(12, 0, 11.2)` |

Dialogue actions `open_blacksmith` / `open_merchant` in `aldric_greeting.json` and `elara_greeting.json` open the vendor UIs from `dialogue_ui.gd:139-142`.

### Merchant
Stock is per-merchant and persisted in `save.merchants.<merchant_id>.purchased` (`local_save.gd:256-288`, `merchant_service.gd:41-43`). `get_available_stock` subtracts purchased counts and drops unknown item ids with one warning per session (`merchant_service.gd:56-74`).

`buy_item` (`merchant_service.gd:77-96`): `spend_gold` first; on inventory failure refunds gold before any save. `sell_item(inv_index, quantity)` (`merchant_service.gd:99-121`): `get_slot_unit_sell_price` applies rarity, upgrade level, and affix values; `quantity < 0` sells the whole stack.

`MerchantService.restock_all()` is called from `run_flow.gd` before every `run_ended.emit`.

### Blacksmith
`Equipment.slot_stats` (`equipment.gd:78-118`) applies `upgrade_multiplier` (+6% per level) or accumulated recipe `statBonus`, and returns zeros when `durability <= 0`.

`RecipeCatalog.upgrade_stat_bonus(item_id, to_level)` sums `statBonus` from all upgrade recipes with `toLevel <= to_level`.

`BlacksmithService.is_unlocked(item_id)` (`blacksmith_service.gd:79-86`): owned recipe id in `save.recipes`, or `unlockFlag` truthy on `CharacterService`. `unlock_item` charges gold, requires `ProgressionService.level`, appends recipe id, grants the item.

`InventoryService.apply_death_durability_loss(15)` (`inventory_service.gd:117-131`) is called from `run_flow.gd:on_player_died` and reduces equipped upgradeable items' durability.

### Storage
`move_to_storage` / `move_to_inventory` (`storage_service.gd:36-60`) move the full slot dictionary via `GridInventory.add_slot` and return `{"ok", "error"}` with `invalid slot`, `storage full`, or `inventory full`. Autosave uses `LocalSave.request_autosave(DEFERRED)` (`storage_service.gd:14-16`).

## Contracts
**Signals:** `NpcBase.dialogue_requested`, `NpcBase.shop_requested`, `StorageService.storage_changed`.

**Save keys:** `storage`, `recipes` (array of recipe id strings), `merchants` (per-merchant `purchased` counters). Normalized in `save_migrator.gd:_normalize_merchants`, `_normalize_recipes`, and default `durability` on equipment slots in `_normalize_slot_entry`.

**Catalog lifecycle:** `NpcCatalog`, `MerchantCatalog`, and `RecipeCatalog` each expose `reload()` and `is_loaded()`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Data-driven NPC definitions and interact routing | IMPLEMENTED | `npc_catalog.gd`, `npc_base.gd`, three files in `content/npcs/` |
| NPC greet-then-shop with zone reset | IMPLEMENTED | `npc_base.gd:13`, `npc_base.gd:47-72` |
| NPC position from content | IMPLEMENTED | `hub_diorama.gd:821-836`, `content/npcs/*.json` |
| Merchant buy with gold-first ordering and refund | IMPLEMENTED | `merchant_service.gd:77-96` |
| Merchant stock per-merchant, persisted, restocked on run end | IMPLEMENTED | `merchant_service.gd:41-43`, `local_save.gd:256-288`, `run_flow.gd` `restock_all` before `run_ended` |
| Merchant sell stack quantity and rarity-aware pricing | IMPLEMENTED | `merchant_service.gd:24-38`, `merchant_service.gd:99-121`, `rarity_registry.gd:75-79` |
| Blacksmith upgrade affects stats | IMPLEMENTED | `equipment.gd:78-118`, `recipe_catalog.gd:upgrade_stat_bonus` |
| Blacksmith repair after death durability loss | IMPLEMENTED | `inventory_service.gd:117-131`, `run_flow.gd:on_player_died`, `blacksmith_service.gd:can_repair` |
| Unlock recipes and `save.recipes` | IMPLEMENTED | `recipe_catalog.gd:26-41`, `blacksmith_service.gd:79-130`, `local_save.gd:238-252` |
| Loadout unlock via `BlacksmithService.is_unlocked` | IMPLEMENTED | `loadout_ui.gd:79-80` |
| Storage whole-slot transfer with error strings | IMPLEMENTED | `storage_service.gd:36-60`, `grid_inventory.gd:add_slot` |
| Storage deferred autosave | IMPLEMENTED | `storage_service.gd:14-16` |
| Catalog reload hooks | IMPLEMENTED | `npc_catalog.gd`, `merchant_catalog.gd`, `recipe_catalog.gd` |
| `dungeon_merchant` reachability in runs | BROKEN | `room_merchant_content.gd:53`; merchant room weight chain â€” see [`room-content.md`](room-content.md) |

## Related
- Improvement plan: [`../actual_improvements/npc-hub-services.md`](../actual_improvements/npc-hub-services.md) - **FINISHED**
- [`hub.md`](hub.md), [`dialogue-quests.md`](dialogue-quests.md), [`inventory-service.md`](inventory-service.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`character-service.md`](character-service.md), [`progression-service.md`](progression-service.md), [`content-catalog.md`](content-catalog.md), [`content-data.md`](content-data.md), [`room-content.md`](room-content.md), [`ui/hub_vendors.md`](ui/hub_vendors.md), [`ui/inventory_ui.md`](ui/inventory_ui.md)
