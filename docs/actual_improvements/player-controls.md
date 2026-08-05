# Player controls — improvement plan

## Current state

`PlayerControls` (`apps/game/client/scripts/app/player_controls.gd`) is the autoloaded meta UI router: it builds `InventoryUI`, `SettingsUI`, `TalentsUI`, `PauseMenu`, and `LoadoutUI`, deletes scene-local duplicates on every scene change, routes the `pause` action, and polls three quick slots. It is not a movement or combat controller — see [`../existing_codebase/player-controls.md`](../existing_codebase/player-controls.md).

Two things are wrong at the seam. `sync_player_loadout()` reaches for a child node named `Locomotion` that does not exist, so appearance refresh and equipment move-speed never apply. And nothing suppresses gameplay input while a meta UI is open: `PlayerControls.is_player_meta_ui_open()` exists but only `hub.gd:222` and `player_controls.gd:155` call it, so the player keeps walking, attacking, dodging, and drinking with the inventory open. The input map itself has three binding collisions and no remapping path.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PCT-01 | P0 | `sync_player_loadout()` looks up the child node `"Locomotion"`, which does not exist — `locomotion.gd` is the script on the root `Player` node. `refresh_appearance_visual()` is therefore never called after a scene change | `player_controls.gd:75-77`, `apps/game/client/scenes/player/player.tscn:36-38` |
| PCT-02 | P0 | The same dead lookup in `InventoryService` silently drops every equipment and talent move-speed bonus in hub and castle runs; only waves mode works, because it uses `player as CharacterBody3D` | `apps/game/client/scripts/inventory/inventory_service.gd:206-208` vs `apps/game/client/scripts/dungeon/waves_run_service.gd:317-320` |
| PCT-03 | P0 | Gameplay input is not suppressed while a meta UI is open. Movement, dodge, attack, guard, and heal all poll `Input` directly and none consults `is_player_meta_ui_open()` | `locomotion.gd:93`, `dodge.gd:59`, `weapon_controller.gd:129`, `guard.gd:64`, `player_heal.gd:35`; gate defined at `player_controls.gd:130-137` |
| PCT-04 | P1 | `talents` and `heal` are both bound to joypad `button_index: 7`. On a controller, pressing the left stick opens the talent tree and drinks a flask | `apps/game/client/project.godot:274`, `:286` |
| PCT-05 | P1 | `lock_on` is bound to joypad `button_index: 5` (`JOY_BUTTON_GUIDE`), which is captured by the OS and by Steam Input on most setups, and to `Enter`, which is also `ui_accept` | `project.godot:181-183`, `:85` |
| PCT-06 | P1 | `zoom_in` / `zoom_out` are bound to D-pad up/down, which are also `ui_up` / `ui_down` | `project.godot:110`, `:116`, `:195`, `:201` |
| PCT-07 | P1 | No gamepad binding for `toggle_camera`, `two_hand`, or `quick_slot_1..3`; five actions are keyboard-only | `project.godot:245-249`, `:256-269`, `:289-293` |
| PCT-08 | P1 | No input remapping. `InputMap` is never mutated anywhere under `apps/game/client/scripts/`, and no save key stores bindings | absence across `scripts/`; `settings_ui.gd` has no input section |
| PCT-09 | P2 | Mouse sensitivity, stick sensitivity, and invert-Y are compile-time `const` | `apps/game/client/scripts/camera/orbit_camera.gd:3-4`, `:12` |
| PCT-10 | P2 | Quick slots are polled in `_process` and hardcoded to three, so the presses cannot be consumed by a focused UI and there is no activation feedback | `player_controls.gd:154-164` |

## Target design

**One player-input authority.** Add `PlayerControls.gameplay_input_blocked() -> bool` returning `is_player_meta_ui_open() or get_tree().paused`. Every player script that polls `Input` gains one early return through a shared static helper so the check is spelled once:

```gdscript
# scripts/app/player_input.gd  (class_name PlayerInput, static only)
static func blocked() -> bool:
	return PlayerControls != null and PlayerControls.gameplay_input_blocked()

static func move_vector() -> Vector2:
	return Vector2.ZERO if blocked() else Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)

static func pressed(action: StringName) -> bool:
	return false if blocked() else Input.is_action_pressed(action)

static func just_pressed(action: StringName) -> bool:
	return false if blocked() else Input.is_action_just_pressed(action)
```

Chosen over pausing the tree on inventory open: pausing would also freeze `AudioDirector` crossfades, VFX pools, and the pixel viewport mirror, and the hub explicitly expects to keep simulating while the loadout is open (`hub.gd:222`). Chosen over `set_process_input(false)`: the scripts poll rather than handle events, so disabling `_input` would change nothing.

