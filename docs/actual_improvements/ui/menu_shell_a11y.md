# Menu accessibility, focus, and navigation — improvement plan

## Current state
Thirteen lines across nine files are the entire focus implementation in the client. Four hub panels and three portal menus call `grab_focus` on open; `MenuShell.show_confirmation` is the only place that sets focus neighbors. The pause menu, main menu, settings, character creator, continue menu, loadout modal, and stair menu focus nothing and are therefore mouse-only. `dialogue_ui.gd:98` explicitly opts every dialogue choice out of the focus system. No control anywhere draws a focus ring; selection is communicated by `modulate` tinting. `talents` and `heal` share joypad button 7. See [`../existing_codebase/ui/menu_shell_a11y.md`](../existing_codebase/ui/menu_shell_a11y.md).

Scaffold structure and the modal stack are owned by [`menu_shell.md`](menu_shell.md); this plan owns focus, navigation, and accessibility policy.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| MSA-01 | P0 | The pause menu is unusable without a mouse. `open_menu` sets `visible`, pauses the tree, and shows the cursor, but focuses nothing, so `ui_accept` has no target and Resume / Settings / Abandon / Quit cannot be reached on a gamepad. | `pause_menu.gd:31-39`; buttons at `:60-64`; no `grab_focus` in the file |
| MSA-02 | P0 | The main menu is mouse-only: four buttons, no focus, no neighbors. A player on a controller cannot start the game from the front end. | `main_menu.gd:69-74`; no `grab_focus` in the file |
| MSA-03 | P0 | Character creation is mouse-only, and the warden name is mandatory — a controller player cannot create a character at all. | `character_create_ui.gd:118-134`; `LineEdit` at `:49-52`; validation at `:186-190` |
| MSA-04 | P0 | The settings overlay is mouse-only across 5 sliders, 11+ checkboxes, 4 option buttons, and every backup button, inside a `ScrollContainer` that does not follow focus. | `settings_ui.gd:500-515`, `:45-50` |
| MSA-05 | P0 | The continue menu calls `_slot_list.select(0)` without focusing the list, so arrow keys change nothing and Play / Delete / Back are mouse-only. | `continue_menu.gd:51-53` |
| MSA-06 | P0 | The stair menu builds Ascend / Descend / Retreat / Close buttons with no focus and no `ui_accept` handling, so a floor transition cannot be triggered without a mouse. | `stair_menu.gd:65-78`, `:99-104` |
| MSA-07 | P0 | No visible focus indicator exists anywhere. Even the menus that do focus a control give no on-screen feedback about where focus is, because there is no theme and no focus `StyleBox`. | 0 theme resources under `apps/game/client`; selection shown by `modulate` at `dialogue_ui.gd:113-119` and `inventory_ui.gd:463-471` |
| MSA-08 | P1 | `talents` and `heal` are both bound to joypad button 7, so one press opens the talent tree and drinks a potion. | `project.godot:274` and `:286` |
| MSA-09 | P1 | `quick_slot_1/2/3` have no gamepad event, so quick slots are keyboard-only by data as well as by code. | `project.godot:256-270` |
| MSA-10 | P1 | Esc handling is duplicated in nine scripts, one of which (`main_menu.gd`) uses `_input` while the rest use `_unhandled_input`, so precedence between overlapping menus is an accident of tree order. | `main_menu.gd:200` vs `pause_menu.gd:68`, `settings_ui.gd:545`, `talents_ui.gd:63`, `inventory_ui.gd:224`, `continue_menu.gd:139`, `character_create_ui.gd:205`, `stair_menu.gd:99`, `dialogue_ui.gd:53` |
| MSA-11 | P1 | 14 direct `Input.mouse_mode` assignments across menu scripts with no arbitration, which is why closing one menu over another captures the cursor. | `pause_menu.gd:38,48`; `settings_ui.gd:515,540,542`; `inventory_ui.gd:289,302`; `talents_ui.gd:53,60`; `dialogue_ui.gd:40,49`; `stair_menu.gd:30,38`; `continue_menu.gd:50` |
| MSA-12 | P1 | No input-rebinding UI. `settings_ui.gd` builds accessibility, audio, pixel-diorama, and save sections and nothing for controls, so the button-7 collision above is not even user-fixable. | `settings_ui.gd:55-58` |
| MSA-13 | P1 | `colorblind_mode` persists and changes nothing: no UI or gameplay code reads it. | `settings_ui.gd:110-125`; `AccessibilitySettings.get_damage_color` has no caller outside a validation suite |
| MSA-14 | P2 | No reduced-motion setting, while the title hint pulses continuously and the planned modal transitions would add more. | `title_screen.gd:115-119` |
| MSA-15 | P2 | No screen-reader or TTS support of any kind. | 0 matches for `tts_` under `apps/game/client` |
| MSA-16 | P2 | Destructive confirmations are a single press with no hold or delay, and Delete Warden erases a save permanently. | `menu_shell.gd:116-119`; `continue_menu.gd:118-131` |
| MSA-17 | P2 | Dialogue choices opt out of the focus system entirely, so they cannot participate in focus rings, TTS, or `follow_focus`. | `dialogue_ui.gd:98` |

