# Player controls — improvement plan

## Status: FINISHED

## Current state

`PlayerControls` (`apps/game/client/scripts/app/player_controls.gd`) is the autoloaded meta UI router: it builds `InventoryUI`, `SettingsUI`, `TalentsUI`, `PauseMenu`, and `LoadoutUI`, deletes scene-local duplicates on every scene change, routes the `pause` action, and handles quick-slot input in `_unhandled_input`. Gameplay polling goes through `PlayerInput` (`apps/game/client/scripts/app/player_input.gd`), which gates on `PlayerControls.gameplay_input_blocked()`. Input remapping is handled by `InputBindings` (`apps/game/client/scripts/app/input_bindings.gd`) with overrides stored in `LocalSave` meta. See [`../existing_codebase/player-controls.md`](../existing_codebase/player-controls.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| PCT-01 | P0 | `sync_player_loadout()` looked up child `"Locomotion"` instead of the root player node | `player_controls.gd:75` | FINISHED |
| PCT-02 | P0 | Equipment move-speed bonus dropped by the same dead lookup in `InventoryService` | `inventory_service.gd:206` | FINISHED |
| PCT-03 | P0 | Gameplay input not suppressed while meta UI open | `locomotion.gd`, `dodge.gd`, `weapon_controller.gd`, `guard.gd`, `player_heal.gd` | FINISHED |
| PCT-04 | P1 | `talents` and `heal` joypad collision on button 7 | `project.godot` | FINISHED |
| PCT-05 | P1 | `lock_on` on GUIDE and Enter/`ui_accept` | `project.godot` | FINISHED |
| PCT-06 | P1 | `zoom_in`/`zoom_out` on D-pad colliding with `ui_up`/`ui_down` | `project.godot` | FINISHED |
| PCT-07 | P1 | Missing gamepad bindings for `toggle_camera`, `two_hand`, quick slots | `project.godot` | FINISHED |
| PCT-08 | P1 | No input remapping path | `settings_ui.gd`, `input_bindings.gd` | FINISHED |
| PCT-09 | P2 | Mouse/stick sensitivity and invert-Y compile-time constants | `orbit_camera.gd`, `accessibility_settings.gd` | FINISHED |
| PCT-10 | P2 | Quick slots polled in `_process`, three slots, no consume/feedback | `player_controls.gd` | FINISHED |

## Target design

**One player-input authority.** `PlayerControls.gameplay_input_blocked() -> bool` returns `is_player_meta_ui_open() or get_tree().paused`. Every player script that polled `Input` now uses `PlayerInput.blocked()`, `move_vector()`, `pressed()`, and `just_pressed()`.

**Player node resolution.** `PlayerControls.resolve_locomotion(player)` duck-types on `set_speed_multiplier` and falls back to child `Locomotion`.

**Input map.** Shipped `project.godot` bindings match the target table: `sprint` on left shoulder (9), `lock_on` on middle mouse / `T` / right-stick click (8), `talents` on D-pad up (11), `heal` on left-stick click (7), `two_hand` on D-pad down (12), `quick_slot_cycle` on Alt / D-pad left (13), `quick_slot_use` on D-pad right (14). `toggle_camera`, `zoom_in`, `zoom_out`, and keyboard quick slots remain keyboard-only via `InputBindings.KEYBOARD_ONLY`.

**Remapping.** `InputBindings` (`class_name InputBindings`) provides `REBINDABLE`, `KEYBOARD_ONLY`, `load_from_save()`, `apply()`, `conflicts()`, `save()`, and UI helpers. Overrides live in `LocalSave` meta key `input_bindings`. `PlayerControls._ready` calls `InputBindings.snapshot_defaults()`, `load_from_save()`, and `apply()` after `AccessibilitySettings.load_from_save()`. `InputRebindService` autoload delegates to `InputBindings` for settings UI compatibility.

**Camera feel settings.** `AccessibilitySettings` exposes `mouse_sensitivity`, `stick_sensitivity`, and `invert_look_y`. `orbit_camera.gd` reads them per event (base `0.003` / `2.5`, multiplier range `0.25`–`4.0`).

## Work plan

1. **Fix the player node lookup.** — `PlayerControls.resolve_locomotion()`, `inventory_service.gd`, `player_controls.gd`. Closes PCT-01, PCT-02.
2. **Add `scripts/app/player_input.gd`** — `blocked()`, `move_vector()`, `pressed()`, `just_pressed()`, `gameplay_input_blocked()`.
3. **Route player scripts through `PlayerInput`.** — `locomotion.gd`, `dodge.gd`, `weapon_controller.gd`, `guard.gd`, `player_heal.gd`. Closes PCT-03.
4. **Rewrite `[input]` in `project.godot`** per target table. Closes PCT-04 through PCT-07.
5. **Add `scripts/app/input_bindings.gd`** and call from `PlayerControls._ready`. Closes PCT-08.
6. **Rebind section in `settings_ui.gd`** — rows per `REBINDABLE` action, conflict warning from `InputBindings.conflicts()`.
7. **Camera feel settings** — `AccessibilitySettings`, `settings_ui.gd`, `orbit_camera.gd`. Closes PCT-09.
8. **Rework quick slots** — `_unhandled_input`, four slots, `quick_slot_used` signal. Closes PCT-10.

## Data and schema changes

- `LocalSave` meta gains `input_bindings: Dictionary` and three `accessibility` keys (`mouse_sensitivity`, `stick_sensitivity`, `invert_look_y`). No `save_migrator.gd` version bump; absent keys fall back in `load_from_save()`.
- No `content/schemas/` change.

## Acceptance criteria

- [x] Equipping a `moveSpeedPercent` item in the hub changes measured player speed; the same item in waves mode changes it by the same factor. (PCT-01, PCT-02)
- [x] Changing appearance and returning to the hub rebuilds the rig without a scene reload. (PCT-01)
- [x] With the inventory, talents, loadout, or settings UI open, holding `W`, `Shift`, `Space`, left mouse, `Q`, and `H` produces no velocity change, no dodge, no attack, no guard, and no charge spend. (PCT-03)
- [x] `InputBindings.conflicts()` returns an empty dictionary for the shipped `project.godot` map. (PCT-04, PCT-05, PCT-06)
- [x] Every action in `InputBindings.REBINDABLE` has at least one keyboard-or-mouse event, and every action not in `InputBindings.KEYBOARD_ONLY` also has at least one gamepad event. (PCT-07)
- [x] A rebind survives an application restart. (PCT-08)
- [x] Mouse sensitivity at `0.25` and at `4.0` produces a 16x difference in yaw per pixel of motion; invert-Y flips the pitch sign. (PCT-09)
- [x] A quick-slot press while the inventory has focus does not consume a charge. (PCT-10)

## Validation

Extended `apps/game/client/scripts/validation/suites/setup_suite.gd`:

- `input.no_binding_conflicts` — `InputBindings.conflicts().is_empty()`.
- `input.gamepad_coverage` — every `REBINDABLE` action outside `KEYBOARD_ONLY` has a joypad event.
- `input.rebindable_actions_exist` — every entry in `REBINDABLE` satisfies `InputMap.has_action`.
- `input.bindings_roundtrip` — back up save, rebind `dodge` to `KEY_C`, `apply()`, assert `InputMap.action_has_event`, restore.

Extended `apps/game/client/scripts/validation/suites/player_suite.gd`:

- `player.locomotion_resolves_from_root` — `PlayerControls.resolve_locomotion(player) == player` for an instanced `player.tscn`.
- `player.move_speed_multiplier_applies` — set multiplier `2.0`, drive movement, assert steady-state speed `9.0` m/s within `0.2`.
- `player.input_blocked_when_meta_ui_open` — force inventory open, assert `PlayerInput.move_vector() == Vector2.ZERO` and `PlayerInput.just_pressed(&"dodge") == false`.

## Related
- Existing state: [`../existing_codebase/player-controls.md`](../existing_codebase/player-controls.md)
- [`locomotion.md`](locomotion.md), [`player-heal.md`](player-heal.md), [`orbit-camera.md`](orbit-camera.md), [`lock-on.md`](lock-on.md)
- [`ui/input_glyphs.md`](ui/input_glyphs.md), [`ui/settings.md`](ui/settings.md), [`ui/inventory_ui.md`](ui/inventory_ui.md), [`accessibility.md`](accessibility.md), [`local-save.md`](local-save.md)
