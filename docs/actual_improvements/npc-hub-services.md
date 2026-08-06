# NPC and hub services — improvement plan

## Current state
The four hub services and three catalogs are wired end to end and load real content. See [`../existing_codebase/npc-hub-services.md`](../existing_codebase/npc-hub-services.md). What they do with that content is the problem. Upgrading an item costs gold and changes nothing but a `"+N"` label, because no stat path reads `upgradeLevel` and no code reads the `statBonus` in the recipe files. Repair is unreachable, because nothing in the game ever reduces `durability`. The two `unlock` recipes are inert, because `RecipeCatalog` only ever queries `upgrade` and `repair`, and the flags they name are the same two flags `loadout_ui.gd` checks and nothing writes. Merchant stock resets every time the UI opens, is keyed by item id across all merchants, and is never saved. Selling a stack of ten potions pays for one. Moving an item to storage silently strips its rarity, affixes, upgrade level, and durability.

## Gaps
| ID | Sev | Gap | Status | Evidence |
|----|-----|-----|--------|----------|
| NPC-01 | P0 | Item upgrades have no mechanical effect | **FINISHED** | `equipment.gd:78-118` `upgrade_multiplier` / `slot_stats`; `recipe_catalog.gd:upgrade_stat_bonus`; `hub_m4_suite.gd` `blacksmith.upgrade_changes_stats` |
| NPC-02 | P0 | Selling a stack pays for one unit | **FINISHED** | `merchant_service.gd:99-121` `sell_item(inv_index, quantity)`; `hub_m4_suite.gd` `merchant.sell_pays_for_full_stack`, `merchant.sell_partial_stack` |
| NPC-03 | P0 | Storage transfers discard rolled item data | **FINISHED** | `grid_inventory.gd:add_slot`; `storage_service.gd:36-60`; `hub_m4_suite.gd` `storage.transfer_preserves_instance` |
| NPC-04 | P0 | Merchant stock resets every UI open | **FINISHED** | `merchant_ui.gd:46` no `reset_session`; save-backed `get_purchased`; `run_flow.gd` `restock_all`; `hub_m4_suite.gd` `merchant.stock_persists_across_ui_open`, `merchant.stock_restocks_on_run_end` |
| NPC-05 | P0 | Repair unreachable — no durability loss | **FINISHED** | `inventory_service.gd:117-131` `apply_death_durability_loss`; `run_flow.gd:on_player_died`; `equipment.gd` zero-durability guard; `hub_m4_suite.gd` `blacksmith.repair_is_reachable_after_death` |
| NPC-06 | P1 | `unlock` recipes never queried; loadout level gates dead | **FINISHED** | `recipe_catalog.gd:26-41`; `blacksmith_service.gd:79-130`; `loadout_ui.gd:79-80`; `hub_m4_suite.gd` `blacksmith.unlock_recipe_purchase`, `blacksmith.unlock_flag_grants_free_access` |
| NPC-07 | P1 | `_purchased` keyed by item id only | **FINISHED** | `merchant_service.gd:41-43` per-merchant `get_purchased(merchant_id)`; `hub_m4_suite.gd` `merchant.stock_is_per_merchant` |
| NPC-08 | P1 | Merchant stock not persisted | **FINISHED** | `local_save.gd:256-288` `merchants` section; `hub_m4_suite.gd` `merchant.stock_round_trips_through_save` |
| NPC-09 | P1 | Sell price ignores rarity/affixes/upgrade | **FINISHED** | `merchant_service.gd:24-38` `get_slot_unit_sell_price`; `rarity_registry.gd:75-79`; `hub_m4_suite.gd` `merchant.sell_price_respects_rarity_and_upgrade` |
| NPC-10 | P1 | Aldric/Elara dialogue unreachable | **FINISHED** | `npc_base.gd:51-72` greet-then-shop; `aldric_greeting.json` / `elara_greeting.json` `open_blacksmith` / `open_merchant`; `hub_m4_suite.gd` `npc.vendor_greets_then_shops` |
| NPC-11 | P2 | `buy_item` grants before debiting gold | **FINISHED** | `merchant_service.gd:77-96` gold-first with refund; `hub_m4_suite.gd` `merchant.buy_refunds_on_inventory_full` |
| NPC-12 | P2 | Storage transfers return bare `false` | **FINISHED** | `storage_service.gd:36-60` `{"ok","error"}`; `storage_ui.gd:86-103`; `hub_m4_suite.gd` `storage.transfer_reports_full` |
| NPC-13 | P2 | NPC `position` never read | **FINISHED** | `hub_diorama.gd:821-836`; `content/npcs/*.json` corrected to scene transforms; `hub_m4_suite.gd` `npc.position_from_content` |
| NPC-14 | P2 | Every storage change writes full save immediately | **FINISHED** | `storage_service.gd:14-16` `request_autosave(DEFERRED)` |
| NPC-15 | P2 | Catalogs lack explicit loaded flag / reload | **FINISHED** | `npc_catalog.gd`, `merchant_catalog.gd`, `recipe_catalog.gd` `_loaded` / `reload()` / `is_loaded()`; `hub_m4_suite.gd` `npc.catalog_reload` |
| NPC-16 | P2 | `save.recipes` never populated or read | **FINISHED** | `local_save.gd:238-252` `get_owned_recipes` / `add_owned_recipe`; `blacksmith_service.gd:unlock_item`; `hub_m4_suite.gd` `blacksmith.unlock_recipe_purchase` |