## Target design

### Focus contract
Every modal that inherits `MenuModal` (see [`menu_shell.md`](menu_shell.md)) must satisfy three rules, enforced by validation rather than convention:

1. **Focus on open.** `MenuModal.open()` calls `initial_focus.grab_focus()`; `initial_focus` is a required export and `open()` pushes an error if it is null or non-focusable.
2. **No focus dead ends.** Every focusable control in the modal is reachable from `initial_focus` by `ui_up`/`ui_down`/`ui_left`/`ui_right`, verified by a graph walk in the validation suite.
3. **Focus returns.** `close()` restores the focus owner captured at open time, or hands focus to the parent modal's `initial_focus` when there is one.

Per-menu `initial_focus`:

| Menu | `initial_focus` |
|---|---|
`main_menu` | Continue when a save exists, otherwise New Game |
`continue_menu` | `_slot_list` |
`character_create_ui` | `_class_list` |
`pause_menu` | Resume |
`settings_ui` | the first control of the first section |
`talents_ui` | `_node_list` |
`inventory_ui` | the stash cell under `_cursor` |
`loadout_ui` | `WeaponList` |
`stair_menu` | the first available action button |
`dialogue_ui` | the first choice button, or the panel itself when there are no choices |
`results_screen` | Continue button (added by [`run_outcome.md`](run_outcome.md)) |
`ConfirmOverlay` | Cancel for destructive, Confirm otherwise |

### Focus order rules
- Vertical stacks use implicit `VBoxContainer` order; nothing sets neighbors by hand.
- Grids set `focus_neighbor_left/right/top/bottom` programmatically from their own dimensions in one helper, `GameUISkin.wire_grid_focus(cells: Array[Control], columns: int, wrap_rows: bool)`.
- Button rows set only `focus_neighbor_left/right`; entering a row from above lands on its first button.
- `ScrollContainer.follow_focus = true` everywhere a scroll exists.
- A disabled control is skipped by re-pointing its neighbors, not left as a hole.

### Visible focus
The theme from [`menu_shell.md`](menu_shell.md) gains a focus `StyleBoxFlat` per variation:

| Token | Value |
|---|---|
`focus_border_color` | `Color(0.98, 0.86, 0.52)` |
`focus_border_width` | `2` px, expanded `2` px outside the control rect |
`focus_corner_radius` | `0` when the pixel preset is active, `4` otherwise |
`focus_pulse` | alpha oscillates `0.7`-`1.0` at `1.4` Hz, disabled under `reduced_motion` |

`ItemList` and `GridContainer` cells additionally get a `selected`/`focused` distinction: focus is the outline, selection is the fill. Every `modulate`-based selection hack — `dialogue_ui.gd:113-119`, `inventory_ui.gd:463-471`, `inventory_ui.gd:435-438`, `:458-460` — is deleted (MSA-07).

Rejected alternative: adding a `Panel` overlay per focused control at runtime. A theme focus stylebox is one authored resource that every control already knows how to draw.

### Input map corrections
| Action | Change |
|---|---|
`heal` | joypad moves from button 7 to button 3 |
`talents` | keeps button 7 |
`quick_slot_1/2/3` | add joypad D-pad left / up / right events |
`ui_focus_next` / `ui_focus_prev` | added explicitly so Tab-cycling does not depend on defaults while Tab is bound to `inventory` |

A validation test asserts no two non-`ui_*` actions share a joypad button index (MSA-08, MSA-09).

### Controls section in settings
`settings_ui.gd` gains a `_build_controls_section` before the audio section:

```
Controls
├── OptionButton "Device hint override"   # Auto / Keyboard / Xbox / PlayStation
├── HSlider "Look sensitivity"
├── CheckBox "Invert look Y"
├── ItemList "Bindings"                   # one row per rebindable action, showing its glyph
└── Button "Restore default bindings"
```

Selecting a row opens a `MenuStack.confirm`-style capture overlay that listens for the next `InputEventKey` or `InputEventJoypadButton`, rejects a binding that collides with another action by name, and writes through `InputMap.action_erase_events` / `action_add_event`. Bindings persist in `LocalSave` under a new `"inputBindings"` dictionary keyed by action name; `InputGlyphService` invalidates on change (see [`input_glyphs.md`](input_glyphs.md)) (MSA-12).

