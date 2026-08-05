# Continue menu

The warden roster picker. An `ItemList` of save slots with a detail label and Play / Back / Delete buttons, built on `MenuShell.build_modal`. It has no scene; `main_menu.gd:30-32` instantiates the script onto a `Control`.

## File
`apps/game/client/scripts/ui/continue_menu.gd` — 145 lines, `extends Control`.

## Signals
| Signal | Emitted by | Consumed by |
|---|---|---|
| `slot_selected(character_id: String)` | `_on_play_pressed` `:107` | `main_menu.gd:33` → `LocalSave.queue_boot_continue_character` + loading screen |
| `slot_deleted(character_id: String)` | the delete confirmation `:124` | `main_menu.gd:35` → `_refresh_continue_button` |
| `cancelled` | `_on_back_pressed` `:136` | `main_menu.gd:34` → `_show_main_panel(true)` |

## Control tree (`_build_ui`, `:25-42`)
```
Control (ContinueMenu)
├── ColorRect "Backdrop"     (from MenuShell.build_modal)
└── PanelContainer "Panel"   (half 420 × 360, clamped to 48% of the viewport)
    └── MarginContainer "Margin"   (PANEL_MARGIN = 18)
        └── VBoxContainer "ContentVBox"  (separation 14)
            ├── Label "TitleLabel"   "Continue"
            ├── Label                 subtitle "Choose a warden to enter Aumbrye Tower."
            ├── ItemList              min height 200, SIZE_EXPAND_FILL
            ├── Label                 detail, word-smart autowrap
            ├── HBoxContainer         [Back] [Play Warden]
            └── HBoxContainer         [Delete Warden]
```

## Data
`_reload_slots` (`:64-77`) calls `LocalSave.list_character_slots()`, which returns dictionaries with three pre-formatted keys built in the save layer (`local_save.gd:151-162`):

| Key | Value produced by `LocalSave` |
|---|---|
| `characterId` | the roster entry id |
| `label` | `"%s — %s (Lv%d)"` of name, raw `classId`, level |
| `detail` | `"Class: %s\nLast played: %s"` of raw `classId` and `savedAt` |

When the roster is empty, the list gets one non-selectable-by-intent row reading `"No wardens yet — create one with New Game."` and both Play and Delete are disabled (`:71-73`).

Deleting goes through `MenuShell.show_confirmation` with the body `"Permanently delete %s?\nAll progress, inventory, and hub state for this warden will be erased."`, then `LocalSave.delete_character(character_id)`, then `_reload_slots()`, and closes the menu if the roster is now empty (`:110-131`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Roster listing with per-slot detail | IMPLEMENTED | `:64-96` |
| Play / Delete gating on an empty roster | IMPLEMENTED | `:69-73` |
| Delete confirmation | IMPLEMENTED, single-press | `:118-131` |
| Keyboard/gamepad focus | ABSENT — `open_menu` calls `_slot_list.select(0)` but never `grab_focus`, so arrow keys do not move the selection and Play / Back / Delete are unreachable without a mouse | `:51-53`; 0 `grab_focus` matches in the file |
| Slot presentation | PLACEHOLDER — a plain `ItemList` of pre-formatted strings; no portrait, class icon, or progress bar. The class is shown as its raw id (`knight`, not a display name) | `:74-76`; strings composed at `local_save.gd:153-161` |
| Progress information | PARTIAL — name, raw class id, level, and a `savedAt` string only. No floor reached, playtime, deaths, or gold | `local_save.gd:151-162` |
| Strings composed in the save layer | PARTIAL — the display strings the UI shows are built inside `local_save.gd`, so the UI cannot restyle or localize them | `local_save.gd:153-161` |
| Empty-roster affordance | PARTIAL — the message is an `ItemList` row, which is selectable and looks like a slot; there is no Create Warden action from here | `:72` |
| Delete safety | PARTIAL — one confirmation, one press, no name-typing or hold-to-confirm for a permanent save deletion | `:118-131` |
| `_on_slot_selected` bounds behavior | PARTIAL — an out-of-range index clears the detail and disables Delete but leaves Play enabled from `_reload_slots` | `:89-96` vs `:69` |
| Cancel handling | IMPLEMENTED via `_unhandled_input` on `ui_cancel` | `:139-145` |
| Mouse mode | PARTIAL — `open_menu` sets `MOUSE_MODE_VISIBLE`; `close_menu` sets nothing, leaving the mode to whatever opens next | `:50` vs `:56-57` |
| Localization | ABSENT — six hardcoded English strings here, plus the `label`/`detail` strings from `local_save.gd` | `:26`, `:28`, `:38-40`, `:72`, `:120-130`; 0 `tr(` calls |
| Cloud / backup slots | ABSENT from this menu — backup restore lives in the settings overlay instead | `settings_ui.gd:380-413` |
| Slot ordering | ABSENT — slots appear in roster order with no sort by last-played | `local_save.gd:145-162` iterates `_roster["characters"]` |

## Related
- Improvement plan: [`../actual_improvements/ui/continue_menu.md`](../actual_improvements/ui/continue_menu.md)
- Entry-flow coordination: [`title_main_continue.md`](title_main_continue.md)
- [`main_menu.md`](main_menu.md) · [`character_create.md`](character_create.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`settings.md`](settings.md)
- [`../local-save.md`](../local-save.md) · [`../character-service.md`](../character-service.md) · [`../save-migrator.md`](../save-migrator.md)
