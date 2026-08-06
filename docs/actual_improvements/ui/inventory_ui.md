# Inventory UI — improvement plan

## Current state
`inventory_ui.gd` uses `ItemIconAtlas` `TextureRect` cells (no Unicode glyphs). Item art resolves through `content/ui/item_icon_atlas.json` with optional per-item `iconPath` override in the schema. Filtering, consumable dispatch, and quick-slot stability remain open gaps — see table below. See [`../existing_codebase/ui/inventory_ui.md`](../existing_codebase/ui/inventory_ui.md).

**Quality bar (icons): FINISHED** — INV-01, INV-02 closed 2026-08-05.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| INV-01 | P0 | ~~Item identity is a Unicode character~~ **FINISHED** — `TextureRect` + `ItemIconAtlas` | was `inventory_ui.gd:787-817` |
| INV-02 | P0 | ~~No `iconPath` / atlas path~~ **FINISHED** — `item_icon_atlas.json`, schema `iconPath`, `item_icons.png` | was 0 `iconPath` in content |
| INV-03 | P0 | The type and rarity filters do nothing visible: `_rebuild_visible_indices` populates `_visible_indices`, `_refresh_grid` iterates `inv.slots` in full and ignores it. Pressing `lock_on` or `interact` only edits the label at `:478`. | `:393-399` (write) vs `:402-439` (read `inv.slots`); `_visible_indices` has no reader |
| INV-04 | P0 | Every consumable is a 30 HP heal. `mana_potion`, `stamina_potion`, `elixir_might`, `elixir_vigor`, and `skip_10/50/100/500_floors` all restore health and are destroyed, so the four Umbral Skip items — 500 gold each — are consumed for a heal. | `:630-641` `def.get("healAmount", 30.0)`; only `content/items/consumables/health_potion.json:9` defines `healAmount` |
| INV-05 | P0 | Quick-slot bindings are grid indices, and the sort button reorders `slots` in place and repacks, so `sprint` silently repoints all three quick slots. | `inventory_service.gd:224-233` stores `grid_index`; `grid_inventory.gd:208-227` sorts and repacks; `inventory_ui.gd:644-647` |
| INV-06 | P0 | No `grab_focus` anywhere in the file, and no cell sets `focus_mode`. The Equip / Unequip / Use / Bind buttons are mouse-only. Quick-slot binding matches raw `KEY_1`-`KEY_3` even though `quick_slot_1`-`quick_slot_3` actions already exist in `project.godot` — and those actions are themselves keyboard-only, with no joypad event. | 0 `grab_focus` and 0 `focus_mode` matches in `inventory_ui.gd`; `:969-987` is `InputEventKey`-only; `project.godot:256-270` defines the three actions with one `InputEventKey` each and no `InputEventJoypadButton` |
| INV-07 | P1 | `loadout_ui.gd:37-39` selects `ItemList` row 0 without focusing it, so arrow keys move nothing until the player clicks. | `loadout_ui.gd:37-39`; 0 `grab_focus` matches |
| INV-08 | P1 | Zero localization: every label, hint, and title is a hardcoded English literal in both files. | `inventory_ui.gd:478`, `:491-529`, `:834-842`; `loadout_ui.gd:67`; 0 `tr(` matches in either |
| INV-09 | P1 | The item "tooltip" is a fixed 560 × 88 footer `Label`; a legendary with four affixes overflows with no scroll and no indication. | `:169` `custom_minimum_size = Vector2(560, 88)`; `:884-901` can emit 8+ lines |
| INV-10 | P1 | No stack count is drawn even though consumables have `stackSize` up to 10, so a stack of 1 and a stack of 10 look identical. | `:359-364` draws only `+upgrade`; `content/items/consumables/stamina_potion.json:7` |
| INV-11 | P1 | `maxDurability` exists on equipment and is invisible in the UI. | `content/items/equipment/castle_sword.json:13`; 0 durability matches in `inventory_ui.gd` |
| INV-12 | P1 | No drop, destroy, or split-stack action; the only ways an item leaves the stash are equipping and consuming. | 0 matches for `discard`, `split` |
| INV-13 | P2 | `loadout_ui.gd` hardcodes five weapon ids and a level-5 / level-8 unlock `match` instead of reading `content/`. | `loadout_ui.gd:9-15`, `:76-84` |
| INV-14 | P2 | `_build_grid()` is a 2-line forwarder with no callers. | `:324-325` |
| INV-15 | P2 | `CompareLabel` hardcodes `Color(0.65, 0.9, 0.65)` instead of using a skin token, so it drifts from every other label. | `:191` |
| INV-16 | P2 | `hide_inventory` unconditionally forces `MOUSE_MODE_CAPTURED`, stealing the cursor when the inventory is closed while a vendor or the pause menu is still open. | `:302`; identical at `loadout_ui.gd:45` |
| INV-17 | P2 | No search field; filtering is cycle-only across 6 types × 7 rarities. | `grid_inventory.gd:11-12`; no `LineEdit` in `inventory_ui.gd` |

