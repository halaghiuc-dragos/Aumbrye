# Hub vendors

Three modal panels in the hub: the merchant (buy/sell), the blacksmith (upgrade/repair/respec), and storage (transfer between inventory and stash). All three are `ItemList` panels with plain text rows.

## Files
| Script | Lines | Scene |
|---|---|---|
| `apps/game/client/scripts/ui/merchant_ui.gd` | 117 | `scenes/ui/merchant_ui.tscn` (74 lines) |
| `apps/game/client/scripts/ui/blacksmith_ui.gd` | 134 | `scenes/ui/blacksmith_ui.tscn` (70 lines) |
| `apps/game/client/scripts/ui/storage_ui.gd` | 103 | `scenes/ui/storage_ui.tscn` (91 lines) |

All three are instanced in `scenes/hub/hub.tscn:390`, `:398`, `:406` and opened from `hub.gd:179-188` when the player interacts with the matching NPC. The merchant scene is also instanced standalone into the scene root for dungeon merchant rooms (`room_merchant_content.gd:49-53`, with `merchant_id = "dungeon_merchant"`).

## Shared shape
Every one of the three does the same five things in `_ready`: hide, `PROCESS_MODE_ALWAYS`, `MOUSE_FILTER_IGNORE`, `GameUISkin.apply_modal_menu(self, "Panel", "Backdrop")`, then connect buttons and service signals (`merchant_ui.gd:22-33`, `blacksmith_ui.gd:20-34`, `storage_ui.gd:20-29`). None of the three scenes contains a `Backdrop` node; `apply_modal_menu` creates one through `ensure_backdrop` and the named lookup at `game_ui_skin.gd:187-189` finds nothing.

`open()` / `close()` are identical in shape, including `Input.mouse_mode = MOUSE_MODE_CAPTURED` on close (`merchant_ui.gd:54-58`, `blacksmith_ui.gd:49-53`, `storage_ui.gd:44-48`), and each handles `ui_cancel` in its own `_unhandled_input`.

## Merchant
```
MerchantUI (Control, full rect, mouse_filter 2)
└── PanelContainer "Panel"     (560 × 400 fixed offsets)
    └── MarginContainer "Margin" (12)
        └── VBoxContainer "VBox"
            ├── Label "Title"       "Merchant"
            ├── Label "GoldLabel"   "Gold: 0" → "Gold: %d"
            ├── ItemList "BuyList"    min height 100
            ├── ItemList "SellList"   min height 100
            ├── Label "DetailLabel"  "Buy or sell items"
            └── HBoxContainer "Buttons"  Buy │ Sell │ Close
```
| Concern | Behavior |
|---|---|
| Stock | `MerchantService.get_available_stock(_merchant_id)`, row text `"%s — %d g (%d left)"` (`:73-78`) |
| Sell rows | every inventory slot, row text `"%s — sell %d g"` (`:82-88`) |
| Prices | `MerchantService.get_buy_price` / `get_sell_price` (`:76`, `:86`) |
| Gold | `CharacterService.gold`, live via `gold_changed` (`:32`, `:70`) |
| Session | `MerchantService.reset_session()` on every open (`:41`) |

## Blacksmith
```
BlacksmithUI → Panel (480 × 400) → Margin → VBox
├── Label "Title"       "Blacksmith"
├── Label "GoldLabel"   scene text "Gold: 0", script writes "Coins: %d"
├── ItemList "ItemList"  min height 160
├── Label "DetailLabel"  "Select a weapon"
└── HBoxContainer "Buttons"  Upgrade │ Repair │ Close │ + "Respec Talents (n)" added in code at :27-30
```
Rows are filtered to `BlacksmithService.UPGRADEABLE_TYPES` and read `"%s %s +%d/%d (%d/%d)"` — rarity display name, item name, upgrade level, max level, durability, max durability (`:73-80`). The detail line shows the upgrade cost and the two buttons are disabled from `can_upgrade` / `can_repair` (`:91-103`). Respec calls `BlacksmithService.respec_talents()` (`:126-129`).