### Accessibility settings that do something
| Setting | New behavior |
|---|---|
`colorblind_mode` | `AccessibilitySettings.get_damage_color` becomes the single source for damage numbers, status icon tints, rarity frames, and the health/stamina/mana bar fills; each of the four modes ships a remapped palette (MSA-13) |
`reduced_motion` | new bool; suppresses the title hint pulse, modal transitions, focus pulse, camera shake, and screen-finish animation (MSA-14) |
`menu_text_scale` | new float `0.8`-`1.6`, applied as a theme font-size multiplier so menu text scales without scaling the whole viewport like `ui_scale` does |
`hold_to_confirm` | new bool, default on; destructive confirmations require holding `ui_accept` for `0.6` s with a radial fill on the button (MSA-16) |
`tts_enabled` | new bool; on focus change, `DisplayServer.tts_speak` reads the focused control's `accessible_name` meta, falling back to its text (MSA-15) |

Every one of the five gets a real `Label` next to its control — the current `ui_scale`, `subtitle_scale`, `vibration`, and `colorblind_mode` widgets have none (`settings_ui.gd:68-125`), which is tracked in [`settings.md`](settings.md).

### Dialogue choices rejoin the focus system
`dialogue_ui.gd:98` becomes `btn.focus_mode = Control.FOCUS_ALL`; `_move_selection` calls `grab_focus()` on the target button and `_update_selection_visual` is deleted in favor of the theme focus ring. `_unhandled_input`'s `ui_up`/`ui_down` handling is removed because the focus chain already does it; only `interact` remains as an alias for `ui_accept` (MSA-17).

### One cancel owner
`MenuStack` handles `ui_cancel` and dispatches `cancel_requested` to the top modal only; the nine per-menu handlers are deleted, and `main_menu.gd`'s `_input` override goes with them. `MenuStack` also owns `Input.mouse_mode`, removing all 14 assignments (MSA-10, MSA-11).

## Work plan
1. **Focus on open, everywhere** — add `initial_focus` and the `grab_focus` call to the nine menus that lack it, in the order `pause_menu`, `main_menu`, `settings_ui`, `character_create_ui`, `continue_menu`, `stair_menu`, `loadout_ui`, `talents_ui`, `inventory_ui` (MSA-01 … MSA-06).
2. **Focus ring** — add the focus styleboxes to the theme, delete every `modulate`-based selection hack (MSA-07).
3. **Grid focus helper** — `wire_grid_focus`, applied to the stash grid, paper doll, and waves reward grid.
4. **`follow_focus`** — set on the settings scroll and every future `ScrollContainer` (MSA-04 support).
5. **Input map** — move `heal` off button 7, add joypad events for the quick slots, add the two focus actions, add the collision test (MSA-08, MSA-09).
6. **Cancel and mouse-mode centralization** — via `MenuStack` (MSA-10, MSA-11).
7. **Controls section and rebinding** — new settings section, capture overlay, persistence, glyph invalidation (MSA-12).
8. **Real accessibility settings** — `colorblind_mode` wiring, `reduced_motion`, `menu_text_scale`, `hold_to_confirm`, `tts_enabled` (MSA-13 … MSA-16).
9. **Dialogue choices** back into the focus system (MSA-17).

Step 1 alone converts the game from mouse-required to pad-playable and should ship before anything else here.

## Data and schema changes
- `apps/game/client/project.godot`: `heal` joypad button 7 to 3; joypad events on `quick_slot_1/2/3`; new `ui_focus_next`, `ui_focus_prev`.
- `AccessibilitySettings`: new `reduced_motion: bool`, `menu_text_scale: float`, `hold_to_confirm: bool`, `tts_enabled: bool`, `device_hint_override: String`; all persisted.
- `LocalSave`: new `"inputBindings": Dictionary` and `"accessibility"` keys; `save_migrator.gd` adds defaults and bumps the save version.
- `apps/game/client/themes/aumbrye_ui.theme`: focus styleboxes per variation.
- `apps/game/client/translations/strings.csv`: `SET_CONTROLS_*`, `SET_A11Y_*`, `A11Y_HOLD_TO_CONFIRM`, plus `accessible_name` keys for controls that need a spoken label distinct from their visible text.