## Target design

### Upgrades that do something
`upgradeLevel` becomes a real stat multiplier applied in the same aggregation pass that already handles affixes, so every consumer of equipment stats gets it for free:

```gdscript
## equipment.gd — new
const UPGRADE_STEP := 0.06   ## +6 percent of base per level, multiplicative on the item only

static func upgrade_multiplier(upgrade_level: int) -> float:
    return 1.0 + UPGRADE_STEP * float(maxi(0, upgrade_level))

static func slot_stats(slot: Dictionary) -> Dictionary
    ## base def stats * upgrade_multiplier, then affix values added flat
```

`InventoryService.aggregate_equipment_stats` calls `Equipment.slot_stats(slot)` instead of reading the definition directly, so the upgrade scales the item's own numbers and nothing else. See [`inventory-service.md`](inventory-service.md) and [`loot-and-equipment.md`](loot-and-equipment.md) for the aggregation contract.

Recipe `statBonus` is kept and becomes authoritative when present, overriding the flat percentage for hand-tuned items:

```gdscript
## RecipeCatalog
static func get_upgrade_recipe(item_id: String, from_level: int) -> Dictionary
static func upgrade_stat_bonus(item_id: String, to_level: int) -> Dictionary
    ## accumulated statBonus of every upgrade recipe with toLevel <= to_level
```

Chosen over a pure percentage: `castle_sword_upgrade.json` already declares `{"damage": 5}` and `{"damage": 8}`, which is the design intent for the starter weapon. A flat percentage covers every item that has no recipe, so upgrading is never a no-op.

### Durability becomes real, or repair goes away
Repair cannot be fixed in isolation: it is unreachable because durability loss does not exist. Two coherent options:

- Implement durability loss and keep repair. Costs a new per-hit hook, a warning UI, and a balance pass; adds an attrition tax that a roguelike hub loop does not obviously need.
- Remove durability and repair entirely, and delete `castle_sword_repair.json` and `maxDurability` from the item schema.

Chosen: implement it, narrowly. The item schema, the blacksmith UI, and five item files already declare `maxDurability`, and the vendor has a repair button; the honest options are a working feature or a removed one, and removing it deletes declared content. The narrow version loses durability only on player death, not per hit:

```gdscript
## RunFlow.on_player_died, before the results screen
InventoryService.apply_death_durability_loss(DEATH_DURABILITY_LOSS)   ## 15 per equipped item
```

Death is already the event that costs the player something, it is once per run rather than once per swing, and it makes the blacksmith a real part of the death loop instead of a button that is always greyed out. `can_repair` then becomes reachable without a per-frame cost, and an item at 0 durability contributes no stats rather than breaking permanently, so there is no way to lose an item to attrition.

