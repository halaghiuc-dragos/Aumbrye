# Continue menu — improvement plan

## Current state
The roster picker is an `ItemList` of strings that `local_save.gd:151-162` pre-formats — `"Warden — knight (Lv3)"` and `"Class: knight\nLast played: ..."` — plus a detail `Label` and three buttons. `open_menu` selects row 0 without focusing the list (`:51-53`), so the menu is mouse-only. Deleting a warden is a single button press behind one confirmation. Nothing is localized, and the class is shown as its raw content id. See [`../existing_codebase/ui/continue_menu.md`](../existing_codebase/ui/continue_menu.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CNT-01 | P0 | Mouse-only: `_slot_list.select(0)` without `grab_focus`, so arrow keys change nothing and Play / Back / Delete cannot be reached on a gamepad. The only way past this screen without a mouse is Esc. | `:51-53`; 0 `grab_focus` matches; `:139-145` handles only `ui_cancel` |
| CNT-02 | P0 | Permanent save deletion is one confirmation and one press, with no hold, no name confirmation, and no undo. | `:118-131`; `LocalSave.delete_character` removes the file at `local_save.gd:427-429` |
| CNT-03 | P1 | The UI's display strings are composed inside the save layer, so the roster cannot be restyled, localized, or given per-field formatting without editing `local_save.gd`. | `local_save.gd:153-161`; consumed verbatim at `:75-76`, `:95` |
| CNT-04 | P1 | A save slot shows name, raw class id, level, and a `savedAt` string. It does not show floor reached, playtime, deaths, gold, or equipped weapon — the things that identify a run in progress. | `local_save.gd:151-162` |
| CNT-05 | P1 | The class is displayed as its raw id (`knight`), not a localized display name, even though `ClassCatalog` has names. | `local_save.gd:155`; `character_create_ui.gd:145` reads `class_def["name"]` for the same data |
| CNT-06 | P1 | Slots are plain text rows: no portrait, class icon, rarity/level framing, or progress bar. | `:74-76` |
| CNT-07 | P1 | Zero localization: six literals here plus two composed in the save layer. | `:26`, `:28`, `:38-40`, `:72`, `:120-130` |
| CNT-08 | P2 | The empty-roster message is an `ItemList` row that looks and selects like a real slot, and there is no Create Warden action from this screen. | `:71-73` |
| CNT-09 | P2 | Slots are listed in raw roster order with no sort, so the warden you played last is not necessarily first. | `local_save.gd:145-162` |
| CNT-10 | P2 | `_on_slot_selected` with an out-of-range index disables Delete but leaves Play enabled from `_reload_slots`, so Play can be pressed with no valid selection (it then returns silently at `:101`). | `:89-96` vs `:69` |
| CNT-11 | P2 | `close_menu` restores no mouse mode, leaving the cursor state to whatever opens next. | `:56-57` against `:50` |
| CNT-12 | P2 | Backup restore lives in the settings overlay, far from the screen where a player looks for a lost save. | `settings_ui.gd:380-413` |

## Target design

### Slot data as data
`LocalSave.list_character_slots()` stops formatting strings and returns structured fields:

```gdscript
{
  "characterId": String,
  "name": String,
  "classId": String,
  "level": int,
  "floorReached": int,
  "playtimeSeconds": int,
  "deaths": int,
  "gold": int,
  "equippedWeaponId": String,
  "savedAtUnix": int,
}
```

The UI composes and localizes everything from these (CNT-03, CNT-04). `classId` is resolved through `ClassCatalog.get_class(classId).nameKey` and `tr()` (CNT-05). `savedAtUnix` allows a relative "3 hours ago" rendering and a real sort (CNT-09).

Rejected alternative: adding more pre-formatted keys to `local_save.gd`. That deepens the coupling that makes the roster unlocalizable.

### Slot cards instead of list rows
Replace the `ItemList` with a `VBoxContainer` of focusable `SlotCard` controls inside a `ScrollContainer`:

```
SlotCard (PanelContainer, focus_mode = FOCUS_ALL, custom_minimum_size 380 × 84)
└── HBoxContainer
    ├── TextureRect "ClassIcon"    # 32 px UISymbolAtlas cell, key class/<classId>
    ├── VBoxContainer
    │   ├── Label "NameLabel"      MenuTitle at font size 18
    │   ├── Label "MetaLabel"      HintText — class, level, floor
    │   └── ProgressBar "FloorBar" ResourceBar variation, value = floorReached / max known floor
    ├── VSeparator
    └── VBoxContainer
        ├── Label "PlaytimeLabel"  HintText
        └── Label "SavedAtLabel"   HintText — relative time
```

Class icon cells are added to the shared symbol atlas as `class/<classId>` (see [`status_icons_glyphs.md`](status_icons_glyphs.md)). Focus order is the card list; `ui_accept` on a card plays that warden; a `Delete` action bound to `ui_focus_next`-adjacent input is replaced by an explicit per-card Delete button reachable with `ui_right` (CNT-01, CNT-06).

### Focus rules
- `initial_focus` is the card for the most recently played warden.
- `ScrollContainer.follow_focus = true`.
- `ui_right` from a card focuses that card's Delete button; `ui_left` returns.
- `ui_down` past the last card focuses `BackButton`.
- With an empty roster, `initial_focus` is `CreateWardenButton` (CNT-01, CNT-08).

### Delete safety
Deleting uses `MenuStack.confirm` with `destructive = true`, which under `hold_to_confirm` (see [`menu_shell_a11y.md`](menu_shell_a11y.md)) requires a `0.6` s hold. The confirmation body names the warden, its level, and its floor so the player can see exactly what is being erased. `LocalSave.delete_character` first copies the character file to `user://backups/deleted_<id>_<unix>.json` and keeps the three most recent, making the delete recoverable from the new restore panel (CNT-02).

### Empty state
An empty roster shows a centered `Label` plus a `CreateWardenButton` that emits a new `create_requested` signal; `main_menu.gd` routes it to `_character_create.open_creation()`. No fake `ItemList` row (CNT-08).

### Restore panel here
A `RestoreButton` at the bottom opens a `MenuModal` listing `LocalSave.list_backups()` and the new `deleted_*` snapshots, sharing its implementation with the settings section at `settings_ui.gd:380-413` rather than duplicating it (CNT-12).

### Small fixes
- `_on_slot_selected` sets `Play.disabled` alongside `Delete.disabled` so the two never disagree (CNT-10).
- `close_menu` leaves mouse mode to `MenuStack` (CNT-11).

### Localization
Keys: `CONTINUE_TITLE`, `CONTINUE_SUBTITLE`, `CONTINUE_EMPTY`, `CONTINUE_CREATE`, `CONTINUE_PLAY`, `CONTINUE_DELETE`, `CONTINUE_BACK`, `CONTINUE_RESTORE`, `CONTINUE_META_FORMAT`, `CONTINUE_PLAYTIME_FORMAT`, `CONTINUE_SAVED_RELATIVE_*` (minutes/hours/days), `CONTINUE_DELETE_TITLE`, `CONTINUE_DELETE_BODY`, `CONTINUE_DELETE_OK`, `CONTINUE_DELETE_CANCEL` (CNT-07).

## Work plan
1. **Focus and card list** — replace the `ItemList` with focusable `SlotCard`s, `initial_focus`, `follow_focus`, and the neighbor rules (CNT-01, CNT-06).
2. **Structured slot data** — change `LocalSave.list_character_slots()` to the field dictionary and update both callers (`continue_menu.gd`, `main_menu.gd`'s detail line) (CNT-03, CNT-04, CNT-05, CNT-09).
3. **Delete safety** — destructive `MenuStack.confirm`, warden details in the body, `deleted_*` snapshot on delete (CNT-02).
4. **Empty state** — label plus `create_requested` button (CNT-08).
5. **Localization** — all strings to `strings.csv` (CNT-07).
6. **Restore panel** — shared component surfaced here and in settings (CNT-12).
7. **Small fixes** — Play/Delete disabled parity, mouse-mode handoff (CNT-10, CNT-11).

## Data and schema changes
- `LocalSave.list_character_slots()` returns structured fields; the roster file gains `floorReached`, `playtimeSeconds`, `deaths`, `gold`, `equippedWeaponId`, and `savedAtUnix` per character. `save_migrator.gd` backfills them from the existing character save where available and `0` otherwise, and bumps the save version.
- `user://backups/deleted_<id>_<unix>.json` snapshots, capped at 3.
- `content/ui/status_icon_atlas.json`: `class/<classId>` cells for every id in `content/classes/`.
- `apps/game/client/translations/strings.csv`: the `CONTINUE_*` keys above.

## Acceptance criteria
- [ ] Opening the continue menu focuses the most recently played warden's card; the entire screen is operable on a gamepad.
- [ ] `ui_right` from a card focuses that card's Delete button and `ui_left` returns to the card.
- [ ] `ui_down` past the last card focuses Back.
- [ ] Focusing a card below the visible area scrolls it into view.
- [ ] `local_save.gd` composes no display string; `list_character_slots()` returns no key whose value contains a space-separated sentence.
- [ ] A slot card shows localized class name, level, floor reached, playtime, and a relative saved-at time.
- [ ] The class name shown is the localized `ClassCatalog` name, never a raw id.
- [ ] Deleting a warden requires a `0.6` s hold when `hold_to_confirm` is on and names the warden, level, and floor in the body.
- [ ] After a delete, a `deleted_<id>_<unix>.json` snapshot exists and appears in the restore panel.
- [ ] With an empty roster, no `ItemList` row is shown and Create Warden is focused.
- [ ] Play and Delete are enabled and disabled together; Play can never be pressed without a valid selection.
- [ ] `continue_menu.gd` contains no `Input.mouse_mode` assignment.
- [ ] Every visible string changes when the locale is switched to a stub translation.

## Validation
Extend `apps/game/client/scripts/validation/suites/save_suite.gd` and add `continue_menu` cases:

| Test id | Assertion |
|---|---|
| `continue_menu.focus_on_open` | focus owner is the `SlotCard` whose `savedAtUnix` is the maximum |
| `continue_menu.focus_graph` | BFS from `initial_focus` reaches every card, every card Delete button, Back, and Restore |
| `continue_menu.follow_focus` | the `ScrollContainer` reports `follow_focus == true` |
| `continue_menu.slots_structured` | `list_character_slots()[0]` has all ten fields and no value containing `" — "` |
| `continue_menu.no_formatting_in_save` | `local_save.gd` contains no `"Class: "` or `"Lv%d"` literal |
| `continue_menu.class_name_localized` | a card's meta line contains `tr(ClassCatalog.get_class(id).nameKey)` and not the raw id |
| `continue_menu.card_fields` | a seeded slot renders level, floor, playtime, and a relative time string |
| `continue_menu.delete_hold` | with `hold_to_confirm`, a `0.3` s press does not delete and a `0.7` s hold does |
| `continue_menu.delete_body_details` | the confirmation body contains the warden name, level, and floor |
| `continue_menu.delete_snapshot` | after deletion, a `user://backups/deleted_*` file exists and is listed by the restore panel |
| `continue_menu.delete_snapshot_cap` | four deletions leave exactly three snapshots |
| `continue_menu.empty_state` | with an empty roster there are zero `SlotCard`s and `CreateWardenButton` has focus |
| `continue_menu.create_signal` | pressing Create Warden emits `create_requested` |
| `continue_menu.play_delete_parity` | for every selection state, `Play.disabled == Delete.disabled` |
| `continue_menu.no_mouse_mode` | `continue_menu.gd` contains no `Input.mouse_mode` |
| `continue_menu.localized` | every `Label` and `Button` text resolves from a `strings.csv` key |
| `continue_menu.slot_sort` | cards are ordered by descending `savedAtUnix` |

## Related
- Existing behavior: [`../existing_codebase/ui/continue_menu.md`](../existing_codebase/ui/continue_menu.md)
- Entry-flow coordination: [`title_main_continue.md`](title_main_continue.md)
- [`main_menu.md`](main_menu.md) · [`character_create.md`](character_create.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`settings.md`](settings.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md)
- [`../local-save.md`](../local-save.md) · [`../save-migrator.md`](../save-migrator.md) · [`../character-service.md`](../character-service.md)