**Player node resolution.** Replace both `get_node_or_null("Locomotion")` sites with a single helper on `PlayerControls`:

```gdscript
static func resolve_locomotion(player: Node) -> Node:
	if player == null:
		return null
	if player.has_method("set_speed_multiplier"):
		return player
	return player.get_node_or_null("Locomotion")
```

Duck-typing on `set_speed_multiplier` keeps the helper working if the script is ever moved onto a child node.

**Input map.** A gamepad exposes 15 usable buttons (`JoyButton` 0-14 minus `5 = GUIDE`, which the OS and Steam Input capture) plus the two triggers. The full gameplay set is assigned below with no collisions and no chords. Rows in bold are the changes from today's map.

| Action | Keyboard / mouse | Gamepad |
|--------|------------------|---------|
| `move_forward` / `back` / `left` / `right` | `W` / `S` / `A` / `D` | left stick, axes 0/1 |
| **`sprint`** | `Shift` | **`9` left shoulder** |
| `jump` | `F` | `0` A |
| `dodge` | `Space` | `1` B |
| `light_attack` | left mouse | axis 5, right trigger |
| `heavy_attack` | right mouse | `3` Y |
| `block` | `Q` | axis 4, left trigger |
| **`lock_on`** | **middle mouse, `T`** | **`8` right stick click** |
| `pause` | `Escape` | `6` Start |
| `inventory` | `Tab` | `4` Back |
| **`talents`** | `K` | **`11` D-pad up** |
| `heal` | `H` | `7` left stick click |
| `interact` | `E` | `2` X |
| **`two_hand`** | `V` | **`12` D-pad down** |
| `weapon_art` | `C` | `10` right shoulder |
| `quick_slot_1..3` | `1` / `2` / `3` | none, replaced by the two actions below |
| **`quick_slot_cycle`** (new) | `Alt` | **`13` D-pad left** |
| **`quick_slot_use`** (new) | none | **`14` D-pad right** |
| `toggle_camera` | `P` | none, keyboard-only by design |
| `zoom_in` / `zoom_out` | wheel up / down | none, keyboard-only by design |

Three actions stay keyboard-and-mouse only because the button budget is exhausted: `toggle_camera`, `zoom_in`, `zoom_out`. They are declared in an explicit `InputBindings.KEYBOARD_ONLY` set so the gamepad-coverage assertion is exact rather than approximate, and the camera view mode is also togglable from the Settings menu. `lock_on` leaves `Enter` (which is `ui_accept`) and `GUIDE`; `sprint` vacates the left stick click so `heal` keeps it alone; the D-pad is freed for gameplay by removing zoom from it, which also ends the `ui_up`/`ui_down` collision.

**Remapping.** Add `scripts/app/input_bindings.gd` (`class_name InputBindings`, static):

- `REBINDABLE: Array[StringName]` — the 20 gameplay actions, excluding `ui_*` and `debug_*`.
- `load_from_save()` reads `LocalSave.get_meta_data()["input_bindings"]`, a dictionary of `action -> Array[Dictionary]` where each entry is `{"type": "key"|"mouse"|"joy_button"|"joy_axis", "code": int, "value": float}`.
- `apply()` calls `InputMap.action_erase_events(action)` then `action_add_event` per entry; actions absent from the save keep their `project.godot` defaults.
- `conflicts() -> Dictionary` maps a device-scoped event signature to the list of actions claiming it, so the settings UI can show the collision inline and CI can assert emptiness.
- `save()` writes back and calls `LocalSave.autosave()`.

`PlayerControls._ready` calls `InputBindings.load_from_save()` and `apply()` immediately after `AccessibilitySettings.load_from_save()`.

**Camera feel settings.** Move `MOUSE_SENSITIVITY`, `STICK_SENSITIVITY`, and `INVERT_Y` out of `orbit_camera.gd` into `AccessibilitySettings` as `mouse_sensitivity: float = 1.0` (multiplier on a `0.003` base, range `0.25`–`4.0`), `stick_sensitivity: float = 1.0` (on a `2.5` base, same range), `invert_look_y: bool = false`. `orbit_camera` reads them per event.

## Work plan