## Acceptance criteria
- [ ] Every modal in the client can be opened, fully navigated, and dismissed with a gamepad only, with no mouse input.
- [ ] Opening any modal leaves `get_viewport().gui_get_focus_owner()` non-null and inside that modal.
- [ ] Closing a modal restores focus to the control that was focused before it opened.
- [ ] A breadth-first walk of `focus_neighbor_*` from `initial_focus` reaches every enabled focusable control in each modal.
- [ ] The focused control draws a 2 px `Color(0.98, 0.86, 0.52)` outline in every modal.
- [ ] No file under `apps/game/client/scripts/ui/` communicates selection by assigning `modulate` or `self_modulate`.
- [ ] No two non-`ui_*` input actions share a joypad button index.
- [ ] `quick_slot_1`, `quick_slot_2`, `quick_slot_3` each have at least one joypad event.
- [ ] Moving focus to a control below the settings viewport scrolls it into view.
- [ ] Only `menu_stack.gd` assigns `Input.mouse_mode`, and only it handles `ui_cancel`.
- [ ] Rebinding `light_attack` to a key already used by `dodge` is refused with the conflicting action named.
- [ ] Rebindings survive a restart and are reflected in every on-screen glyph.
- [ ] Setting `colorblind_mode` to `deuteranopia` changes damage-number, status-icon, rarity-frame, and resource-bar colors.
- [ ] With `reduced_motion` on, the title hint does not pulse, modals do not tween, and the focus ring does not pulse.
- [ ] With `hold_to_confirm` on, Delete Warden requires a `0.6` s hold and shows a radial fill.
- [ ] With `tts_enabled` on, changing focus speaks the focused control's accessible name.
- [ ] Dialogue choice buttons report `focus_mode == FOCUS_ALL` and are navigated by the focus chain.

## Validation
New suite `apps/game/client/scripts/validation/suites/ui_a11y_suite.gd`, category `ui_a11y`. Every menu test runs over a table of all modals so a new menu cannot skip the rules:

| Test id | Assertion |
|---|---|
| `ui_a11y.focus_on_open_all` | for each modal in the registry, `open()` leaves a focus owner that is a descendant of that modal |
| `ui_a11y.focus_reachability` | BFS over `focus_neighbor_*` from `initial_focus` covers every enabled focusable descendant |
| `ui_a11y.focus_restore_all` | `close()` restores the pre-open focus owner |
| `ui_a11y.pad_only_flow` | a scripted gamepad-only sequence completes: main menu to character creation to a run, then pause, settings, and quit to menu |
| `ui_a11y.focus_ring_present` | the theme defines a `focus` stylebox for every variation and the focused control's draw includes it |
| `ui_a11y.no_modulate_selection` | no file under `scripts/ui/` assigns `modulate` or `self_modulate` for selection |
| `ui_a11y.no_joypad_collisions` | no two non-`ui_*` actions share a joypad `button_index` |
| `ui_a11y.quick_slot_pad_events` | each `quick_slot_*` action has at least one `InputEventJoypadButton` |
| `ui_a11y.follow_focus` | every `ScrollContainer` in a modal reports `follow_focus == true` |
| `ui_a11y.single_cancel_owner` | only `menu_stack.gd` matches `is_action_pressed("ui_cancel")` under `scripts/ui/` |
| `ui_a11y.single_mouse_mode_owner` | only `menu_stack.gd` matches `Input.mouse_mode` under `scripts/ui/` |
| `ui_a11y.rebind_conflict` | binding an event already owned by another action is rejected and the conflicting action name is reported |
| `ui_a11y.rebind_persist` | a rebinding round-trips through `LocalSave` and is reflected by `InputGlyphService` |
| `ui_a11y.colorblind_applies` | switching to each of the three modes changes the damage color, status tint, rarity color, and bar fill |
| `ui_a11y.reduced_motion` | with the flag on, no `Tween` is created by opening a modal and the title hint `modulate` is constant |
| `ui_a11y.hold_to_confirm` | a destructive confirm requires `>= 0.6` s of held `ui_accept` and a shorter press does not fire |
| `ui_a11y.tts_on_focus` | with TTS on, a focus change requests speech containing the focused control's accessible name |
| `ui_a11y.dialogue_focusable` | every dialogue choice reports `focus_mode == FOCUS_ALL` and `dialogue_ui.gd` contains no `FOCUS_NONE` |

## Related
- Existing behavior: [`../existing_codebase/ui/menu_shell_a11y.md`](../existing_codebase/ui/menu_shell_a11y.md)
- [`menu_shell.md`](menu_shell.md) · [`settings.md`](settings.md) · [`display_settings.md`](display_settings.md) · [`input_glyphs.md`](input_glyphs.md) · [`title_main_continue.md`](title_main_continue.md) · [`dialogue_quests_talents.md`](dialogue_quests_talents.md)
- [`../accessibility.md`](../accessibility.md) · [`../player-controls.md`](../player-controls.md) · [`../save-migrator.md`](../save-migrator.md)
