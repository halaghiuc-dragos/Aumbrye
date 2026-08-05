# Entry flow — title, main menu, continue

How the three front-end surfaces hand off to each other and into the hub. Individual screens are documented in [`title_screen.md`](title_screen.md), [`main_menu.md`](main_menu.md), and [`continue_menu.md`](continue_menu.md); this topic records what they share.

## Scene graph of the entry path
```
project.godot:19  run/main_scene = res://scenes/ui/title_screen.tscn
        │  any key / mouse / pad button  (title_screen.gd:126-138)
        ▼
scenes/ui/main_menu.tscn
        ├─ New Game ──▶ CharacterCreateUI  (child node, in-place; main_menu.gd:25-27)
        │                     completed ──▶ LocalSave.queue_boot_new_game (:177)
        ├─ Continue ──▶ ContinueMenu       (child node, in-place; main_menu.gd:30-32)
        │                     slot_selected ──▶ LocalSave.queue_boot_continue_character (:188)
        ├─ Settings ──▶ PlayerControls.open_settings()  (autoload overlay; :143-145)
        └─ Quit ──────▶ get_tree().quit()               (:163)
        │
        ▼  change_scene_to_file  (:178, :189)
scenes/ui/loading_screen.tscn
        │  await 1.1 s, then LocalSave.execute_boot()   (loading_screen.gd:47-62)
        ├─ failure ──▶ back to main_menu.tscn after 1.2 s  (:55-59)
        ▼  success
scenes/hub/hub.tscn
```

The post-run path re-enters through `RunFlow.return_to_hub` from `results_screen.gd:88-91`, not through this flow.

## Shared boot work, duplicated per screen
| Call | `title_screen.gd` | `main_menu.gd` | `settings_ui.gd` |
|---|---|---|---|
`AccessibilitySettings.load_from_save()` | `:14` | `:19` | `:22` |
`DisplaySettings.apply()` | `:15` | `:20` | `:23` |
`AudioSettings.load_from_save()` | — | `:21` | `:25` |
`PixelDioramaSettings.load_from_save()` | — | — | `:26` |
`LeaderboardSettings.load_from_save()` | — | — | `:24` |
`PixelDioramaBootstrap.prime()` | `:16` | — | — |
`AudioDirector.play_menu_music()` | `:17` | `:22` | — |

`player_controls.gd:17-18` also calls `AccessibilitySettings.load_from_save()` and `DisplaySettings.apply()` in its own `_ready`. There is no single boot entry point; five scripts each load some subset of the settings singletons.

## The deferred-boot handshake
Neither the character creator nor the continue menu loads a save. Both stash intent on `LocalSave` and change scene:

| Producer | Call | Consumer |
|---|---|---|
`main_menu.gd:177` | `LocalSave.queue_boot_new_game(class_id, name, appearance)` | `LocalSave.execute_boot()` at `loading_screen.gd:54` |
`main_menu.gd:188` | `LocalSave.queue_boot_continue_character(character_id)` | same |
`local_save.gd:190` | `queue_boot_continue_backup(index)` | same — no UI producer calls it; the settings backup path uses `restore_backup` instead (`settings_ui.gd:405`) |

`execute_boot()` dispatches on `_boot_mode` (`local_save.gd:195-206`). If nothing was queued, the mode is `BootMode.NONE`, which falls through the `match`.

## Global overlays present in the front end
`PlayerControls` is autoload 49 (`project.godot:49`), so `InventoryUI`, `SettingsUI`, `TalentsUI`, `PauseMenu`, and `LoadoutUI` all exist on the title screen and main menu. Their `_unhandled_input` handlers are live there:

| Script | Trigger | Guarded against the front end? |
|---|---|---|
`inventory_ui.gd:225` | `inventory` action (Tab / pad button 4) | no |
`talents_ui.gd:64` | `talents` action (K / pad button 7) | no |
`player_controls.gd:140-151` | `pause` action | no; the title and main menu both consume Escape first via their own handlers |
`settings_ui.gd:545-551` | `ui_cancel` or `pause` | it is the shared settings overlay for both the front end and gameplay |