1. **Fix the player node lookup.** Add `PlayerControls.resolve_locomotion(player)`; use it at `player_controls.gd:75` and `inventory_service.gd:206`. Closes PCT-01, PCT-02.
2. **Add `scripts/app/player_input.gd`** with `blocked()`, `move_vector()`, `pressed()`, `just_pressed()`, and `PlayerControls.gameplay_input_blocked()`. No call sites yet; the game is unchanged.
3. **Route player scripts through `PlayerInput`.** Replace the `Input.` calls at `locomotion.gd:93`, `:96`, `:191`, `:204`; `dodge.gd:59`, `:84`, `:112`; `weapon_controller.gd:122`, `:124`, `:129`, `:131`, `:379`, `:381`, `:391`, `:396`; `guard.gd:64`, `:71`; `player_heal.gd:35`. Leave `orbit_camera.gd` and `lock_on.gd` on raw `Input` — they already gate on mouse mode and `_is_ui_focused()`. Closes PCT-03.
4. **Rewrite the `[input]` block** in `project.godot` per the table above. Closes PCT-04 through PCT-07.
5. **Add `scripts/app/input_bindings.gd`** and call it from `PlayerControls._ready`. Closes PCT-08.
6. **Add the Rebind section to `settings_ui.gd`**: one row per `REBINDABLE` action showing the current glyph via `InputGlyphService`, a listen-for-input button, a Reset button, and an inline conflict warning fed by `InputBindings.conflicts()`.
7. **Add camera feel settings.** Extend `AccessibilitySettings` with the three fields, add sliders and a checkbox to `settings_ui.gd`, and read them in `orbit_camera.gd`. Closes PCT-09.
8. **Rework quick slots.** Move activation from `_process` to `_unhandled_input`, mark the event handled, extend to four slots, and emit a `quick_slot_used(index, item_id)` signal for the HUD to flash. Closes PCT-10.

## Data and schema changes

- `LocalSave` meta gains `input_bindings: Dictionary` and three `accessibility` keys (`mouse_sensitivity`, `stick_sensitivity`, `invert_look_y`). Both live in the meta blob, which `local_save.gd` already round-trips untyped, so **no `save_migrator.gd` version bump is required**; absent keys fall back to defaults in `load_from_save()`.
- No `content/schemas/` change: bindings are user data, not content.

## Acceptance criteria

- [ ] Equipping a `moveSpeedPercent` item in the hub changes measured player speed; the same item in waves mode changes it by the same factor. (PCT-01, PCT-02)
- [ ] Changing appearance and returning to the hub rebuilds the rig without a scene reload. (PCT-01)
- [ ] With the inventory, talents, loadout, or settings UI open, holding `W`, `Shift`, `Space`, left mouse, `Q`, and `H` produces no velocity change, no dodge, no attack, no guard, and no charge spend. (PCT-03)
- [ ] `InputBindings.conflicts()` returns an empty dictionary for the shipped `project.godot` map. (PCT-04, PCT-05, PCT-06)
- [ ] Every action in `InputBindings.REBINDABLE` has at least one keyboard-or-mouse event, and every action not in `InputBindings.KEYBOARD_ONLY` also has at least one gamepad event. (PCT-07)
- [ ] A rebind survives an application restart. (PCT-08)
- [ ] Mouse sensitivity at `0.25` and at `4.0` produces a 16x difference in yaw per pixel of motion; invert-Y flips the pitch sign. (PCT-09)
- [ ] A quick-slot press while the inventory has focus does not consume a charge. (PCT-10)

## Validation

Extend `apps/game/client/scripts/validation/suites/setup_suite.gd`:

- `input.no_binding_conflicts` — `InputBindings.conflicts().is_empty()`.
- `input.gamepad_coverage` — every `REBINDABLE` action outside `KEYBOARD_ONLY` has a joypad event.
- `input.rebindable_actions_exist` — every entry in `REBINDABLE` satisfies `InputMap.has_action`.
- `input.bindings_roundtrip` — back up the save, rebind `dodge` to `KEY_C`, `apply()`, assert `InputMap.action_has_event`, restore.

Extend `apps/game/client/scripts/validation/suites/player_suite.gd`:

- `player.locomotion_resolves_from_root` — `PlayerControls.resolve_locomotion(player) == player` for an instanced `player.tscn`.
- `player.move_speed_multiplier_applies` — set a multiplier of `2.0`, drive `PlayerInput.move_vector` through a stub, and assert the achieved steady-state speed is `9.0` m/s within 0.2.
- `player.input_blocked_when_meta_ui_open` — force `PlayerControls` to report a UI open, then assert `PlayerInput.move_vector() == Vector2.ZERO` and `PlayerInput.just_pressed(&"dodge") == false`.

## Related
- Existing state: [`../existing_codebase/player-controls.md`](../existing_codebase/player-controls.md)
- [`locomotion.md`](locomotion.md), [`player-heal.md`](player-heal.md), [`orbit-camera.md`](orbit-camera.md), [`lock-on.md`](lock-on.md)
- [`ui/input_glyphs.md`](ui/input_glyphs.md), [`ui/settings.md`](ui/settings.md), [`ui/inventory_ui.md`](ui/inventory_ui.md), [`accessibility.md`](accessibility.md), [`local-save.md`](local-save.md)