### Unlock recipes, and the two dead flags
`RecipeCatalog` gains the third type, and the blacksmith gains the purchase path the content already describes:

```gdscript
## RecipeCatalog
static func get_unlock_recipes() -> Array[Dictionary]
static func get_unlock_recipe(item_id: String) -> Dictionary

## BlacksmithService
static func get_available_unlocks() -> Array[Dictionary]   ## rows with {itemId, goldCost, requiredLevel, owned}
static func can_unlock(item_id: String) -> bool
static func unlock_item(item_id: String) -> Dictionary     ## {"ok", "error"}
```

`unlock_item` charges `goldCost`, requires `ProgressionService.level >= requiredLevel`, appends the recipe id to the `recipes` save array, and grants the item into the inventory. That gives `save.recipes` its first real use and closes NPC-16.

`unlockFlag` is repurposed rather than deleted: it names the flag that grants the same unlock *for free*. `loadout_ui._is_weapon_unlocked` becomes:

```gdscript
"guard_spear", "hunter_bow":
    return BlacksmithService.is_unlocked(item_id)

## BlacksmithService.is_unlocked
static func is_unlocked(item_id: String) -> bool:
    var recipe := RecipeCatalog.get_unlock_recipe(item_id)
    if recipe.is_empty():
        return ItemCatalog.has_item(item_id)
    if str(recipe.get("id", "")) in LocalSave.get_owned_recipes():
        return true
    var flag_id := str(recipe.get("unlockFlag", ""))
    return flag_id != "" and CharacterService.is_flag_truthy(flag_id)
```

The raw `level >= 5` / `level >= 8` gates at `loadout_ui.gd:80-82` are removed, because they make the purchase and the flag both pointless. The flag itself gets its writer from [`character-service.md`](character-service.md): clearing the matching dungeon sets it. So there are two honest paths to each weapon — clear the dungeon, or pay the blacksmith — and neither is dead content.

### Merchant stock that means something
Stock becomes per-merchant, persisted, and refreshed on a stated schedule rather than on every UI open:

```gdscript
## MerchantService — session state replaced by save-backed state
static func get_purchased(merchant_id: String) -> Dictionary
static func restock(merchant_id: String) -> void          ## clears that merchant's counters
static func restock_all() -> void                        ## called once per completed run
static func get_available_stock(merchant_id: String = "hub_merchant") -> Array[Dictionary]
static func buy_item(item_id: String, merchant_id: String = "hub_merchant") -> Dictionary
```

`reset_session()` is deleted and the call at `merchant_ui.gd:41` is removed. Restocking happens on `RunFlow.run_ended`, which is the natural cadence: stock is a per-run resource, so a limited item is a real decision and returning from a run refreshes the shop.

Persistence adds a `merchants` save section keyed by merchant id:

```json
"merchants": {
  "hub_merchant": { "purchased": { "gold_ring": 1 }, "restockedAfterRuns": 3 }
}
```

Transaction order is corrected so money moves first:

```gdscript
if not CharacterService.spend_gold(price):
    return {"ok": false, "error": "not enough gold"}
if not InventoryService.add_item(item_id, 1):
    CharacterService.add_gold(price)          ## refund, no autosave in between
    return {"ok": false, "error": "inventory full"}
```

### Honest sell prices and stack handling
```gdscript
static func get_slot_sell_price(slot: Dictionary) -> int
    ## base = ItemCatalog.get_loot_value(itemId)
    ## * RarityRegistry.sell_multiplier(slot.rarity)
    ## * Equipment.upgrade_multiplier(slot.upgradeLevel)
    ## + affix value contribution
    ## then * quantity

static func sell_item(inv_index: int, quantity: int = -1) -> Dictionary
    ## quantity < 0 sells the whole slot; otherwise splits the stack
```

