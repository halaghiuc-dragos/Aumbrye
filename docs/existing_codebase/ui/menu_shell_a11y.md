# Menu shell accessibility, focus, and navigation

This topic records the actual state of focus handling, keyboard/gamepad navigation, and accessibility affordances across every menu in the client. It is a cross-cutting audit; per-menu behavior lives in each menu's own doc.

## Where focus is handled at all
A repo-wide search for `grab_focus`, `focus_neighbor`, and `focus_mode` under `apps/game/client/scripts/ui/` returns exactly 13 lines in 9 files:

| Site | What it does |
|---|---|
| `menu_shell.gd:121-123` | `ConfirmOverlay` sets `focus_neighbor_left/right` between Cancel and Confirm and calls `cancel.grab_focus()` |
| `merchant_ui.gd:46` | `_buy_list.grab_focus()` on open |
| `blacksmith_ui.gd:46` | `_item_list.grab_focus()` on open |
| `storage_ui.gd:41` | `_inv_list.grab_focus()` on open |
| `quest_board_ui.gd:35` | `_available_list.grab_focus()` on open |
| `castle_entry_menu.gd:80`, `:142`, `:193`, `:198`, `:203` | `_new_button.grab_focus()` on open, `_seed_input.grab_focus()` in four places |
| `umbral_waves_menu.gd:30` | `_new_button.grab_focus()` on open |
| `umbral_endless_menu.gd:44` | `_new_button.grab_focus()` on open |
| `dialogue_ui.gd:98` | sets every choice button to `Control.FOCUS_NONE` — the only deliberate opt-out |

Nothing anywhere sets `focus_neighbor_top`/`bottom`, `focus_next`, `focus_previous`, or `Control.FOCUS_ALL`. No control in the project draws a custom focus ring; selection is signalled with `modulate` or `self_modulate` tinting instead (`dialogue_ui.gd:113-119`, `inventory_ui.gd:463-471`).

## Per-menu focus audit
| Menu | Focus on open | Navigation mechanism | Verdict |
|---|---|---|---|
| `title_screen.gd` | n/a — no focusable control exists | `_input` accepts any `InputEventKey`, `InputEventMouseButton`, or `InputEventJoypadButton` (`:126-138`) | works on every device |
| `main_menu.gd` | none | four `Button`s from `MenuShell.make_menu_button` (`:69-74`) and nothing else | mouse-only: with no focus owner, `ui_down` and `ui_accept` do nothing |
| `continue_menu.gd` | none — `_slot_list.select(0)` without `grab_focus` (`:51-53`) | `ItemList` plus three buttons | mouse-only for the list and all three buttons; only `ui_cancel` works (`:139-145`) |
| `character_create_ui.gd` | none (`:118-134`) | `ItemList`, `LineEdit`, five `OptionButton`s, two buttons | mouse-only; the mandatory name field cannot be reached without a click |
| `pause_menu.gd` | none (`:31-39`) | 3-4 buttons | mouse-only; only Esc / `pause` works (`:68-73`) |
| `settings_ui.gd` | none (`:500-515`) | 5 sliders, 11+ checkboxes, 4 option buttons, N backup buttons inside a `ScrollContainer` | mouse-only; Esc closes (`:545-551`) |
| `talents_ui.gd` | none | custom `_unhandled_input` on `ui_up`/`ui_down`/`ui_accept` driving `_node_list.select(_cursor)` (`:76-85`) | pad-navigable without focus; the `ItemList` itself never receives focus |
| `inventory_ui.gd` | none | custom `_unhandled_input` cursor over hand-tinted cells (`:224-268`, `:463-471`) | grid navigable; Equip/Unequip/Use/Bind buttons mouse-only |
| `loadout_ui.gd` | none — `_list.select(0)` without `grab_focus` (`:37-39`) | `ItemList` plus two buttons | mouse-only |
| `stair_menu.gd` | none | buttons built in `_rebuild_buttons` (`:65-78`) with no `ui_accept` handling | mouse-only; only Esc works (`:99-104`) |
| `dialogue_ui.gd` | deliberate `FOCUS_NONE` | custom `_unhandled_input` on `ui_up`/`ui_down`/`ui_accept`/`interact` with `modulate` selection (`:53-73`, `:113-119`) | pad-navigable, outside the focus system |
| `results_screen.gd` | none | any `ui_accept` or `interact` dismisses (`:80-91`) | works on every device |
| `merchant_ui`, `blacksmith_ui`, `storage_ui`, `quest_board_ui` | `grab_focus` on a list | native `ItemList` navigation | navigable |
| `castle_entry_menu`, `umbral_waves_menu`, `umbral_endless_menu` | `grab_focus` on a button | native button focus chain | navigable |
| `MenuShell.show_confirmation` | `cancel.grab_focus()` | left/right neighbors | navigable |

## Input actions available to menus
From `apps/game/client/project.godot` `[input]`:

| Action | Keyboard | Gamepad |
|---|---|---|
| `ui_accept` `:83-88` | Enter (`4194309`) | button 0 |
| `ui_cancel` `:89-94` | Escape (`4194305`) | button 1 |
| `ui_left/right/up/down` `:95-118` | arrow keys | D-pad 13 / 14 / 11 / 12 |
| `inventory` `:250-255` | Tab | button 4 |
| `talents` `:271-276` | K | button 7 |
| `heal` `:283-288` | H | button 7 |
| `quick_slot_1/2/3` `:256-270` | 1 / 2 / 3 | none |
| `interact` `:277-282` | E | button 2 |