## Target design

### Authored item icon atlas
Items get real art through the shared symbol contract in [`status_icons_glyphs.md`](status_icons_glyphs.md).

- `assets/ui/item_icons.png` — 256×256, a 16×16 grid of 16 px cells, one cell per item id, `filter=false`, `mipmaps=false`, lossless.
- `content/ui/item_icon_atlas.json` — conforms to `content/schemas/ui-symbol-atlas.v1.json`; keys are item ids, plus `slot/<slot_name>` keys for the nine empty paper-doll cells.
- Multi-cell items draw their icon stretched across their `gridWidth` × `gridHeight` footprint using `STRETCH_KEEP_ASPECT_CENTERED` on the origin cell spanning the full rect, not one icon per covered cell.

`content/schemas/item-instance.v1.json` gains `"iconPath": {"type": "string"}` as an explicit per-item override; the atlas key remains the default lookup so no item file needs editing to get art (INV-01, INV-02).

### Cell composition
Replace `_make_item_cell`'s three-label `VBox` with:

```
ItemCell (PanelContainer, focus_mode = FOCUS_ALL, custom_minimum_size = 64 × 64)
├── TextureRect "Icon"   (full rect, NEAREST, MOUSE_FILTER_IGNORE)
├── Label "Stack"        (bottom-right, font 10, shown when quantity > 1)
├── Label "Upgrade"      (top-right, font 10, shown when upgrade > 0)
└── TextureProgressBar "Durability" (bottom edge, 2 px, shown when durability < max)
```

The name is removed from the cell entirely — identity comes from the icon, and the full name lives in the hover tooltip. This deletes `_item_abbrev`, `_item_glyph`, and `_slot_glyph_for_label` (INV-01, INV-10, INV-11).

Cell rarity framing keeps `GameUISkin.make_item_cell_style(rarity, filled)` so the frame color stays the single rarity source.

### Real filtering
`_refresh_grid` iterates `_visible_indices` instead of `inv.slots`. Slots filtered out are drawn at 35 % alpha rather than hidden, so grid geometry stays stable and the player can still see where things are; a `Sort`/`Type`/`Rarity` chip row replaces the concatenated label at `:478`. Add a `LineEdit` "Search" above the grid whose text is matched case-insensitively against the localized display name and folded into `_rebuild_visible_indices` (INV-03, INV-17).

### Consumable effects
Consumables stop being a heal call site. Add to `content/schemas/item-instance.v1.json`:

```json
"consumableEffect": {
  "type": "object",
  "required": ["kind"],
  "properties": {
    "kind": { "enum": ["heal", "restoreStamina", "restoreMana", "applyStatus", "skipFloors", "cure"] },
    "amount": { "type": "number" },
    "statusId": { "type": "string" },
    "duration": { "type": "number" },
    "floors": { "type": "integer" },
    "usableInRun": { "type": "boolean", "default": true },
    "usableInHub": { "type": "boolean", "default": true }
  }
}
```

