# Inventory UI

A Diablo-style grid stash plus paper-doll equipment panel, built entirely in code at runtime with no `.tscn`. Plus a separate `ItemList`-based weapon loadout modal that does have a scene.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/inventory_ui.gd` | 988 lines, `extends Control`; the whole stash/paper-doll surface |
| `apps/game/client/scripts/ui/inventory_ui_layout.gd` | 31 lines, `class_name InventoryUILayout extends RefCounted`; only `EQUIP_LAYOUT` and `SLOT_LABELS` plus three re-exported skin constants |
| `apps/game/client/scripts/ui/loadout_ui.gd` | 113 lines, `extends Control`; hub weapon-archetype swap |
| `apps/game/client/scenes/ui/loadout_ui.tscn` | 71 lines; the only inventory-adjacent authored scene |

No `inventory_ui.tscn` exists — `player_controls.gd:25` creates a bare `Control` and assigns the script (`_make_scripted_ui`).

## Control tree — inventory (built by `_build_ui_shell`, `:126-221`)
```
Control (InventoryUI, mouse_filter IGNORE until open)
├── ColorRect        (backdrop from GameUISkin.make_backdrop, forced MOUSE_FILTER_STOP at :130)
├── PanelContainer   "Panel" (make_center_panel, half-extents 720 × 480 from :32-33 of game_ui_skin.gd)
│   └── MarginContainer (PANEL_MARGIN on all four sides)
│       └── HBoxContainer (separation = SECTION_SEPARATION)
│           ├── section frame "Stash"
│           │   └── VBoxContainer
│           │       ├── Label "Title"        -> "Stash" or "Waves Stash" (:479)
│           │       ├── Label "FilterLabel"  -> "Sort: x | Type: y | Rarity: z" (:478)
│           │       ├── GridContainer        -> grid_width × grid_height cells, 64 px, gap 4
│           │       └── VBoxContainer footer
│           │           ├── Label "DetailLabel"  (560 × 88, word-smart wrap)
│           │           ├── HBoxContainer action row: Equip, Unequip, Use, Bind 1-3
│           │           ├── HBoxContainer quick-slot row: three "[n] label" Labels
│           │           ├── Label "CompareLabel" (hardcoded green override at :191)
│           │           └── Label "HintLabel"
│           ├── VSeparator (4 px)
│           └── section frame "Character"
│               └── VBoxContainer
│                   └── Control "EquipWrap"  (silhouette from build_human_silhouette, :210)
│                       └── GridContainer "EquipGrid" (3 columns, 82 px cells)
└── PanelContainer "_drag_ghost" (z_index 100, MOUSE_FILTER_IGNORE)
```

Each cell (`_make_item_cell`, `:334-366`) is a `PanelContainer` holding `VBox/GlyphLabel` (font 18), `VBox/NameLabel` (font 11), `VBox/UpgradeLabel` (font 10). No `TextureRect` and no `focus_mode` are ever set on a cell.

Paper-doll grid, `inventory_ui_layout.gd:13-18` — spacer where the string is empty:

| | col 0 | col 1 | col 2 |
|---|---|---|---|
| row 0 | — | `helmet` | — |
| row 1 | `weapon` | `chest` | `secondary` |
| row 2 | `gloves` | `amulet` | `ring` |
| row 3 | — | `boots` | `relic` |

## Services and data
- Grid source switches on run mode: `_inventory()` (`:76-79`) returns `WavesRunService.waves_inventory` when `RunFlow.get_run_mode() == MODE_WAVES`, else `InventoryService.inventory`.
- Rebinds on `get_tree().scene_changed` (`:68-70`) and on `InventoryService.inventory_changed` / `WavesRunService.inventory_changed` (`:67`, `:72`).
- `ItemCatalog.get_definition` for defs (`:864`), `RarityRegistry.display_color` / `display_name`, `BlacksmithService.get_slot_upgrade_level`, `Equipment.compare_stats` / `format_stat_line` / `format_delta_line`, `AffixRoller.get_affix_stat`, `InputGlyphService.get_action_glyph`.
- Equip application goes through `WavesRunService.apply_equipment_to_player` or `InventoryService.apply_equipment_to_player_node` (`:781-784`).

## Input (`_unhandled_input`, `:224-268`)
| Action | Effect |
|---|---|
| `inventory` | toggle open/closed |
| `ui_cancel` | cancel drag if dragging, else close |
| `ui_accept` | `_confirm_action` — equip / use / pick up, or unequip when the equipment column is focused |
| `ui_left/right/up/down` | move `_cursor` or cross into the equipment column when already at `grid_width - 1` (`:542-544`) |
| `sprint` | cycle sort mode and immediately re-sort the inventory |
| `lock_on` | cycle type filter |
| `interact` | cycle rarity filter |
| `KEY_1`/`KEY_2`/`KEY_3` | bind the selected grid index to quick slot 1-3 (`:974-986`); matched as raw keycodes even though `quick_slot_1`-`quick_slot_3` actions exist at `project.godot:256-270`, and those actions carry no joypad event |

Mouse: per-cell `gui_input`, `mouse_entered`, `mouse_exited` (`:115-117`, `:317-319`); left click equips, uses, or starts a drag; the drag ghost follows `get_global_mouse_position()` from `_process` (`:270-274`).

## Loadout UI
`loadout_ui.tscn` root `Control` with `Dimmer` `ColorRect` (`Color(0,0,0,0.45)`) and a `PanelContainer` at ±200 × ±160 containing `Title`, `WeaponList` (`ItemList`, min height 180), `InfoLabel`, `EquipButton`, `CloseButton`. `loadout_ui.gd:26` calls `GameUISkin.apply_modal_menu(self, "Panel", "Dimmer")`. Candidate weapons are the hardcoded five ids at `:9-15`; gating is a hardcoded `match` on level 5 / level 8 and two theme-cleared flags (`:76-84`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Grid stash with multi-cell items | IMPLEMENTED — origin cell shows the abbrev, other covered cells are drawn empty-but-styled | `inventory_ui.gd:418-434` |
| Paper doll with 9 slots | IMPLEMENTED | `inventory_ui_layout.gd:13-30`; built at `inventory_ui.gd:305-321` |
| Mouse drag and drop, both directions | IMPLEMENTED | `:720-760`, `:595-611` |
| Stat compare vs equipped | IMPLEMENTED | `:509`, `:517-521`, `:868-881` |
| Waves-mode inventory switch | IMPLEMENTED | `:76-88` |
| Item icons | PARTIAL — every item renders as a Unicode character in a `Label`, never a texture. No item JSON has an `iconPath` or `icon` key (0 matches across `content/`), and no `.png` exists in the client | `:795-817` returns `⚔ ⛨ ▣ ✋ ▼ ◯ ✦ ✚ ◆ •`; `:820-831` returns `⚔ ⛨ ▣ ✋ ▼ ◯ ✦ ✧ ⬛` |
| Item names in cells | PARTIAL — truncated to 4 characters with no ellipsis, so `Castle Sword` reads `Cast` and `Castle Crown` also reads `Cast` | `:787-792` |
| Type / rarity filters | FAKE — `_rebuild_visible_indices` fills `_visible_indices` (`:393-399`) but `_refresh_grid` iterates `inv.slots` in full and never reads it; only the label text changes | `_visible_indices` is written at `:394-399` and read nowhere; `:402-439` |
| Consumable use | BROKEN — every consumable calls `health.heal(def.get("healAmount", 30.0))`; only `health_potion.json:9` defines `healAmount`, so `mana_potion`, `stamina_potion`, `elixir_might`, `elixir_vigor` and all four `skip_*_floors` items heal exactly 30 HP and vanish | `:630-641`; `content/items/consumables/*.json` — 1 of 9 has `healAmount` |
| Quick-slot binding | BROKEN — bindings store a raw grid index (`inventory_service.gd:224-233`), and `sort_slots` reorders `slots` in place plus repacks (`grid_inventory.gd:208-227`), so pressing `sprint` silently repoints every quick slot at a different item | `inventory_ui.gd:644-647` then `:962-966` |
| Keyboard/gamepad focus on open | PARTIAL — `show_inventory` sets `_cursor` and `_focus_area` but calls no `grab_focus()`; navigation works only through the custom `_unhandled_input` path, and the Equip/Unequip/Use/Bind buttons are reachable by mouse only | `:284-294` has no `grab_focus`; the only `grab_focus` in the file is ABSENT (0 matches) |
| Loadout list focus on open | PARTIAL — `_list.select(0)` without `grab_focus()`, so arrow keys do not move the `ItemList` selection | `loadout_ui.gd:37-39` |
| Localization | ABSENT — every string is a hardcoded English literal; no `tr()` call in either file | `inventory_ui.gd:478`, `:491-529`, `:834-842`; `loadout_ui.gd:67`; 0 `tr(` matches |
| Rarity color source | IMPLEMENTED via `RarityRegistry` for glyph/frame, but `CompareLabel` hardcodes `Color(0.65, 0.9, 0.65)` outside the skin | `:349` vs `:191` |
| Tooltip presentation | PARTIAL — the "tooltip" is a fixed 560 × 88 `Label` in the footer, not a hover panel; long items overflow silently | `:166-171`, `:884-901` |
| Stack counts | ABSENT — cells show a `+n` upgrade level but never a stack quantity, though `stackSize` is up to 10 on consumables | `:359-364`; `content/items/consumables/health_potion.json` has `stackSize` |
| Durability display | ABSENT — `maxDurability` exists in item JSON, nothing in the UI reads it | `content/items/equipment/castle_sword.json:13`; 0 matches for `urabilit` in `inventory_ui.gd` |
| Item drop / discard | ABSENT — no drop, destroy, or sell path from the stash | 0 matches for `drop`/`discard` outside drag handling |
| Split stack | ABSENT | 0 matches for `split` |
| Search box | ABSENT — filtering is cycle-only, no `LineEdit` | `:158` is the only text-input-adjacent control and it is a `GridContainer` |
| `_build_grid()` | STUB — 2 lines that only forward to `_ensure_grid_dimensions`, called from nowhere | `:324-325`; 0 other call sites |
| `loadout_ui.gd` weapon list | PLACEHOLDER — five hardcoded ids and a hardcoded level/flag `match`, not driven by `content/` | `loadout_ui.gd:9-15`, `:76-84` |
| Mouse mode on close | PARTIAL — `hide_inventory` unconditionally sets `MOUSE_MODE_CAPTURED`, even when opened from the hub or with another menu still open | `:302`; same pattern at `loadout_ui.gd:45` |

## Related
- Improvement plan: [`../actual_improvements/ui/inventory_ui.md`](../actual_improvements/ui/inventory_ui.md)
- [`game_ui_skin.md`](game_ui_skin.md) · [`menu_shell.md`](menu_shell.md) · [`input_glyphs.md`](input_glyphs.md) · [`hub_vendors.md`](hub_vendors.md) · [`waves_hud.md`](waves_hud.md)
- [`../inventory-service.md`](../inventory-service.md) · [`../loot-and-equipment.md`](../loot-and-equipment.md) · [`../content-catalog.md`](../content-catalog.md) · [`../weapons.md`](../weapons.md)