## Storage
```
StorageUI → Panel (600 × 400) → Margin → VBox
├── Label "Title"      "Storage"
├── HBoxContainer "Columns"
│   ├── VBoxContainer "InventoryColumn"  Label "Inventory" + ItemList "InvList" (200 × 160)
│   └── VBoxContainer "StorageColumn"    Label "Storage"   + ItemList "StorageList" (200 × 160)
├── Label "DetailLabel"  "Move items between inventory and storage"
└── HBoxContainer "Buttons"  To Storage │ To Inventory │ Close
```
Rows are `"%s x%d"` on both sides (`:68`, `:77`); transfers go through `StorageService.move_to_storage` / `move_to_inventory` and refresh on `storage_changed` and `inventory_changed` (`:28-29`, `:81-102`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Buy, sell, upgrade, repair, respec, transfer | IMPLEMENTED — all six operations reach their services and refresh | `merchant_ui.gd:91-116`; `blacksmith_ui.gd:106-129`; `storage_ui.gd:81-102` |
| Initial focus | IMPLEMENTED — each panel focuses its primary `ItemList` on open, the only menus in the UI tree that do | `merchant_ui.gd:46`; `blacksmith_ui.gd:46`; `storage_ui.gd:41` |
| Focus beyond the list | PARTIAL — no focus neighbors are declared, and while an `ItemList` has focus the directional actions move the selection, so reaching Buy/Sell/Close on a gamepad is not established anywhere | `merchant_ui.gd:9-15` (no `focus_neighbor_*` in any of the three scenes) |
| Item icons | ABSENT — every row is text. No item definition in the repository has an `iconPath` or `icon` field: 0 matches across all of `content/` (89 item JSON files) | 0 `iconPath` matches in `content/`; rows at `merchant_ui.gd:77`, `:87`, `blacksmith_ui.gd:80`, `storage_ui.gd:68`, `:77` |
| Currency naming | BROKEN — the merchant shows `"Gold: n"` and the blacksmith shows `"Coins: n"` for the same wallet: `CharacterService.coins` is assigned `coins = gold` on every change, and `add_coins`/`spend_coins` forward to the gold functions | `merchant_ui.gd:70`; `blacksmith_ui.gd:65`; `character_service.gd:62-92` |
| Blacksmith label default | PARTIAL — the scene ships `"Gold: 0"` and the script overwrites it with `"Coins: …"` on first refresh, so the panel briefly shows the other currency name | `blacksmith_ui.tscn:44-46`; `blacksmith_ui.gd:65` |
| Respec button | PARTIAL — created in code and appended to the scene's button row, so its position and styling differ from the authored buttons and it is not visible in the scene file | `blacksmith_ui.gd:27-30` |
| Panel sizing | PARTIAL — all three panels use fixed pixel offsets in the scene rather than `GameUISkin.clamped_panel_half_size`, so they are not clamped to small windows or UI scale | `merchant_ui.tscn:22-25`; `blacksmith_ui.tscn:22-25`; `storage_ui.tscn:22-25` |
| Backdrop node | PARTIAL — `apply_modal_menu` is called with `"Backdrop"`, no scene defines that node, and the dimmer branch at `game_ui_skin.gd:187-189` therefore never runs; the backdrop that does appear comes from `ensure_backdrop` | `merchant_ui.gd:26`; `blacksmith_ui.gd:24`; `storage_ui.gd:24`; `game_ui_skin.gd:185-189` |
| Mouse mode on close | BROKEN — all three capture the mouse unconditionally on close, including the dungeon merchant instance and any case where another menu is still open behind them | `merchant_ui.gd:57`; `blacksmith_ui.gd:52`; `storage_ui.gd:47` |
| Sell safety | ABSENT — no confirmation, no lock for equipped, quest, or high-rarity items; the sell list is every inventory slot | `merchant_ui.gd:82-88`, `:105-116` |
| Quantity handling | ABSENT — no buy/sell/transfer quantity selector; every action moves exactly one slot | `merchant_ui.gd:91-116`; `storage_ui.gd:81-102` |
| Item comparison | ABSENT — no stat block, no comparison against equipped gear, no rarity color; the blacksmith prints the rarity name as text | `blacksmith_ui.gd:79-80`; `merchant_ui.gd:30-31` sets the detail label to `"Select Buy or Sell"` on any selection |
| Merchant detail line | STUB — selecting a row in either list writes the literal `"Select Buy or Sell"`, so selection conveys nothing about the item | `merchant_ui.gd:30-31` |
| Storage capacity | ABSENT — no used/total counter on either column; failure is reported only after a rejected move | `storage_ui.gd:59-78`, `:86-89` |
| Error text | PARTIAL — service error keys are printed raw (`str(result.get("error", …))`) | `merchant_ui.gd:101`, `:115`; `blacksmith_ui.gd:112`, `:122` |
| Localization | ABSENT — every title, label, button, row format, and message is hardcoded English across the three scripts and three scenes | `merchant_ui.tscn:41-73`; `blacksmith_ui.tscn:41-69`; `storage_ui.tscn:41-90`; `merchant_ui.gd:70-115`; 0 `tr(` calls |
| Vendor identity | PARTIAL — one merchant panel serves `hub_merchant` and `dungeon_merchant` with the same title and no portrait, name, or greeting | `merchant_ui.gd:19`, `:49-51`; `room_merchant_content.gd:52-53` |
| Audio | ABSENT — no purchase, upgrade, or transfer sound; `wire_button_sfx` is never called for these scene buttons | `merchant_ui.gd:27-29`; `blacksmith_ui.gd:25-31`; `storage_ui.gd:25-27` |

## Related
- Improvement plan: [`../actual_improvements/ui/hub_vendors.md`](../actual_improvements/ui/hub_vendors.md)
- [`inventory_ui.md`](inventory_ui.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`dialogue_quests.md`](dialogue_quests.md) · [`talents.md`](talents.md)
- [`../npc-hub-services.md`](../npc-hub-services.md) · [`../hub.md`](../hub.md) · [`../inventory-service.md`](../inventory-service.md) · [`../loot-and-equipment.md`](../loot-and-equipment.md) · [`../content-catalog.md`](../content-catalog.md) · [`../room-content.md`](../room-content.md)