`RarityRegistry` gains `sell_multiplier(rarity)` alongside `max_upgrade_level`, using `tier_index` so a new tier does not need a second table. `sell_item` returns `{"ok", "gold", "quantity"}` so the UI can report what actually happened, and the merchant UI grows a quantity control for stacks; see [`ui/hub_vendors.md`](ui/hub_vendors.md).

### Storage that preserves items
Both transfer functions move the whole slot dictionary rather than two fields:

```gdscript
func move_to_storage(inv_index: int) -> Dictionary   ## {"ok", "error"}
func move_to_inventory(storage_index: int) -> Dictionary
func can_accept(slot: Dictionary) -> bool
```

Implementation moves the slot payload intact through `GridInventory.add_slot(slot)` — a new method that places an existing slot dictionary rather than re-deriving one from an item id — and only removes the source after the destination placement succeeds. Error strings: `invalid slot`, `storage full`, `inventory full`. This is the same fidelity problem described for the storage UI in [`ui/inventory_ui.md`](ui/inventory_ui.md); the fix belongs here so both callers get it.

### NPC dialogue for vendors
`interactType` stops being an either/or. A vendor NPC with a `dialogueId` greets first and opens the shop from a dialogue action, which is what the content already implies:

```gdscript
## npc_base.gd
func _on_interacted() -> void:
    var dialogue_id := str(_data.get("dialogueId", ""))
    if dialogue_id != "" and not _greeted_this_visit:
        _greeted_this_visit = true
        dialogue_requested.emit(npc_id, dialogue_id)
        return
    _emit_shop_for_type()
```

`aldric_greeting.json` and `elara_greeting.json` gain an `open_shop` dialogue action so the greeting flows into the vendor UI without a second interact; see [`dialogue-quests.md`](dialogue-quests.md) for the action table. `_greeted_this_visit` resets when the player leaves the interact zone, so the greeting is not a toll on every purchase.

### Content-driven NPC placement
`position` gets read. `HubDiorama` stops hardcoding the three NPC transforms and instead places every `hub_npc` from its definition, falling back to the scene transform when `position` is absent:

```gdscript
static func _position_npcs_from_content(hub: Node3D) -> void:
    for npc in hub.get_children():
        if not npc.is_in_group("hub_npc"):
            continue
        var def := NpcCatalog.get_definition(str(npc.get("npc_id")))
        var pos: Variant = def.get("position", null)
        if pos is Dictionary:
            (npc as Node3D).position = Vector3(
                float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0))
            )
```

The three content positions are then corrected to the values the diorama currently produces, so the visible layout does not change.

### Catalog lifecycle
All three catalogs get an explicit loaded flag and a reload hook, matching the pattern proposed in [`content-catalog.md`](content-catalog.md):

```gdscript
static var _loaded := false
static func reload() -> void
static func is_loaded() -> bool
```

## Work plan