## Escape is two actions
`ui_cancel` (`project.godot:89-94`) and `pause` (`:186-191`) are both bound to physical keycode `4194305`. Eight scripts check one, two check both (`pause_menu.gd:71`, `settings_ui.gd:548`), and `main_menu.gd:200` uses `_input` so it sees Escape before anything else.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Title to main menu to hub path works | IMPLEMENTED | `title_screen.gd:122-123`, `main_menu.gd:178`, `loading_screen.gd:62` |
| Boot-intent handshake through `LocalSave` | IMPLEMENTED | `main_menu.gd:177`, `:188`; `local_save.gd:195-206` |
| Boot-failure fallback | PARTIAL — the loading screen shows `"Could not load save — returning to menu."` for 1.2 s, then the main menu opens with no record of the failure | `loading_screen.gd:55-59` |
| Scene transitions | ABSENT — three bare `change_scene_to_file` calls with no fade, no loading of the next scene in the background | `title_screen.gd:123`, `main_menu.gd:178`, `:189`, `loading_screen.gd:58`, `:62` |
| Single boot entry point | ABSENT — settings-singleton loading is duplicated across five scripts with different subsets | table above |
| Loading screen duration | PARTIAL — a hardcoded `MIN_DISPLAY_SEC = 1.1` await before any work starts, so entry always costs at least 1.1 s regardless of actual load time | `loading_screen.gd:7`, `:51-53` |
| Loading progress | PLACEHOLDER — three fixed status strings (`"Preparing your warden..."`, `"Syncing echo..."`, `"Opening the hub..."`), no progress bar and no real progress source | `loading_screen.gd:41`, `:52`, `:60` |
| Front-end overlay isolation | BROKEN — the global inventory and talents overlays respond to their actions on the title screen and main menu, where there is no player, no run, and no inventory context | `inventory_ui.gd:225` and `talents_ui.gd:64` have no scene or run-mode guard |
| Settings hint correctness | BROKEN — the shared settings overlay always shows `"Esc: back to main menu"`, including when opened from the in-run pause menu | `settings_ui.gd:44`; opened from `pause_menu.gd:80-82` |
| Escape action duplication | PARTIAL — `ui_cancel` and `pause` share Escape, and precedence depends on `_input` vs `_unhandled_input` and tree order | `project.godot:91`, `:188`; `main_menu.gd:200` vs eight `_unhandled_input` handlers |
| Music continuity | PARTIAL — both the title screen and the main menu call `play_menu_music()`, so the track is re-triggered on the transition | `title_screen.gd:17`, `main_menu.gd:22` |
| Cancel from the loading screen | ABSENT — no back or cancel affordance once boot has started | `loading_screen.gd:47-62` |
| `queue_boot_continue_backup` | STUB — implemented on `LocalSave` (`:190-192`) with no UI caller anywhere | 0 callers outside `local_save.gd` |
| Focus continuity across the flow | BROKEN — the title screen has no focusable control, and the main menu, continue menu, and character creator focus nothing, so the entry path cannot be completed on a gamepad | see [`menu_shell_a11y.md`](menu_shell_a11y.md) |
| Save selection in the flow | PARTIAL — the continue menu is the only place a warden is chosen; the main menu's Continue button is a binary enabled/disabled with no indication of which warden | `main_menu.gd:95-98` |

## Related
- Improvement plan: [`../actual_improvements/ui/title_main_continue.md`](../actual_improvements/ui/title_main_continue.md)
- Per-screen docs: [`title_screen.md`](title_screen.md) · [`main_menu.md`](main_menu.md) · [`continue_menu.md`](continue_menu.md) · [`character_create.md`](character_create.md) · [`run_outcome.md`](run_outcome.md)
- [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`settings.md`](settings.md)
- [`../local-save.md`](../local-save.md) · [`../run-flow.md`](../run-flow.md) · [`../player-controls.md`](../player-controls.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md)
