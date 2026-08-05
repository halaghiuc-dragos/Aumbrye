# Hub vendors — improvement plan

## Current state
Three near-identical `ItemList` panels do reach their services correctly: buy, sell, upgrade, repair, respec, and transfer all work. Everything around the transaction is missing. Rows are plain text with no icons — no item in the repository has icon data at all. The merchant calls the wallet "Gold" and the blacksmith calls the same wallet "Coins". Selecting a merchant row writes the literal `"Select Buy or Sell"` instead of item information. Nothing is compared against equipped gear, nothing is confirmed before a sale, and every operation moves exactly one slot. See [`../existing_codebase/ui/hub_vendors.md`](../existing_codebase/ui/hub_vendors.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| VND-01 | P0 | No item icons anywhere. Every vendor row is a formatted string, and no item definition carries icon data: 0 `iconPath` or `"icon"` matches across `content/` for 89 item files. | 0 matches in `content/`; `merchant_ui.gd:77`, `:87`; `blacksmith_ui.gd:80`; `storage_ui.gd:68`, `:77` |
| VND-02 | P0 | The same wallet is labelled two different ways: `"Gold: n"` at the merchant, `"Coins: n"` at the blacksmith, while `coins` is a mirror of `gold`. | `merchant_ui.gd:70`; `blacksmith_ui.gd:65`; `character_service.gd:62-92` |
| VND-03 | P0 | Selling has no safety at all: the sell list is every inventory slot, with no confirmation and no protection for equipped, quest, or high-rarity items. | `merchant_ui.gd:82-88`, `:105-116` |
| VND-04 | P1 | The merchant detail line is a stub: selecting any row writes `"Select Buy or Sell"`, so the player never sees what an item does before buying it. | `merchant_ui.gd:30-31` |
| VND-05 | P1 | No comparison against equipped gear and no rarity color; the blacksmith prints the rarity as a word inside a formatted row. | `blacksmith_ui.gd:79-80` |
| VND-06 | P1 | Reaching the action buttons from a focused `ItemList` is not established: no focus neighbors exist in any of the three scenes, and directional input inside a list moves the selection. | no `focus_neighbor_*` in `merchant_ui.tscn`, `blacksmith_ui.tscn`, `storage_ui.tscn` |
| VND-07 | P1 | All three capture the mouse on close, including the dungeon merchant instance and cases where another menu is still open. | `merchant_ui.gd:57`; `blacksmith_ui.gd:52`; `storage_ui.gd:47` |
| VND-08 | P1 | No quantity handling: buy, sell, and transfer always move one slot, so stacks must be moved one press at a time. | `merchant_ui.gd:91-116`; `storage_ui.gd:81-102` |
| VND-09 | P1 | Zero localization across three scripts and three scenes, including row format strings and raw service error keys. | `merchant_ui.tscn:41-73`; `blacksmith_ui.tscn:41-69`; `storage_ui.tscn:41-90`; `merchant_ui.gd:101`, `:115` |
| VND-10 | P2 | Storage shows no capacity; a full stash is discovered only by a failed move. | `storage_ui.gd:59-78`, `:86-89` |
| VND-11 | P2 | Panels use fixed pixel offsets rather than the clamped panel helper, so they do not adapt to small windows or UI scale. | `merchant_ui.tscn:22-25`; `blacksmith_ui.tscn:22-25`; `storage_ui.tscn:22-25` |
| VND-12 | P2 | The respec button is created in code and appended to an authored row, so it is invisible in the scene and styled differently. | `blacksmith_ui.gd:27-30` |
| VND-13 | P2 | `apply_modal_menu` is called with a `"Backdrop"` node name that no scene defines, so the dimmer branch never runs. | `merchant_ui.gd:26`; `game_ui_skin.gd:185-189` |
| VND-14 | P2 | One anonymous merchant panel serves both the hub and dungeon merchants: same title, no name, portrait, or greeting. | `merchant_ui.gd:19`, `:49-51`; `room_merchant_content.gd:52-53` |
| VND-15 | P2 | No transaction audio; `wire_button_sfx` is never applied to these scene buttons. | `merchant_ui.gd:27-29`; `blacksmith_ui.gd:25-31`; `storage_ui.gd:25-27` |
| VND-16 | P2 | The blacksmith scene ships `"Gold: 0"` and the script rewrites it to `"Coins: …"`, so the wrong currency name is visible for one frame. | `blacksmith_ui.tscn:44-46`; `blacksmith_ui.gd:65` |

## Target design

### One shared vendor shell
All three panels become instances of `scenes/ui/vendor_shell.tscn` with a pluggable body, so the identical `_ready`/`open`/`close`/`_unhandled_input` code in three files collapses into one:

```
VendorShell (MenuModal — see menu_shell.md)
└── PanelContainer "Panel"              VendorPanel variation, clamped half size
    └── MarginContainer → VBoxContainer "ContentVBox"
        ├── HBoxContainer "HeaderRow"
        │   ├── TextureRect "VendorPortrait"     96 × 96
        │   ├── VBoxContainer
        │   │   ├── Label "VendorName"           VendorName variation
        │   │   └── Label "VendorGreeting"       VendorGreeting, autowrap
        │   └── HBoxContainer "WalletRow"
        │       ├── TextureRect "CurrencyIcon"   ui_symbols cell "currency_gold"
        │       └── Label "WalletValue"          MenuValue
        ├── Control "Body"                        vendor-specific
        └── HBoxContainer "FooterRow"             actions + hint captions with live glyphs
```

`VendorPortrait`, `VendorName`, and `VendorGreeting` come from `content/vendors/<id>.json` (`nameKey`, `greetingKey`, `portraitPath`, `stockTable`), which gives the hub and dungeon merchants distinct identities (VND-14).

The wallet row is built once from a single `CurrencyFormat.wallet_text()` helper, so no panel can invent its own currency name. `CharacterService.coins` and the `add_coins`/`spend_coins`/`can_afford_coins` aliases are deleted and their callers point at the gold API; the player-facing word is chosen once in `strings.csv` under `CURRENCY_GOLD` (VND-02, VND-16).

### Item rows with real icons
Every list becomes a `VBoxContainer` of `item_row.tscn` instances, sharing the cell composition specified in [`inventory_ui.md`](inventory_ui.md):

```
ItemRow (Button, focus_mode FOCUS_ALL, toggle_mode)
├── PanelContainer "Frame"          rarity-tinted 9-slice from ui_frames atlas
│   └── TextureRect "Icon"          32 × 32 AtlasTexture from item_icons.png
├── VBoxContainer "Text"
│   ├── Label "NameLabel"           rarity-colored
│   └── Label "SubLabel"            type, upgrade level, durability, or stack count
└── HBoxContainer "PriceBox"
    ├── TextureRect "CurrencyIcon"
    └── Label "PriceLabel"          affordable / unaffordable theme color
```

Item icon atlas: `assets/ui/atlas/item_icons.png`, `16 × 16` grid of `32 × 32` cells (`512 × 512`), cell ids named `item_<snake_case_id>`; every file in `content/items/**` gains `"iconPath": "item_icons:<cell>"`, and a content validation test fails on any item without one. This closes VND-01 for vendors, inventory, waves rewards, and loot toasts simultaneously.

Rejected alternative: keeping text rows and adding a rarity color prefix. It leaves the game with no item art at all, which is the single most visible placeholder in the UI.

### Detail and comparison panel
The merchant and blacksmith bodies gain a right-hand `ItemDetailPanel` (shared with the inventory tooltip):

```
ItemDetailPanel (PanelContainer)
├── Label "Name" + Label "TypeRarity"
├── GridContainer "Stats"        stat │ value │ delta vs equipped (green/red)
├── Label "Effects"              consumable effect or affix text
├── Label "FlavorText"
└── HBoxContainer "PriceRow"     price, and "you can afford n" when relevant
```

It updates on selection change, replacing the `"Select Buy or Sell"` stub, and the delta column is computed against the currently equipped item in the same slot (VND-04, VND-05).

### Sell safety and quantity
- The sell list excludes equipped items, quest items, and anything flagged `noSell`; those appear greyed with a reason tooltip rather than vanishing.
- Selling rarity `rare` or above, or any item with an upgrade level above `0`, requires `MenuStack.confirm` with a destructive spec.
- A `QuantityStepper` (`-` / value / `+`, plus `Shift` = 5, `Ctrl` = all) sits in the footer for buy, sell, and both transfer directions, and the price label multiplies live (VND-03, VND-08).

### Focus and input
- `initial_focus` is the first row of the primary list.
- Rows are focusable buttons in a `VBoxContainer`, so `ui_up`/`ui_down` move focus, and `focus_neighbor_bottom` from the last row is the primary action button — the ambiguity of directional input inside an `ItemList` disappears with the `ItemList` (VND-06).
- Storage: `ui_left`/`ui_right` switch columns; the transfer action is bound to `ui_accept` on a focused row, with the opposite direction on `interact`.
- Bumper actions `ui_page_prev`/`ui_page_next` switch vendor tabs where a vendor has more than one list (merchant Buy/Sell becomes two tabs instead of two stacked lists).
- `MenuStack` owns `ui_cancel` and mouse mode, so no vendor script writes `Input.mouse_mode` (VND-07).

### Capacity, sizing, and audio
- Both storage columns show `used / total` in their header, and rows show a full-stash warning before a move is attempted (VND-10).
- Panels use `GameUISkin.clamped_panel_half_size` through the shell, so they adapt to window size and UI scale (VND-11).
- The respec action becomes an authored button in `blacksmith_body.tscn` with the cost from `BlacksmithService.RESPEC_COST` (VND-12).
- The dimmer is part of the shell, so the `"Backdrop"` lookup mismatch disappears (VND-13).
- `AudioDirector` cues: `vendor_buy`, `vendor_sell`, `vendor_upgrade_success`, `vendor_repair`, `vendor_denied`, `storage_move` (VND-15).

### Localization
Row text is composed from localized templates, not concatenated in code: `VENDOR_ROW_PRICE` (`"{price}"` with the currency icon adjacent), `VENDOR_ROW_STOCK_LEFT`, `SMITH_ROW_LEVEL`, `SMITH_ROW_DURABILITY`, `STORAGE_ROW_STACK`, plus `VENDOR_TITLE_*`, `VENDOR_ACTION_*`, `VENDOR_ERR_*` mapped from service error keys through one `ErrorText.resolve(key)` helper (VND-09).

## Work plan
1. **Author `item_icons.png` and add `iconPath` to all 89 item files**, with a content test that fails on a missing icon (VND-01).
2. **Build `vendor_shell.tscn` + `vendor_shell.gd`** on `MenuModal`, with header, wallet, body slot, footer (VND-11, VND-13).
3. **Build `item_row.tscn` and `ItemDetailPanel`**, shared with the inventory (VND-01, VND-04, VND-05).
4. **Vendor content files** with name, greeting, portrait, stock table (VND-14).
5. **Currency unification** — delete the `coins` mirror and the three alias methods, route all display through `CurrencyFormat` (VND-02, VND-16).
6. **Port the three bodies** onto the shell: merchant tabs, blacksmith list + actions, storage two-column transfer (VND-06, VND-12).
7. **Sell protection and confirmations; quantity stepper** (VND-03, VND-08).
8. **Capacity readouts** (VND-10).
9. **Localization and error mapping; audio cues** (VND-09, VND-15).

## Data and schema changes
- `content/items/**/*.json`: mandatory `iconPath`; new optional `noSell`, `flavorKey`.
- New `content/vendors/hub_merchant.json`, `content/vendors/dungeon_merchant.json`, `content/vendors/hub_blacksmith.json`, `content/vendors/hub_storage.json`.
- New `assets/ui/atlas/item_icons.png` (`16 × 16` grid, `32 × 32` cells) and `assets/ui/atlas/ui_symbols.png` cell `currency_gold`.
- New `scenes/ui/vendor_shell.tscn`, `scenes/ui/item_row.tscn`, `scenes/ui/item_detail_panel.tscn`, `scenes/ui/merchant_body.tscn`, `scenes/ui/blacksmith_body.tscn`, `scenes/ui/storage_body.tscn`.
- `CharacterService`: `coins`, `get_coins`, `add_coins`, `spend_coins`, `can_afford_coins` removed; `coins_changed` removed after callers migrate.
- `StorageService`: expose `capacity()` and `used()`.
- `strings.csv`: the `VENDOR_*`, `SMITH_*`, `STORAGE_*`, `CURRENCY_*` keys above.

## Acceptance criteria
- [ ] Every vendor row shows an item icon from `item_icons.png`; no row is icon-less.
- [ ] Every item file has an `iconPath` that resolves to a real atlas cell.
- [ ] All three panels show the same currency name and icon, and `coins` no longer exists in `CharacterService`.
- [ ] Selecting a merchant row shows the item's stats, effects, price, and delta against equipped gear.
- [ ] Equipped and quest items cannot be sold; selling a rare or upgraded item requires a confirmation.
- [ ] Buy, sell, and both transfer directions accept a quantity, and the displayed price multiplies with it.
- [ ] Every panel is fully operable on a gamepad, including moving from a row to the action buttons.
- [ ] No vendor script writes `Input.mouse_mode`.
- [ ] Storage shows used and total capacity per side and warns before a move that would fail.
- [ ] Panels shrink to fit a `1280 × 720` window at UI scale `1.5`.
- [ ] The blacksmith respec button exists in the scene file.
- [ ] The hub and dungeon merchants show different names, portraits, and greetings.
- [ ] Buying, selling, upgrading, repairing, and a denied action each play a distinct cue.
- [ ] Switching to a stub locale changes every visible string, including row text and error messages.

## Validation
Extend `apps/game/client/scripts/validation/suites/hub_m4_suite.gd` and add `vendor` cases:

| Test id | Assertion |
|---|---|
| `vendor.item_icons_present` | every file in `content/items/**` has `iconPath` and the cell exists in `item_icons.png` |
| `vendor.rows_have_icons` | every visible row in all three panels has a non-null `Icon.texture` |
| `vendor.currency_single_name` | `CharacterService` exposes no `coins` member, and both panels' wallet text resolves from `CURRENCY_GOLD` |
| `vendor.detail_on_select` | selecting a buy row populates name, stats, effects, and price, and the text is not `Select Buy or Sell` |
| `vendor.compare_delta` | with a weaker weapon equipped, the delta column shows a positive value for the better item |
| `vendor.sell_excludes_protected` | an equipped item and a quest item are non-sellable and show a reason |
| `vendor.sell_confirm_required` | selling a `rare` item opens a confirmation and does not change gold until confirmed |
| `vendor.quantity_stepper` | setting quantity `3` on a stack of `5` moves exactly `3` and charges `3 ×` the unit price |
| `vendor.focus_on_open` | focus owner is the first row of the primary list in each panel |
| `vendor.focus_reaches_actions` | BFS from the initial focus reaches every action button in each panel |
| `vendor.no_mouse_mode` | none of the three scripts contains `Input.mouse_mode` |
| `vendor.storage_capacity` | both column headers show `used/total` matching `StorageService` |
| `vendor.panel_clamped` | at a `1280 × 720` viewport the panel rect fits inside the window with margin |
| `vendor.respec_in_scene` | `blacksmith_body.tscn` contains the respec button and the script creates no buttons |
| `vendor.vendor_identity` | opening the hub and dungeon merchants yields different name, portrait, and greeting |
| `vendor.audio_cues` | buy, sell, upgrade, repair, and a denied action each emit their distinct cue |
| `vendor.localized` | every visible string in the three panels resolves from a `strings.csv` key |
| `vendor.error_mapping` | each `MerchantService`/`BlacksmithService`/`StorageService` error key maps to a `VENDOR_ERR_*` string |

## Related
- Existing behavior: [`../existing_codebase/ui/hub_vendors.md`](../existing_codebase/ui/hub_vendors.md)
- [`inventory_ui.md`](inventory_ui.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`dialogue_quests.md`](dialogue_quests.md) · [`talents.md`](talents.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md)
- [`../npc-hub-services.md`](../npc-hub-services.md) · [`../hub.md`](../hub.md) · [`../inventory-service.md`](../inventory-service.md) · [`../loot-and-equipment.md`](../loot-and-equipment.md) · [`../content-catalog.md`](../content-catalog.md) · [`../room-content.md`](../room-content.md)