1. **Add `Equipment.upgrade_multiplier` / `slot_stats` and route `InventoryService.aggregate_equipment_stats` through it; add `RecipeCatalog.upgrade_stat_bonus`** — `items/equipment.gd`, `inventory_service.gd:116-180`, `recipe_catalog.gd`. Closes NPC-01.
2. **Add `RarityRegistry.sell_multiplier`, `MerchantService.get_slot_sell_price`, and `sell_item(inv_index, quantity)`** — `rarity_registry.gd`, `merchant_service.gd:20-73`, merchant UI quantity control. Closes NPC-02, NPC-09.
3. **Add `GridInventory.add_slot(slot)`; rewrite both `StorageService` transfers to move whole slots and return `{"ok", "error"}`** — `grid_inventory.gd`, `storage_service.gd:27-49`, storage UI call sites. Closes NPC-03, NPC-12.
4. **Replace `_purchased` with save-backed per-merchant state; delete `reset_session` and its call; restock on `run_ended`; fix the buy order with a refund path** — `merchant_service.gd:6-57`, `merchant_ui.gd:41`, `run_flow.gd` run-ended path, `local_save.gd` new `merchants` section. Closes NPC-04, NPC-07, NPC-08, NPC-11.
5. **Add `InventoryService.apply_death_durability_loss` and call it from the death path; confirm a 0-durability item contributes no stats** — `inventory_service.gd`, `run_flow.gd:395-433`, `equipment.gd`. Closes NPC-05.
6. **Add `unlock` recipe support: `RecipeCatalog.get_unlock_recipes` / `get_unlock_recipe`, `BlacksmithService.get_available_unlocks` / `can_unlock` / `unlock_item` / `is_unlocked`, `LocalSave.get_owned_recipes` / `add_owned_recipe`; rewrite `loadout_ui._is_weapon_unlocked`** — `recipe_catalog.gd`, `blacksmith_service.gd`, `local_save.gd:585`, `loadout_ui.gd:72-84`, blacksmith UI tab. Closes NPC-06, NPC-16.
7. **Greet-then-shop in `NpcBase`; add the `open_shop` dialogue action to Aldric's and Elara's dialogue files** — `npc_base.gd:44-62`, `content/dialogue/aldric_greeting.json`, `elara_greeting.json`. Closes NPC-10.
8. **Place NPCs from content and correct the three `position` values** — `hub_diorama.gd:699-722`, `content/npcs/*.json`. Closes NPC-13.
9. **Throttle storage autosave** — `storage_service.gd:16` uses `LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)`. Depends on [`local-save.md`](local-save.md). Closes NPC-14.
10. **Add `_loaded` / `reload` / `is_loaded` to the three catalogs** — `npc_catalog.gd`, `merchant_catalog.gd`, `recipe_catalog.gd`. Closes NPC-15.

## Data and schema changes

**Save version bump: `save_migrator.gd` `CURRENT_VERSION` 4 -> 5** — the shared bump from [`save-migrator.md`](save-migrator.md). Sections owned by this topic:

```gdscript
## merchants: new section, empty is valid
if not copy.has("merchants"):
    copy["merchants"] = {}

## recipes: legacy value may be anything; normalise to an array of recipe id strings
var owned: Variant = copy.get("recipes", [])
var ids: Array[String] = []
if owned is Array:
    for entry in owned:
        if entry is String:
            ids.append(entry)
        elif entry is Dictionary and entry.has("id"):
            ids.append(str(entry["id"]))
copy["recipes"] = ids

## inventory slots: durability defaults are explicit from v5 so can_repair is meaningful
for slot in _slots_of(copy):
    if not slot.has("durability"):
        slot["durability"] = BlacksmithService.get_max_durability(str(slot.get("itemId", "")))
```

**Schema files to update:**

- `content/schemas/recipe-definition.v1.json`: add `unlock` to the `type` enum; declare `requiredLevel` (integer, minimum 1), `unlockFlag` (string, `^[a-z0-9_]+$`), `toLevel` (integer), and `statBonus` (object with keys from `ALLOWED_ITEM_STAT_KEYS` in `scripts/validate-content/validate.mjs`); require `fromLevel` and `toLevel` only for `type: "upgrade"` via `if/then`.
- `content/schemas/merchant-pack.v1.json`: add an optional `restockPolicy` enum `["per_run", "never"]` per file, defaulting to `per_run`, so a future permanent-stock vendor is expressible.
- `content/schemas/npc-definition.v1.json`: keep `position` but document it as authoritative now that it is read; add optional `shopId` so an NPC can point at a merchant other than `hub_merchant`.
- `content/schemas/character-state.v2.json`: add the `merchants` section and constrain `recipes` to an array of strings.
- `content/schemas/item-instance.v1.json`: `durability` becomes required alongside `upgradeLevel` for equipment slots.

**Failure and recovery behaviour:**