`talents` and `heal` are both bound to joypad button 7 (`:274` and `:286`), so one pad press fires both actions.

There is no `ui_focus_next` / `ui_focus_prev` entry, so Tab-cycling relies on Godot's built-ins while Tab itself is bound to `inventory`.

## Accessibility settings that affect menus
| Setting | Where set | Effect on menus |
|---|---|---|
| `ui_scale` | `settings_ui.gd:68-79` (unlabeled `HSlider`, 0.8-1.5) | `DisplaySettings.apply()` sets `tree.root.content_scale_factor`, clamped to 0.75-1.75 (`display_settings.gd:11`) |
| `subtitle_scale` | `settings_ui.gd:88-98` (unlabeled `HSlider`, 0.8-1.6) | read only by `dialogue_ui.gd:79-81`, which scales the speaker and body font |
| `reduce_camera_shake` | `settings_ui.gd:80-87` | gameplay camera only, no menu effect |
| `vibration_intensity` | `settings_ui.gd:99-109` (unlabeled `HSlider`) | no menu effect |
| `colorblind_mode` | `settings_ui.gd:110-125` (unlabeled `OptionButton`) | no menu effect; `AccessibilitySettings.get_damage_color` is referenced only from a validation suite |

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Focus on open for scene-based hub and portal menus | IMPLEMENTED | 8 `grab_focus` call sites listed above |
| Focus on open for code-built menus | ABSENT — `main_menu`, `continue_menu`, `character_create_ui`, `pause_menu`, `settings_ui`, `talents_ui`, `inventory_ui`, `loadout_ui`, `stair_menu` all skip it | the `grab_focus` list contains none of them |
| Focus neighbors | PARTIAL — two assignments, both inside `ConfirmOverlay` | `menu_shell.gd:121-122` |
| Visible focus indicator | ABSENT — no focus `StyleBox`, no theme, no ring; selection is `modulate` tinting | `dialogue_ui.gd:113-119`, `inventory_ui.gd:463-471`; 0 theme resources in the client |
| Gamepad-complete menu flow | BROKEN — the pause menu, main menu, settings, character creation, continue, loadout, and stair menus cannot be operated with a gamepad or keyboard alone | per-menu table above |
| `ScrollContainer` focus following | ABSENT — the settings scroll never sets `follow_focus` | `settings_ui.gd:45-50` |
| Consistent Esc handling | PARTIAL — implemented separately in nine `_unhandled_input`/`_input` handlers, with `main_menu` using `_input` and everything else `_unhandled_input` | `main_menu.gd:200`, `pause_menu.gd:68`, `settings_ui.gd:545`, `talents_ui.gd:63`, `inventory_ui.gd:224`, `continue_menu.gd:139`, `character_create_ui.gd:205`, `stair_menu.gd:99`, `dialogue_ui.gd:53` |
| Mouse-mode ownership | PARTIAL — 14 direct `Input.mouse_mode` assignments across menu scripts, with no arbitration | `pause_menu.gd:38,48`; `settings_ui.gd:515,540,542`; `inventory_ui.gd:289,302`; `talents_ui.gd:53,60`; `dialogue_ui.gd:40,49`; `stair_menu.gd:30,38`; `continue_menu.gd:50` |
| Duplicate gamepad binding | BROKEN — `talents` and `heal` share joypad button 7 | `project.godot:274`, `:286` |
| Gamepad path for quick slots | ABSENT — `quick_slot_1/2/3` have keyboard events only | `project.godot:256-270` |
| Rebinding UI | ABSENT — no control-remap screen anywhere; `settings_ui.gd` has no input section | `settings_ui.gd:55-58` builds accessibility, audio, pixel, and save sections only |
| Text scaling for menus | PARTIAL — `ui_scale` scales the whole viewport via `content_scale_factor`, `subtitle_scale` affects only dialogue; no menu-text-only scale | `display_settings.gd:11`, `dialogue_ui.gd:79-81` |
| Colorblind support in menus | FAKE — the setting persists and changes nothing outside a validation suite | `settings_ui.gd:110-125`; `AccessibilitySettings.get_damage_color` has no gameplay or UI caller |
| Reduced-motion option | ABSENT — no such setting; the only motion is the title hint pulse | `title_screen.gd:115-119` |
| Screen-reader / TTS support | ABSENT — no `DisplayServer.tts_*` call anywhere in the client | 0 matches for `tts_` |
| Hold-to-confirm or confirm-delay for destructive actions | ABSENT — every destructive confirmation is a single button press | `menu_shell.gd:116-119` |

## Related
- Improvement plan: [`../actual_improvements/ui/menu_shell_a11y.md`](../actual_improvements/ui/menu_shell_a11y.md)
- [`menu_shell.md`](menu_shell.md) · [`settings.md`](settings.md) · [`display_settings.md`](display_settings.md) · [`pause_menu.md`](pause_menu.md) · [`main_menu.md`](main_menu.md) · [`continue_menu.md`](continue_menu.md) · [`character_create.md`](character_create.md) · [`dialogue_quests.md`](dialogue_quests.md) · [`inventory_ui.md`](inventory_ui.md) · [`run_portals.md`](run_portals.md)
- [`../accessibility.md`](../accessibility.md) · [`../player-controls.md`](../player-controls.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md)
