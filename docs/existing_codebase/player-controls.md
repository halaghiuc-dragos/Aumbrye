# Player controls

`PlayerControls` is the autoloaded **meta UI router**, not a movement or combat controller. It owns the four global player menus (inventory, settings, talents, loadout) plus the pause menu, routes the `pause` action, and polls the three quick-slot actions. It is on the live play path in every scene because it is an autoload. Movement input is read by [`locomotion.md`](locomotion.md), attacks by `WeaponController`, dodge/jump by [`dodge.md`](dodge.md), guard by [`guard.md`](guard.md), heal by [`player-heal.md`](player-heal.md), and camera by [`orbit-camera.md`](orbit-camera.md) — none of them go through `PlayerControls`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/app/player_controls.gd` | The autoload. `extends CanvasLayer`, registered as `PlayerControls` (`apps/game/client/project.godot:49`) |
| `apps/game/client/project.godot` | `[input]` section, lines 83-299: the entire input map |

## How it works

`_ready()` (`player_controls.gd:14`) sets `layer = 20` and `process_mode = Node.PROCESS_MODE_ALWAYS` so the menus draw over every HUD and keep processing while `get_tree().paused` is true. It then calls `AccessibilitySettings.load_from_save()` and `DisplaySettings.apply()` (`player_controls.gd:17-18`), builds the UIs, and connects `get_tree().scene_changed` to `_on_scene_changed` (`player_controls.gd:20`).

`_build_global_uis()` (`player_controls.gd:24`) creates four bare `Control` nodes and `set_script()`s them:

| Node name | Script |
|-----------|--------|
| `InventoryUI` | `res://scripts/ui/inventory_ui.gd` |
| `SettingsUI` | `res://scripts/ui/settings_ui.gd` |
| `TalentsUI` | `res://scripts/ui/talents_ui.gd` |
| `PauseMenu` | `res://scripts/ui/pause_menu.gd` |

Each is anchored `PRESET_FULL_RECT` with `mouse_filter = MOUSE_FILTER_IGNORE` (`player_controls.gd:41-42`). `LoadoutUI` is the only one instantiated from a scene, `res://scenes/ui/loadout_ui.tscn` (`player_controls.gd:29-34`).

On every scene change, `_after_scene_changed()` (`player_controls.gd:51`) first calls `_remove_duplicate_scene_uis()`, which walks the new `current_scene` and `queue_free()`s any node named `InventoryUI`, `SettingsUI`, `TalentsUI`, `LoadoutUI`, or `PauseMenu` (`player_controls.gd:63-66`) so a scene-local copy cannot shadow the autoload's. It then awaits one `process_frame`, re-binds the inventory context, and calls `sync_player_loadout()`.

`sync_player_loadout()` (`player_controls.gd:69`) returns immediately in waves mode (`RM.is_waves(RunFlow.get_run_mode())`), then calls `InventoryService.apply_equipment_to_player_node(player)` on the first node in group `player`.

Input handling is split in two:

- `_unhandled_input()` (`player_controls.gd:140`) reacts only to `pause`. It returns without acting if the inventory, talents, or loadout is open (`player_controls.gd:143-144`) — those UIs close themselves on `ui_cancel`, which is bound to the same Escape key. If settings are open it calls `close_settings()`, otherwise it calls `PauseMenu.toggle()`. It always calls `get_viewport().set_input_as_handled()`.
- `_process()` (`player_controls.gd:154`) polls `quick_slot_1`, `quick_slot_2`, `quick_slot_3` and forwards them to `InventoryService.activate_quick_slot(0..2)`. It skips both when any meta UI is open and when `uses_main_inventory()` is false (waves mode).

`get_tree().paused` is only set by the pause menu (`apps/game/client/scripts/ui/pause_menu.gd:37` and `:47`). Opening the inventory, talents, loadout, or settings does not pause the tree.

## Input map

Every action below is read somewhere in the client. Keyboard values are `physical_keycode`; joypad values are `JoyButton` indices or `axis`/`axis_value` pairs.

| Action | Keyboard / mouse | Joypad | Read by |
|--------|------------------|--------|---------|
| `move_forward` / `move_back` / `move_left` / `move_right` | `W` / `S` / `A` / `D`, deadzone 0.2 | left stick axes 0/1 | `locomotion.gd:93`, `dodge.gd:112` |
| `sprint` | `Shift` | button 8 (right stick click) | `locomotion.gd:96`, `:191` |
| `jump` | `F` | button 0 (A) | `dodge.gd:84` |
| `dodge` | `Space` | button 1 (B) | `dodge.gd:59` |
| `light_attack` | left mouse | axis 5 (right trigger) | `weapon_controller.gd:129`, `:379`, `:396` |
| `heavy_attack` | right mouse | button 3 (Y) | `weapon_controller.gd:131`, `:381`, `:391` |
| `block` | `Q` | axis 4 (left trigger) | `guard.gd:64`, `:71`, `weapon_controller.gd:379` |
| `lock_on` | `Enter`, middle mouse | button 5 (Guide) | `lock_on.gd:47` |
| `pause` | `Escape` | button 6 (Start) | `player_controls.gd:141` |
| `zoom_in` / `zoom_out` | wheel up / wheel down | buttons 11 / 12 (D-pad up/down) | `orbit_camera.gd:62-65` |
| `look_left` / `look_right` / `look_up` / `look_down` | none | right stick axes 2/3, deadzone 0.15 | `orbit_camera.gd:71`, `lock_on.gd:194`, `orbit_camera.gd:166` |
| `toggle_camera` | `P` | none | `orbit_camera.gd:59` |
| `inventory` | `Tab` | button 4 (Back) | `inventory_ui.gd:225` |
| `talents` | `K` | button 7 (left stick click) | `talents_ui.gd:64` |
| `heal` | `H` | button 7 (left stick click) | `player_heal.gd:35` |
| `interact` | `E` | button 2 (X) | hub and dungeon interactables |
| `two_hand` | `V` | none | `weapon_controller.gd:122` |
| `weapon_art` | `C` | button 10 (right shoulder) | `weapon_controller.gd:124` |
| `quick_slot_1..3` | `1` / `2` / `3` | none | `player_controls.gd:159-163` |
| `debug_toggle` / `debug_hitboxes` / `toggle_damage_numbers` | `F1` / `F2` / `F3` | none | debug overlay |
| `reset_duel` | `R` | button 9 (left shoulder) | debug arenas |