| Situation | Behaviour |
|-----------|-----------|
| `content/merchant/` missing | `MerchantCatalog` warns once (`merchant_catalog.gd:23`) and every merchant shows an empty stock list; buying returns `item not sold here` |
| A stock row names an item id absent from `ItemCatalog` | The row is dropped from `get_available_stock` with one warning per id per session, so the shop never lists an unbuyable item |
| `content/recipes/` missing | Upgrade cost falls back to `25 + level * 15`, repair to the durability formula, and the unlock tab is empty; no crash |
| An `unlock` recipe names a missing item | Excluded from `get_available_unlocks` with a warning; `is_unlocked` falls back to `ItemCatalog.has_item`, which is false, so the weapon stays hidden rather than appearing unbuyable |
| `save.merchants` contains an unknown merchant id | Retained on load (a future content file may restore it) and ignored by every query |
| `save.recipes` contains an unknown recipe id | Ignored for unlock checks, retained on save, reported once by the validation suite |
| Storage is full during `move_to_storage` | Returns `{"ok": false, "error": "storage full"}` and the source slot is untouched |
| An item reaches 0 durability | Contributes no stats, remains in the slot, is repairable; nothing is ever destroyed |
| `spend_gold` succeeds but `add_item` fails | Gold is refunded in the same call before any save is requested |

## Acceptance criteria
- [x] Upgrading `castle_sword` from +0 to +1 increases the player's damage stat by the recipe's `statBonus.damage`, and upgrading an item with no recipe increases its own stats by 6 percent per level. (NPC-01)
- [x] Selling a stack of ten `health_potion` pays ten times the unit price, and selling five leaves five in the slot. (NPC-02)
- [x] Moving a `legendary` sword with two affixes and `+3` to storage and back returns the identical slot, including `instanceId`. (NPC-03)
- [x] Buying the single `gold_ring`, closing the merchant UI, and reopening shows it out of stock; completing a run restocks it. (NPC-04)
- [x] Dying with equipped gear reduces its durability, the blacksmith offers a repair, and repairing restores full durability. (NPC-05)
- [x] The blacksmith lists `guard_spear` for 120 gold at level 5; buying it makes it equippable, and clearing the Forgotten Castle makes it equippable without paying. (NPC-06)
- [x] Buying a `health_potion` from the dungeon merchant does not change hub merchant stock. (NPC-07)
- [x] Merchant stock survives a quit and reload. (NPC-08)
- [x] An upgraded legendary sells for more than the same base item at `common` +0. (NPC-09)
- [x] Talking to Aldric plays `aldric_greeting` and the dialogue opens the blacksmith UI; the next interact in the same visit opens the shop directly. (NPC-10)
- [x] With a full inventory, buying returns `inventory full` and the player's gold is unchanged. (NPC-11)
- [x] Filling storage and attempting another transfer surfaces "storage full" in the UI. (NPC-12)
- [x] Editing `warden_mira.json`'s `position` moves her in game. (NPC-13)
- [x] Moving five items to storage produces one deferred save write. (NPC-14)
- [x] `NpcCatalog.reload()` picks up a newly added NPC file without a restart. (NPC-15)
- [x] `save.recipes` contains `unlock_guard_spear` after the purchase and is read back on load. (NPC-16)

