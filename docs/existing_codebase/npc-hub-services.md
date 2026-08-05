# NPC and hub services

Four hub services back the vendor UIs: `MerchantService` (buy/sell), `BlacksmithService` (upgrade, repair, respec), `StorageService` (a second grid inventory), and the two catalogs that feed them. `NpcBase` and `NpcCatalog` turn `content/npcs/*.json` into the three hub NPCs. Three of the four services are `static`-only `RefCounted` classes; `StorageService` is an autoload.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/hub/merchant_service.gd` | `MerchantService` — prices, stock accounting, `buy_item`, `sell_item` |
| `apps/game/client/scripts/hub/merchant_catalog.gd` | `MerchantCatalog` — loads `content/merchant/*.json` into `id -> items` |
| `apps/game/client/scripts/hub/blacksmith_service.gd` | `BlacksmithService` — upgrade level, durability, repair, talent respec |
| `apps/game/client/scripts/hub/recipe_catalog.gd` | `RecipeCatalog` — loads `content/recipes/*.json`, queries `upgrade` and `repair` |
| `apps/game/client/scripts/hub/storage_service.gd` | `StorageService` autoload — an 8 x 6 `GridInventory` and two transfer functions |
| `apps/game/client/scripts/npc/npc_base.gd` | `NpcBase` — reads its definition, routes interact by `interactType` |
| `apps/game/client/scripts/npc/npc_catalog.gd` | `NpcCatalog` — loads `content/npcs/*.json` into `id -> definition` |
| `apps/game/client/scripts/loot/rarity_registry.gd` | `RarityRegistry.max_upgrade_level` — the upgrade cap |
| `content/npcs/*.json` | 3 files: `blacksmith_aldric`, `merchant_elara`, `warden_mira` |
| `content/merchant/*.json` | 2 files: `hub_merchant` (6 rows), `dungeon_merchant` (3 rows) |
| `content/recipes/*.json` | 5 files: 2 `upgrade`, 1 `repair`, 2 `unlock` |

## How it works

### NPCs
`NpcCatalog._ensure_loaded` (`npc_catalog.gd:24-45`) walks `content/npcs`, loads each `.json` through `ContentLoader.load_json`, skips files without an `id` with a warning, and stamps `content_path` onto each definition. Caching is "non-empty means loaded", so a load that yields nothing retries every call.

`NpcBase._ready` (`npc_base.gd:15-24`) reads its definition from `npc_id`, requires a child `InteractArea` of type `HubInteractable` (warning and early return otherwise), overwrites `prompt_text` with `"<displayName> (E)"`, connects `interacted` -> `_on_interacted`, and sets a `NameLabel` `Label3D` if present.

`_on_interacted` (`npc_base.gd:44-62`) switches on `interactType`:

| `interactType` | Emits |
|----------------|-------|
| `dialogue` | `dialogue_requested(npc_id, dialogueId)` when `dialogueId` is non-empty |
| `blacksmith` | `shop_requested(npc_id, "blacksmith")` |
| `merchant` | `shop_requested(npc_id, "merchant")` |
| `quest_board` | `shop_requested(npc_id, "quest_board")` |
| anything else | `dialogue_requested` with `dialogueId` as a fallback |

The three definitions:

| File | `id` | `displayName` | `interactType` | `dialogueId` | `position` |
|------|------|---------------|----------------|--------------|------------|
| `blacksmith_aldric.json` | `blacksmith_aldric` | Aldric the Blacksmith | `blacksmith` | `aldric_greeting` | `(-16, 0, -2)` |
| `merchant_elara.json` | `merchant_elara` | Elara the Merchant | `merchant` | `elara_greeting` | `(-10, 0, 12)` |
| `warden_mira.json` | `warden_mira` | Warden Mira | `dialogue` | `mira_greeting` | `(10, 0, 12)` |

Because `blacksmith` and `merchant` branches ignore `dialogueId`, Aldric's and Elara's dialogue files are unreachable through the NPC (see gaps). `position` is not read by any script: `hub_diorama.gd:699-722` positions the three NPCs from its own constants and `hub.tscn:247-256` sets the instanced transforms.

### Merchant
`MerchantCatalog.get_stock(merchant_id)` (`merchant_catalog.gd:11-14`) returns the `items` array of the matching file, or `[]`. Loading is the same directory walk as `NpcCatalog`.

`MerchantService` price rules:
- `get_buy_price(item_id, merchant_id = "hub_merchant")` (lines 13-17): the stock row's `price`, else the item definition's `value`, else 10.
- `get_sell_price(item_id)` (lines 20-21): `maxi(1, ItemCatalog.get_loot_value(item_id))`, which prefers `lootValue` then `value` then 1 (`item_catalog.gd:30-36`).

Stock accounting lives in one `static var _purchased: Dictionary` (line 6) keyed by **item id only**, not by merchant. `get_available_stock` (lines 24-37) subtracts `_purchased[itemId]` from the row's `stock` (default 99) and adds a `remaining` field. `reset_session()` (lines 9-10) clears the counter and is called by `merchant_ui.open()` (`merchant_ui.gd:41`).

`buy_item` (lines 40-57), in order: `can_afford(price)`, find the stock row, check `bought >= stock`, `InventoryService.add_item(item_id, 1)`, `CharacterService.spend_gold(price)`, increment `_purchased`, `LocalSave.autosave()`. Error strings: `not enough gold`, `out of stock`, `inventory full`, `item not sold here`.

`sell_item(inv_index)` (lines 60-73): validates the index, requires a known item definition, computes `get_sell_price(item_id)`, calls `inv.remove_at(inv_index)` — which removes the entire slot with its full `quantity` (`grid_inventory.gd:169-175`) — then `CharacterService.add_gold(price)` and `LocalSave.autosave()`. Returns `{"ok": true, "gold": price}`.

Stock content:

| Merchant | Rows |
|----------|------|
| `hub_merchant` | `health_potion` 15/10, `stamina_potion` 12/8, `iron_scrap` 8/5, `iron_sword` 45/2, `iron_boots` 35/2, `gold_ring` 55/1 |
| `dungeon_merchant` | `health_potion` 25/3, `stamina_potion` 20/2, `castle_sword` 120/1 |

### Blacksmith
| Function | Lines | Behaviour |
|----------|-------|-----------|
| `get_slot_upgrade_level(slot)` | 11-12 | `slot.upgradeLevel`, default 0 |
| `get_slot_durability(slot)` | 15-18 | `slot.durability`, default `DEFAULT_MAX_DURABILITY` = 100 |
| `get_max_durability(item_id)` | 21-23 | `def.maxDurability`, default 100 |
| `get_max_upgrade_level_for_slot(slot)` | 26-32 | `RarityRegistry.max_upgrade_level(rarity)` — 10 for `aumbral`, 5 otherwise (`rarity_registry.gd:60-61`); the slot's own `rarity` overrides the definition's |
| `get_upgrade_cost(item_id, level)` | 35-39 | The first `upgrade` recipe whose `fromLevel == level`, reading `goldCost` then `coinCost`; otherwise `25 + level * 15` |
| `can_upgrade(inv_index)` | 42-55 | `itemType` must be in `["weapon", "armor", "accessory"]`, below the cap, and affordable |
| `upgrade_item(inv_index)` | 58-73 | Spends coins, increments `slot.upgradeLevel`, emits `inv.changed`, autosaves |
| `can_repair(inv_index)` | 76-93 | Upgradeable type, `durability < maxDurability`, and affordable at the recipe cost or `maxi(1, (max - current) / 2)` |
| `repair_item(inv_index)` | 120-141 | Spends coins, sets `slot.durability = max`, emits `inv.changed`, autosaves |
| `can_respec_talents()` / `respec_talents()` | 99-117 | `RESPEC_COST` = 250 (line 96); requires `ProgressionService.talent_points_spent > 0`; calls `ProgressionService.respec_talents()` and re-applies equipment to the player node |

`RecipeCatalog.get_upgrade_recipes(item_id, current_level)` matches `type == "upgrade"` and exact `fromLevel`; `get_repair_recipe(item_id)` returns the first `type == "repair"` row (`recipe_catalog.gd:11-29`). No other `type` value is ever queried.

Recipe content:

| File | `id` | `type` | `itemId` | Keys |
|------|------|--------|----------|------|
| `castle_sword_upgrade.json` | `castle_sword_upgrade_1` | `upgrade` | `castle_sword` | `fromLevel: 0`, `toLevel: 1`, `goldCost: 50`, `statBonus: {damage: 5}` |
| `castle_sword_upgrade_2.json` | `castle_sword_upgrade_2` | `upgrade` | `castle_sword` | `fromLevel: 1`, `toLevel: 2`, `goldCost: 100`, `statBonus: {damage: 8}` |
| `castle_sword_repair.json` | `castle_sword_repair` | `repair` | `castle_sword` | `goldCost: 15` |
| `unlock_guard_spear.json` | `unlock_guard_spear` | `unlock` | `guard_spear` | `goldCost: 120`, `requiredLevel: 5`, `unlockFlag: theme_forgotten_castle_cleared` |
| `unlock_hunter_bow.json` | `unlock_hunter_bow` | `unlock` | `hunter_bow` | `goldCost: 150`, `requiredLevel: 8`, `unlockFlag: theme_crystal_caverns_cleared` |

### Storage
`StorageService` is an autoload holding `storage: GridInventory = GridInventory.new(8, 6)` (line 7). `storage.changed` is forwarded as `storage_changed` and triggers `LocalSave.autosave()` (lines 10-16). `get_save_storage` / `apply_save_storage` delegate to `GridInventory.to_save_dict` / `from_save_dict` (lines 19-24), called from `local_save.gd:580` and `local_save.gd:529`.

`move_to_storage(inv_index)` (lines 27-37) reads only `itemId` and `quantity` from the source slot, calls `storage.add_item(item_id, qty)`, and on success `inv.remove_at(inv_index)`. `move_to_inventory(storage_index)` (lines 40-49) is the mirror image. Neither passes the `instance_data` argument that `GridInventory.add_item` accepts (`grid_inventory.gd:97`).

## Contracts
**Signals:** `NpcBase.dialogue_requested(npc_id, dialogue_id)`, `NpcBase.shop_requested(npc_id, shop_type)`, `StorageService.storage_changed`. Consumed by `hub.gd:71-74` and the storage UI.

**Return shape from every mutating service call:** `{"ok": bool, "error": String}` plus `gold`, `newLevel`, or `durability` on success.

**Content keys read:** NPC — `id`, `displayName`, `interactType`, `dialogueId`. Merchant — `id`, `items[].itemId`, `items[].price`, `items[].stock`. Recipe — `type`, `itemId`, `fromLevel`, `goldCost`, `coinCost`.

**Content keys present but never read:** NPC `position`; recipe `toLevel`, `statBonus`, `requiredLevel`, `unlockFlag`, and the entire `unlock` type.

**Slot keys these services write:** `upgradeLevel`, `durability`.

**Autoload dependencies:** `CharacterService`, `InventoryService`, `LocalSave`, `ProgressionService`, `ContentLoader`, plus the static classes `ItemCatalog`, `RarityRegistry`, `MerchantCatalog`, `RecipeCatalog`, `NpcCatalog`.

**Save keys:** `storage` (via `StorageService`), `recipes` (written from `_cached_state` at `local_save.gd:585`, never populated).

**Groups:** `hub_npc` on the NPC scene root; `player` for `HubInteractable` detection.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Data-driven NPC definitions and interact routing | IMPLEMENTED | `npc_catalog.gd:24-45`, `npc_base.gd:44-62`, three files in `content/npcs/` |
| Merchant buy with gold check and inventory-full check | IMPLEMENTED | `merchant_service.gd:40-57` |
| Merchant stock loaded from content | IMPLEMENTED | `merchant_catalog.gd:11-34`, `content/merchant/hub_merchant.json` |
| Blacksmith upgrade cap from rarity | IMPLEMENTED | `blacksmith_service.gd:26-32`, `rarity_registry.gd:60-61` |
| Blacksmith upgrade cost from recipes with a formula fallback | IMPLEMENTED | `blacksmith_service.gd:35-39` |
| Talent respec for 250 gold | IMPLEMENTED | `blacksmith_service.gd:99-117` |
| Storage as a separate 8 x 6 grid, persisted | IMPLEMENTED | `storage_service.gd:7`, `local_save.gd:529`, `local_save.gd:580` |
| Upgrade effect on stats | FAKE | `upgrade_item` only increments `slot.upgradeLevel` (`blacksmith_service.gd:70`); grep of `apps/` finds `upgradeLevel` read only by `blacksmith_service.gd`, `blacksmith_ui.gd`, and `inventory_ui.gd` for a `"+N"` label — no stat path consumes it, and `statBonus` in the recipe files is never read |
| Repair | BROKEN | No code anywhere decrements `durability`; grep of `apps/` finds writes only at `blacksmith_service.gd:138`. `get_slot_durability` returns the max for any slot without the key, so `can_repair` is always false and `castle_sword_repair.json` is unreachable |
| `unlock` recipes | ABSENT | `RecipeCatalog` queries only `upgrade` and `repair` (`recipe_catalog.gd:15`, `27`); nothing reads `type == "unlock"`, `requiredLevel`, or `unlockFlag`, so `unlock_guard_spear.json` and `unlock_hunter_bow.json` are inert. Their `unlockFlag` values are the two flags `loadout_ui.gd:80-82` checks and nothing sets |
| `save.recipes` array | PLACEHOLDER | Written at `local_save.gd:585`, initialised at `local_save.gd:638`, never populated or read |
| Merchant stock limits | BROKEN | `merchant_ui.gd:41` calls `MerchantService.reset_session()` on every `open()`, so `_purchased` is cleared each time the UI opens; `gold_ring` with `stock: 1` can be bought once per open, without limit |
| Merchant stock accounting scope | BROKEN | `_purchased` is keyed by item id only (`merchant_service.gd:31`, `54`), so buying a `health_potion` from `dungeon_merchant` consumes `hub_merchant` stock of the same item |
| Merchant stock persistence | ABSENT | `_purchased` is a `static var` with no save key; searched `local_save.gd` for any merchant key |
| Selling a stack | BROKEN | `sell_item` pays `get_sell_price(item_id)` once but `inv.remove_at` deletes the whole slot including its `quantity` (`merchant_service.gd:69-71`, `grid_inventory.gd:169-175`), so a stack of 10 potions sells for the price of one |
| Sell price fidelity | PARTIAL | `get_sell_price` uses only the item definition (`merchant_service.gd:20-21`), ignoring the slot's `rarity`, `affixes`, and `upgradeLevel`, so an upgraded legendary sells for the base value |
| Buy transaction ordering | PARTIAL | `add_item` runs before `spend_gold` (`merchant_service.gd:50-53`); if the debit fails the item has already been granted |
| Storage transfer fidelity | BROKEN | `move_to_storage` and `move_to_inventory` carry only `itemId` and `quantity` (`storage_service.gd:32-33`, `44-45`), discarding `rarity`, `affixes`, `upgradeLevel`, `durability`, `instanceId`, and `keyId` |
| Storage capacity feedback | PARTIAL | Both transfers return a bare `false` on failure (`storage_service.gd:35`, `47`) with no reason, so the UI cannot distinguish "storage full" from "invalid index" |
| Aldric and Elara dialogue | BROKEN | `content/dialogue/aldric_greeting.json` and `elara_greeting.json` exist and are named by the NPC definitions, but the `blacksmith` and `merchant` branches at `npc_base.gd:53-56` never emit `dialogue_requested` |
| NPC `position` in content | FAKE | Present in all three files; no script reads it — positioning is hardcoded at `hub_diorama.gd:699-722` |
| `dungeon_merchant` reachability | BROKEN | Only opened by `room_merchant_content.gd:53`, and the `merchant` room type is unreachable because the cumulative weight chain reaches 1.01 at `empty` before merchant's 0.04 is considered (`room_content_config.gd:6-15`, `room_content_assigner.gd:148-165`); see [`room-content.md`](room-content.md) |
| Catalog cache invalidation | PARTIAL | All three catalogs use "non-empty means loaded" (`npc_catalog.gd:25-26`, `merchant_catalog.gd:18-19`, `recipe_catalog.gd:33-34`), so a genuinely empty directory retries the whole walk on every call and there is no reload hook |
| Autosave per storage change | PARTIAL | `storage_service.gd:16` writes the full save document on every grid change, including intermediate states of a single drag |
| Blacksmith gold vs coins | PARTIAL | `can_afford` (gold) is paired with `spend_coins` (`blacksmith_service.gd:55` / `68`, `92` / `136`, `104` / `110`); the two are the same number today (`character_service.gd:78`) |

## Related
- Improvement plan: [`../actual_improvements/npc-hub-services.md`](../actual_improvements/npc-hub-services.md)
- [`hub.md`](hub.md), [`dialogue-quests.md`](dialogue-quests.md), [`inventory-service.md`](inventory-service.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`character-service.md`](character-service.md), [`progression-service.md`](progression-service.md), [`content-catalog.md`](content-catalog.md), [`content-data.md`](content-data.md), [`room-content.md`](room-content.md), [`ui/hub_vendors.md`](ui/hub_vendors.md), [`ui/inventory_ui.md`](ui/inventory_ui.md)