`_use_selected_consumable` dispatches on `kind` through a new `ConsumableService.apply(def, player) -> bool` so `inventory_ui.gd`, `combat_hud.gd` quick slots, and `inventory_service.gd:283` share one implementation. `skip_*_floors` items set `kind: "skipFloors"` with `usableInRun: false`, and the Use button is disabled with the reason shown in the hint label when a consumable is not usable in the current context (INV-04).

Rejected alternative: keeping `healAmount` and adding `manaAmount`/`staminaAmount` siblings. That keeps the "unknown key means 30 HP" failure mode; a required `kind` makes a missing effect a schema error instead.

### Stable quick slots
`InventoryService.quick_slot_indices` becomes `quick_slot_instances: Array[String]` holding `instanceId`. `get_quick_slot_index` resolves an id to the current index on demand and returns `-1` when the item is gone. `set_quick_slot` takes an `instanceId`. `save_migrator.gd` converts the old `quickSlots` index array by resolving each index against the loaded grid once at migration time (INV-05).

### Focus and gamepad
- Every `ItemCell` and every equip cell sets `focus_mode = FOCUS_ALL`; grid navigation is expressed with `focus_neighbor_*` so Godot's own focus system moves the cursor, and the custom `_navigate` becomes a thin wrapper that only handles the grid-to-paper-doll crossing.
- `show_inventory` ends with `_cells[_cursor_index()].grab_focus()`.
- The action row is reachable by pressing `ui_down` from the bottom grid row; `focus_neighbor_bottom` on the last row points at `_btn_equip`.
- Quick-slot binding moves off raw keycodes onto the `quick_slot_1`, `quick_slot_2`, `quick_slot_3` actions that already exist at `project.godot:256-270`, and each of those three gains a joypad event (D-pad left / up / right) so the binding is reachable on a pad at all.
- The focus-visible ring is the shared token from [`menu_shell_a11y.md`](menu_shell_a11y.md), not `self_modulate` multiplication (INV-06, INV-07).

`loadout_ui.gd:37-39` adds `_list.grab_focus()` after `select(0)`.

### Tooltip panel
Replace the fixed footer `Label` with a floating `TooltipPanel` (`PanelContainer` + `VBoxContainer` inside a `ScrollContainer`, max height 320) anchored to the hovered or focused cell, flipping side when it would leave the panel. It shows the localized name colored by rarity, the item type and slot, base stats, affixes, durability, stack size, value, and the compare block. `_format_slot_tooltip` becomes its builder (INV-09).

### Localization
Every literal moves to `apps/game/client/translations/strings.csv` with keys `INV_TITLE_STASH`, `INV_TITLE_WAVES_STASH`, `INV_SORT`, `INV_TYPE`, `INV_RARITY`, `INV_EMPTY_SLOT`, `INV_HINT_EQUIP`, `INV_HINT_USE`, `INV_HINT_MOVE`, `INV_HINT_UNEQUIP`, `INV_SELECT_PROMPT`, `INV_BTN_EQUIP`, `INV_BTN_UNEQUIP`, `INV_BTN_USE`, `INV_BTN_BIND`, `INV_VS_EQUIPPED`, `INV_SEARCH_PLACEHOLDER`, `LOADOUT_TITLE`, `LOADOUT_EQUIPPED_PREFIX`, `LOADOUT_BTN_EQUIP`, `LOADOUT_BTN_CLOSE`, plus `SLOT_HELMET` … `SLOT_RELIC` for the nine paper-doll labels and `ITEM_NAME_*` / `ITEM_DESC_*` per item id (INV-08).

### Drop and split
Add a `Drop` button and a `ui_page_down`-bound split action. Dropping spawns the existing world pickup at the player position when in a run and returns the item to the vendor-sell flow in the hub; splitting halves a stack into the first free rect (INV-12).

### Loadout data
`WEAPON_ITEMS` and `_is_weapon_unlocked` are replaced by a query over `ItemCatalog` for `itemType == "weapon"` filtered through `ClassCatalog.is_weapon_allowed`, with unlock requirements moved into each item's JSON as `"unlock": {"level": int, "flag": string}` (INV-13).