## Validation
Extend `apps/game/client/scripts/validation/suites/hub_m4_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `merchant.stock_persists_across_ui_open` | Buy the last `gold_ring`, close and reopen the UI, `get_available_stock` omits it |
| `merchant.stock_is_per_merchant` | Buying `health_potion` from `dungeon_merchant` leaves `hub_merchant` remaining unchanged |
| `merchant.stock_restocks_on_run_end` | After `RunFlow.run_ended`, `_purchased` for every merchant is empty |
| `merchant.stock_round_trips_through_save` | `merchants.hub_merchant.purchased` survives `to_save_dict` / `from_save_dict` |
| `merchant.sell_pays_for_full_stack` | A slot with `quantity: 10` pays `10 * unit price` |
| `merchant.sell_partial_stack` | `sell_item(i, 4)` leaves `quantity: 6` and pays for 4 |
| `merchant.sell_price_respects_rarity_and_upgrade` | `legendary +3` sells above `common +0` of the same item |
| `merchant.buy_refunds_on_inventory_full` | Gold is unchanged and no item is granted |
| `merchant.unknown_stock_item_is_dropped` | A stock row naming a missing item id is absent from `get_available_stock` and warns once |
| `blacksmith.upgrade_changes_stats` | Aggregated damage rises after `upgrade_item`, by the recipe bonus where one exists |
| `blacksmith.upgrade_respects_rarity_cap` | An `aumbral` item stops at +10, others at +5 |
| `blacksmith.repair_is_reachable_after_death` | Death reduces durability, `can_repair` is true, `repair_item` restores the max |
| `blacksmith.zero_durability_contributes_no_stats` | A 0-durability equipped item adds nothing and is not destroyed |
| `blacksmith.unlock_recipe_purchase` | `unlock_item("guard_spear")` charges 120, appends the recipe id, and makes the weapon equippable |
| `blacksmith.unlock_requires_level` | Below `requiredLevel`, `can_unlock` is false and no gold moves |
| `blacksmith.unlock_flag_grants_free_access` | Setting `theme_forgotten_castle_cleared` makes `is_unlocked("guard_spear")` true with no purchase |
| `storage.transfer_preserves_instance` | A slot with `rarity`, `affixes`, `upgradeLevel`, `durability`, and `instanceId` round-trips both directions byte-identically |
| `storage.transfer_reports_full` | With storage full, `move_to_storage` returns `error == "storage full"` and the source slot is intact |
| `storage.dungeon_key_survives_transfer` | A `dungeon_key` slot keeps `keyId` and `lockId` through storage |
| `npc.vendor_greets_then_shops` | First interact emits `dialogue_requested`, second emits `shop_requested`, and leaving the zone resets it |
| `npc.position_from_content` | Overriding a content `position` moves the node after `HubDiorama.apply` |
| `npc.catalog_reload` | `reload()` after adding a definition exposes the new id |

Extend `apps/game/client/scripts/validation/suites/content_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `content.merchant.items_exist` | Every `items[].itemId` in `content/merchant/*.json` resolves in `ItemCatalog` |
| `content.merchant.prices_positive` | Every `price` and `stock` is a positive integer |
| `content.recipes.types_are_handled` | Every `type` in `content/recipes/*.json` is one of `upgrade`, `repair`, `unlock` and has a `RecipeCatalog` query |
| `content.recipes.items_exist` | Every recipe `itemId` resolves in `ItemCatalog` |
| `content.recipes.upgrade_levels_contiguous` | Per item, the `fromLevel` / `toLevel` chain starts at 0 and has no gaps |
| `content.recipes.stat_bonus_keys_allowed` | Every `statBonus` key is in `ALLOWED_ITEM_STAT_KEYS` |
| `content.recipes.unlock_flags_registered` | Every `unlockFlag` is in `CharacterFlags.REGISTRY` (see [`character-service.md`](character-service.md)) |
| `content.npcs.dialogue_ids_exist` | Every `dialogueId` resolves in `DialogueCatalog` |
| `content.npcs.interact_types_known` | Every `interactType` is handled by `NpcBase._on_interacted` |
| `content.npcs.shop_ids_exist` | Every `shopId`, when present, resolves in `MerchantCatalog` |

## Related
- Existing state: [`../existing_codebase/npc-hub-services.md`](../existing_codebase/npc-hub-services.md)
- [`hub.md`](hub.md), [`dialogue-quests.md`](dialogue-quests.md), [`inventory-service.md`](inventory-service.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`character-service.md`](character-service.md), [`progression-service.md`](progression-service.md), [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`content-catalog.md`](content-catalog.md), [`content-data.md`](content-data.md), [`run-flow.md`](run-flow.md), [`ui/hub_vendors.md`](ui/hub_vendors.md), [`ui/inventory_ui.md`](ui/inventory_ui.md)

## Status: FINISHED

All sixteen gaps (NPC-01 through NPC-16) are implemented and covered by `hub_m4_suite.gd` assertions. Save normalization for `merchants`, `recipes`, and default equipment `durability` lives in `save_migrator.gd:_normalize_merchants`, `_normalize_recipes`, and `_normalize_slot_entry` at `CURRENT_VERSION` 6.