Mouse look is not an action: `orbit_camera.gd:51-56` consumes raw `InputEventMouseMotion` while `Input.get_mouse_mode() == MOUSE_MODE_CAPTURED`. Lock-on target cycling consumes raw `MOUSE_BUTTON_WHEEL_UP` / `WHEEL_DOWN` (`lock_on.gd:51-56`).

## Contracts

- Autoload name `PlayerControls` (`project.godot:49`). Consumers: `hub.gd:176` and `:222`, `pause_menu.gd:82`, `main_menu.gd:88`/`:110`/`:145`/`:212-213`, `combat_arena.gd:42`, `lock_on.gd:416`.
- Public API: `sync_player_loadout()`, `uses_main_inventory()`, `get_inventory_ui()`, `get_settings_ui()`, `get_talents_ui()`, `get_loadout_ui()`, `open_settings()`, `open_loadout()`, `is_inventory_open()`, `is_settings_open()`, `is_talents_open()`, `is_loadout_open()`, `is_pause_open()`, `is_player_meta_ui_open()`.
- Each routed UI must implement `is_open()`; the inventory must also implement `_bind_inventory_context()`; the loadout must implement `open()`.
- Scene authors must not add nodes named `InventoryUI`, `SettingsUI`, `TalentsUI`, `LoadoutUI`, or `PauseMenu` to a gameplay scene — they are deleted on scene entry (`player_controls.gd:63`).
- `Escape` is bound to both `pause` and `ui_cancel`. Correct behaviour depends on the open UI consuming the event with `set_input_as_handled()` before `PlayerControls._unhandled_input` runs.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Pause routing and quick-slot polling | IMPLEMENTED | `player_controls.gd:140`, `:154` |
| Duplicate scene-UI cleanup | IMPLEMENTED | `player_controls.gd:59` |
| Appearance refresh after scene change | BROKEN | `player_controls.gd:75` looks up child node `Locomotion`; `locomotion.gd` is on the root `Player` node itself (`apps/game/client/scenes/player/player.tscn:36-38`), so the lookup returns `null` and `refresh_appearance_visual()` never runs |
| Equipment move-speed bonus | BROKEN | Same dead `"Locomotion"` lookup in `apps/game/client/scripts/inventory/inventory_service.gd:206`; `waves_run_service.gd:317` uses `player as CharacterBody3D` and works |
| Gameplay lockout while a meta UI is open | PARTIAL | `is_player_meta_ui_open()` is consulted only by `player_controls.gd:155` and `hub.gd:222`; `locomotion.gd:93`, `dodge.gd:59`, `weapon_controller.gd:129`, `guard.gd:64`, `player_heal.gd:35` poll `Input` regardless, so the player still walks, attacks, dodges, and drinks with the inventory open |
| `talents` / `heal` joypad binding | BROKEN | Both bound to `button_index: 7` (`project.godot:274`, `:286`) |
| `lock_on` joypad binding | PARTIAL | `button_index: 5` is `JOY_BUTTON_GUIDE` (`project.godot:183`) |
| `lock_on` keyboard binding | PARTIAL | `Enter` is also `ui_accept` (`project.godot:85`, `:181`) |
| `zoom_in` / `zoom_out` joypad binding | PARTIAL | D-pad up/down, also `ui_up`/`ui_down` (`project.godot:110`, `:116`, `:195`, `:201`) |
| Gamepad coverage for `toggle_camera`, `two_hand`, `quick_slot_1..3` | ABSENT | No joypad event in those action blocks (`project.godot:245`, `:289`, `:256-269`) |
| Input remapping, mouse sensitivity, invert-Y | ABSENT | No `InputMap` mutation anywhere under `apps/game/client/scripts/`; `MOUSE_SENSITIVITY`, `STICK_SENSITIVITY`, and `INVERT_Y` are `const` (`orbit_camera.gd:3-4`, `:12`) and `accessibility_settings.gd` exposes only `ui_scale`, `reduce_camera_shake`, `colorblind_mode`, `subtitle_scale`, `vibration_intensity` |

## Related
- Improvement plan: [`../actual_improvements/player-controls.md`](../actual_improvements/player-controls.md)
- [`locomotion.md`](locomotion.md), [`player-heal.md`](player-heal.md), [`orbit-camera.md`](orbit-camera.md), [`lock-on.md`](lock-on.md)
- [`ui/inventory_ui.md`](ui/inventory_ui.md), [`ui/pause_menu.md`](ui/pause_menu.md), [`ui/talents.md`](ui/talents.md), [`ui/settings.md`](ui/settings.md), [`ui/input_glyphs.md`](ui/input_glyphs.md)
