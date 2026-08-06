# Player controls

`PlayerControls` is the autoloaded **meta UI router**, not a movement or combat controller. It owns the four global player menus (inventory, settings, talents, loadout) plus the pause menu, routes the `pause` action, and handles quick-slot input in `_unhandled_input`. It is on the live play path in every scene because it is an autoload. Gameplay input is gated by `PlayerInput` (`apps/game/client/scripts/app/player_input.gd`), which consults `PlayerControls.gameplay_input_blocked()` before polling `InputMap`. Movement, attacks, dodge, guard, and heal read through `PlayerInput`; camera and lock-on still poll raw `Input` with their own UI-focus gates.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/app/player_controls.gd` | Autoload `PlayerControls` (`project.godot:50`) — meta UI, loadout sync, quick slots, `resolve_locomotion()`, `gameplay_input_blocked()` |
| `apps/game/client/scripts/app/player_input.gd` | `class_name PlayerInput` — static gameplay input gate |
| `apps/game/client/scripts/app/input_bindings.gd` | `class_name InputBindings` — remapping, `REBINDABLE`, `KEYBOARD_ONLY`, `conflicts()`, LocalSave persistence |
| `apps/game/client/scripts/app/input_rebind_service.gd` | Autoload facade delegating to `InputBindings` for settings UI (`project.godot:55`) |
| `apps/game/client/project.godot` | `[input]` section, lines 82–318 |

## How it works

`_ready()` (`player_controls.gd:18`) sets `layer = 20` and `process_mode = Node.PROCESS_MODE_ALWAYS`, calls `AccessibilitySettings.load_from_save()`, `InputBindings.snapshot_defaults()`, `InputBindings.load_from_save()`, `InputBindings.apply()`, and `DisplaySettings.apply()`, then builds the UIs and connects `scene_changed`.

`resolve_locomotion(player)` (`player_controls.gd:32`) returns `player` when it implements `set_speed_multiplier`, otherwise `player.get_node_or_null("Locomotion")`.

`gameplay_input_blocked()` (`player_controls.gd:40`) returns `is_player_meta_ui_open() or get_tree().paused`.

`sync_player_loadout()` (`player_controls.gd:88`) skips waves mode, calls `InventoryService.apply_equipment_to_player_node(player)`, then `resolve_locomotion(player).refresh_appearance_visual()` when present.

`PlayerInput` (`player_input.gd:7–24`) returns zero/false from `move_vector()`, `pressed()`, and `just_pressed()` when `blocked()` is true.

Input handling:

- `_unhandled_input()` (`player_controls.gd:164`) handles `pause`, then `quick_slot_cycle`, `quick_slot_use`, and `quick_slot_1..4` when no meta UI is open and `uses_main_inventory()` is true. Each quick-slot activation marks the event handled and emits `quick_slot_used(index, item_id)`.
- `_process()` no longer polls quick slots.

`InventoryService.activate_quick_slot()` (`inventory_service.gd:270`) returns the activated `item_id` string or `""` on failure. Four quick slots (`quick_slot_indices` length 4).

## Input map

| Action | Keyboard / mouse | Joypad | Read by |
|--------|------------------|--------|---------|
| `move_forward` / `back` / `left` / `right` | `W` / `S` / `A` / `D`, deadzone 0.2 | left stick axes 0/1 | `PlayerInput.move_vector()` via `locomotion.gd`, `dodge.gd` |
| `sprint` | `Shift` | button 9 (left shoulder) | `PlayerInput.pressed(&"sprint")` in `locomotion.gd` |
| `jump` | `F` | button 0 (A) | `PlayerInput.just_pressed(&"jump")` in `dodge.gd` |
| `dodge` | `Space` | button 1 (B) | `PlayerInput.just_pressed(&"dodge")` in `dodge.gd` |
| `light_attack` | left mouse | axis 5 (right trigger) | `PlayerInput` in `weapon_controller.gd` |
| `heavy_attack` | right mouse | button 3 (Y) | `PlayerInput` in `weapon_controller.gd` |
| `block` | `Q` | axis 4 (left trigger) | `PlayerInput` in `guard.gd`, `weapon_controller.gd` (bow) |
| `lock_on` | middle mouse, `T` | button 8 (right stick click) | `lock_on.gd:47` (raw `Input`) |
| `pause` | `Escape` | button 6 (Start) | `player_controls.gd:165` |
| `zoom_in` / `zoom_out` | wheel up / down | none (keyboard-only) | `orbit_camera.gd:62-65` |
| `look_left` / `look_right` / `look_up` / `look_down` | none | right stick axes 2/3 | `orbit_camera.gd` (raw `Input`) |
| `toggle_camera` | `P` | none (keyboard-only) | `orbit_camera.gd:59` |
| `inventory` | `Tab` | button 4 (Back) | `inventory_ui.gd:225` |
| `talents` | `K` | button 11 (D-pad up) | `talents_ui.gd:64` |
| `heal` | `H` | button 7 (left stick click) | `PlayerInput.just_pressed(&"heal")` in `player_heal.gd` |
| `interact` | `E` | button 2 (X) | hub and dungeon interactables |
| `two_hand` | `V` | button 12 (D-pad down) | `PlayerInput` in `weapon_controller.gd` |
| `weapon_art` | `C` | button 10 (right shoulder) | `PlayerInput` in `weapon_controller.gd` |
| `quick_slot_1..4` | `1` / `2` / `3` / `4` | none (keyboard-only) | `player_controls.gd:187` |
| `quick_slot_cycle` | `Alt` | button 13 (D-pad left) | `player_controls.gd:178` |
| `quick_slot_use` | none | button 14 (D-pad right) | `player_controls.gd:182` |
| `debug_toggle` / `debug_hitboxes` / `toggle_damage_numbers` | `F1` / `F2` / `F3` | none | debug overlay |
| `reset_duel` | `R` | none | debug arenas |

Mouse look is not an action: `orbit_camera.gd:51-56` consumes raw `InputEventMouseMotion` while captured. Sensitivity multipliers come from `AccessibilitySettings.mouse_sensitivity` and `stick_sensitivity` (base `0.003` / `2.5`, range `0.25`–`4.0`); invert-Y from `invert_look_y`.

## Contracts

- Autoload names `PlayerControls`, `InputRebindService`. Consumers include `hub.gd`, `pause_menu.gd`, `main_menu.gd`, `combat_arena.gd`, `lock_on.gd`.
- Public API: `sync_player_loadout()`, `resolve_locomotion()`, `gameplay_input_blocked()`, `uses_main_inventory()`, UI getters/openers, `is_*_open()`, `is_player_meta_ui_open()`, signal `quick_slot_used(index, item_id)`.
- `InputBindings.REBINDABLE` — 20 discrete gameplay actions; `KEYBOARD_ONLY` — `toggle_camera`, `zoom_in`, `zoom_out`, `quick_slot_1..4`.
- Save key `input_bindings` in `LocalSave` meta; accessibility keys `mouse_sensitivity`, `stick_sensitivity`, `invert_look_y` under `accessibility`.
- Scene authors must not add nodes named `InventoryUI`, `SettingsUI`, `TalentsUI`, `LoadoutUI`, or `PauseMenu` to gameplay scenes — they are deleted on scene entry (`player_controls.gd:79`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Pause routing | IMPLEMENTED | `player_controls.gd:165` |
| Quick-slot `_unhandled_input` (4 slots, signal) | IMPLEMENTED | `player_controls.gd:178`, `:195` |
| Duplicate scene-UI cleanup | IMPLEMENTED | `player_controls.gd:79` |
| Appearance refresh after scene change | IMPLEMENTED | `player_controls.gd:88`, `resolve_locomotion()` |
| Equipment move-speed bonus | IMPLEMENTED | `inventory_service.gd:210`, `resolve_locomotion()` |
| Gameplay lockout while meta UI open | IMPLEMENTED | `player_input.gd:7`, `gameplay_input_blocked()` |
| Joypad binding map (no intra-REBINDABLE conflicts) | IMPLEMENTED | `project.godot`, `InputBindings.conflicts()` |
| Input remapping | IMPLEMENTED | `input_bindings.gd`, `settings_ui.gd` Controls section |
| Camera sensitivity / invert-Y / FOV / stick curve | IMPLEMENTED | `accessibility_settings.gd` (`cameraMouseSensitivity` etc.), `orbit_camera.gd`, `settings_ui.gd` |

## Related
- Improvement plan: [`../actual_improvements/player-controls.md`](../actual_improvements/player-controls.md)
- [`locomotion.md`](locomotion.md), [`player-heal.md`](player-heal.md), [`orbit-camera.md`](orbit-camera.md), [`lock-on.md`](lock-on.md)
- [`ui/inventory_ui.md`](ui/inventory_ui.md), [`ui/pause_menu.md`](ui/pause_menu.md), [`ui/talents.md`](ui/talents.md), [`ui/settings.md`](ui/settings.md), [`ui/input_glyphs.md`](ui/input_glyphs.md)