## Work plan
1. **Filter correctness** — `_refresh_grid` iterates `_visible_indices`; dim non-matching slots (INV-03).
2. **Consumable schema and service** — add `consumableEffect`, add `ConsumableService.apply`, repoint `inventory_ui.gd:640` and `inventory_service.gd:283`, mark `skip_*` items `usableInRun: false` (INV-04).
3. **Quick slots by instance id** — change `InventoryService`, add the migrator step (INV-05).
4. **Icon atlas** — author `item_icons.png` + `item_icon_atlas.json`, add `iconPath` to the schema, rewrite `_make_item_cell` / `_set_cell_content` on `TextureRect`, delete `_item_abbrev`, `_item_glyph`, `_slot_glyph_for_label`, delete dead `_build_grid` (INV-01, INV-02, INV-14).
5. **Cell decorations** — stack count, upgrade badge, durability strip (INV-10, INV-11).
6. **Focus model** — `focus_mode` on cells, `focus_neighbor_*` wiring, `grab_focus` on open, new `quick_slot_*` actions, shared focus ring; `loadout_ui.gd` focus fix (INV-06, INV-07).
7. **Tooltip panel** — floating scrollable tooltip replacing the footer label; retire the hardcoded compare color for a skin token (INV-09, INV-15).
8. **Localization** — move all literals to `strings.csv` and wrap in `tr()` (INV-08).
9. **Drop and split** (INV-12), **loadout from content** (INV-13), **mouse-mode ownership** via `MenuStack` from [`menu_shell_a11y.md`](menu_shell_a11y.md) (INV-16), **search field** (INV-17).

Steps 1-3 are behavior fixes with no art dependency and should land first.

## Data and schema changes
- `content/schemas/item-instance.v1.json`: add `iconPath` and `consumableEffect`; add `unlock` for weapons.
- `content/items/consumables/*.json`: all 9 files gain `consumableEffect`; `healAmount` is retired after the migration window.
- New: `content/ui/item_icon_atlas.json`, `assets/ui/item_icons.png` (256×256, 16 px cells).
- `apps/game/client/project.godot`: add an `InputEventJoypadButton` to each of the existing `quick_slot_1`, `quick_slot_2`, `quick_slot_3` actions at `:256-270`.
- `apps/game/client/translations/strings.csv`: the key list above.
- `save_migrator.gd`: one new step converting `quickSlots` indices to `instanceId` strings; bump the save version.

## Acceptance criteria
- [x] No item cell contains a `Label` whose text is a non-ASCII code point; `inventory_ui.gd` contains no non-ASCII literal.
- [x] `inventory_ui.gd` contains no `_item_abbrev`, `_item_glyph`, or `_slot_glyph_for_label`.
- [x] Every id in `content/items/catalog.json` resolves to an item-atlas cell, or to an explicit `iconPath`.
- [ ] Setting the type filter to `weapon` dims every non-weapon slot and leaves weapons at full alpha.
- [ ] Typing `cro` in the search field leaves only `Castle Crown` and `Mythic Crown` at full alpha.
- [ ] Using `mana_potion` restores mana and not health; using `skip_10_floors` in a run is refused with a reason in the hint label and does not consume the item.
- [ ] Binding an item to quick slot 1, then pressing `sprint` to sort, leaves quick slot 1 pointing at the same `instanceId`.
- [ ] Loading a pre-migration save with `quickSlots: [3, -1, 0]` produces the instance ids that were at indices 3 and 0.
- [ ] Opening the inventory leaves `get_viewport().gui_get_focus_owner()` non-null and inside the stash grid.
- [ ] `ui_down` from the bottom grid row focuses the Equip button; `ui_up` returns to the grid.
- [ ] Pressing the gamepad event bound to `quick_slot_1` while a stash item is focused binds quick slot 1.
- [ ] `inventory_ui.gd` contains no `KEY_1`, `KEY_2`, or `KEY_3` literal.
- [ ] Opening the loadout modal leaves `WeaponList` focused and arrow keys change the selection.
- [ ] A legendary with four affixes shows a scrollable tooltip with no clipped line.
- [ ] A stack of 7 potions shows `7`; an item at 40/100 durability shows a partial durability strip.
- [ ] Switching the locale to a stub translation changes every visible inventory and loadout string.
- [ ] Closing the inventory while a vendor panel is open leaves the mouse visible.

## Validation
Extend `apps/game/client/scripts/validation/suites/content_suite.gd` and add `apps/game/client/scripts/validation/suites/inventory_ui_suite.gd`, category `inventory_ui`:

| Test id | Assertion |
|---|---|
| `inventory_ui.no_unicode` | `inventory_ui.gd` and `inventory_ui_layout.gd` match no non-ASCII code point |
| `inventory_ui.icon_coverage` | every id in `content/items/catalog.json` resolves through `UISymbolAtlas` or has `iconPath` |
| `inventory_ui.cell_uses_texture` | a filled cell contains a `TextureRect` with a non-null `texture` and no name `Label` |
| `inventory_ui.filter_applies` | with type filter `weapon`, every non-weapon cell modulate alpha is `0.35` and weapons are `1.0` |
| `inventory_ui.search_applies` | search `cro` yields exactly the two crown items at full alpha |
| `inventory_ui.consumable_schema` | every file in `content/items/consumables/` has `consumableEffect.kind` and none has `healAmount` |
| `inventory_ui.consumable_dispatch` | `mana_potion` raises mana and leaves health unchanged; `stamina_potion` raises stamina |
| `inventory_ui.skip_item_guarded` | using `skip_10_floors` during a run returns `false` and leaves the stack size unchanged |
| `inventory_ui.quick_slot_stable` | bind slot 0, `sort_slots("rarity")`, assert the resolved `instanceId` is unchanged |
| `inventory_ui.quick_slot_migration` | migrating `{"quickSlots": [3, -1, 0]}` yields the instance ids formerly at 3 and 0 |
| `inventory_ui.focus_on_open` | after `show_inventory()`, `gui_get_focus_owner()` is a descendant of the stash `GridContainer` |
| `inventory_ui.focus_reaches_actions` | `ui_down` from the last grid row focuses `_btn_equip` |
| `inventory_ui.quick_slot_actions_used` | `inventory_ui.gd` contains no `KEY_1`/`KEY_2`/`KEY_3`, and each of `quick_slot_1`-`quick_slot_3` has at least one `InputEventJoypadButton` |
| `inventory_ui.loadout_focus_on_open` | after `open()`, `WeaponList.has_focus()` |
| `inventory_ui.tooltip_scrolls` | a slot with 4 affixes yields a tooltip whose `ScrollContainer` content height exceeds its rect and is scrollable |
| `inventory_ui.stack_and_durability` | a 7-stack renders `"7"`; a 40/100 durability item renders a progress value of `0.4` |
| `inventory_ui.localized` | every `Label` and `Button` text in the built tree is present as a key in `strings.csv` |
| `inventory_ui.no_hardcoded_colors` | `inventory_ui.gd` contains no `add_theme_color_override` with a literal `Color(` |
| `inventory_ui.mouse_mode_deferred` | `hide_inventory()` with another modal registered leaves `Input.mouse_mode == MOUSE_MODE_VISIBLE` |
| `inventory_ui.loadout_from_content` | `loadout_ui.gd` contains no hardcoded weapon-id array and lists every catalog weapon allowed for the current class |

## Related
- Existing behavior: [`../existing_codebase/ui/inventory_ui.md`](../existing_codebase/ui/inventory_ui.md)
- [`status_icons_glyphs.md`](status_icons_glyphs.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`hub_vendors.md`](hub_vendors.md) · [`waves_hud.md`](waves_hud.md)
- [`../inventory-service.md`](../inventory-service.md) · [`../loot-and-equipment.md`](../loot-and-equipment.md) · [`../content-catalog.md`](../content-catalog.md) · [`../save-migrator.md`](../save-migrator.md)
