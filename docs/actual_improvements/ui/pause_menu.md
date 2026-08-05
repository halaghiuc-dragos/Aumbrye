# Pause menu — improvement plan

## Current state
`pause_menu.gd` builds its panel once in `_ready`, which runs during `PlayerControls`' autoload initialization. Because `RunFlow.is_run_active()` is necessarily false at that moment, the Abandon run button is never created (`:62-63`). Nothing is focused on open, so with the tree paused the only working input is Escape. Opening settings from here and closing it captures the mouse while the pause menu is still up. The `closed` signal has no listeners. Eight strings are hardcoded English, and the panel shows no information about the run being paused. See [`../existing_codebase/ui/pause_menu.md`](../existing_codebase/ui/pause_menu.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PSE-01 | P0 | Abandon run is unreachable. `_build_ui` is called from `_ready` at autoload time and gates the button on `RunFlow.is_run_active()`, which is false then and is never re-evaluated. | `:17` → `:52-65`; gate at `:62-63`; built at `player_controls.gd:28` during autoload init; `run_flow.gd:675-676` returns `_run_active`, initialized false |
| PSE-02 | P0 | The pause menu is mouse-only. No `grab_focus`, no neighbors, and the tree is paused, so a controller player can only close it again with Escape or pad button 6. | `:31-38`, `:60-64`; 0 `grab_focus` matches |
| PSE-03 | P0 | Returning from settings captures the mouse while the pause menu is still visible and the tree is still paused, because `settings_ui.close_settings` captures whenever a player node exists. | `:80-82`; `settings_ui.gd:534-542` |
| PSE-04 | P1 | The Abandon confirmation is parented to the pause menu and only hidden when the pause menu closes, so Escape during the confirmation closes the pause menu and leaves a stale overlay for the next open. | `menu_shell.gd:101`; `:41-49`, `:68-73` |
| PSE-05 | P1 | The panel shows nothing about the run: no floor, elapsed time, seed, run mode, or objective, which is the information a player pauses to check. | `:52-65` |
| PSE-06 | P1 | Zero localization across eight strings, including both confirmation bodies. | `:55`, `:60-65`, `:88-95`, `:102-109` |
| PSE-07 | P2 | The `closed` signal is declared and emitted with no listener. | `:5`, `:49`; 0 connections in the client |
| PSE-08 | P2 | `"Esc to resume"` hardcodes the key name and is wrong on a gamepad. | `:65` |
| PSE-09 | P2 | No audio treatment on pause: music and ambience continue at full level and no pause sting plays. | `:31-49` has no `AudioDirector` call |
| PSE-10 | P2 | No restart-run action, so a player who wants a fresh attempt must abandon, walk back to the portal, and re-enter. | `:60-64` |
| PSE-11 | P2 | The node exists in the front end, where it is only unreachable by accident of Escape precedence. | `project.godot:49`; `main_menu.gd:200-219` uses `_input` |

## Target design

### Rebuild on open, not on ready
`_build_ui` moves out of `_ready` into `open_menu()` behind a dirty flag, and the run-dependent rows are rebuilt every time:

```gdscript
func open_menu() -> void:
    if _open: return
    _rebuild_actions()          # reads RunFlow state now, not at autoload time
    ...
    _initial_focus.grab_focus()
```

`_rebuild_actions()` decides the button set from live state:

| Condition | Buttons |
|---|---|
`RunFlow.is_run_active()` and mode is castle | Resume, Restart floor, Abandon run, Settings, Quit to menu |
`RunFlow.is_run_active()` and mode is waves | Resume, Leave waves, Settings, Quit to menu |
in the hub, no run active | Resume, Settings, Quit to menu |

The waves Leave entry replaces the copy currently buried in the settings overlay at `settings_ui.gd:438-462`, which is the wrong place for a run action (PSE-01, PSE-10).

Rejected alternative: keeping the build in `_ready` and toggling `visible` on the Abandon button. It works, but every future run-dependent row would need the same manual toggle; rebuilding from live state makes the class of bug impossible.

### Run context panel
```
ContentVBox
├── Label "TitleLabel"          MenuTitle — "Paused"
├── PanelContainer "RunInfo"    SectionFrame variation
│   └── GridContainer (2 columns)
│       ├── Label "ModeKey"    │ Label "ModeValue"      # Castle Run / Umbral Waves / Hub
│       ├── Label "FloorKey"   │ Label "FloorValue"     # floor n of m
│       ├── Label "TimeKey"    │ Label "TimeValue"      # elapsed mm:ss
│       ├── Label "SeedKey"    │ Label "SeedValue"      # run seed, selectable
│       └── Label "ObjKey"     │ Label "ObjValue"       # current objective
├── VBoxContainer "Actions"     # rebuilt per open
└── HintLabel                   # glyph + resume
```

Values come from `RunFlow` (`get_run_mode`, `is_run_active`), `DungeonSeedService` for the seed, and the objective source the HUD banner already uses (see [`combat_hud.md`](combat_hud.md)). `SeedValue` is a `LineEdit` in read-only `select_all_on_focus` mode so a player can copy a seed to share it (PSE-05).

### Focus and mouse ownership
- `initial_focus` is Resume.
- Vertical `VBoxContainer` order is the focus order; `RunInfo` labels are not focusable.
- The pause menu registers with `MenuStack`, which owns mouse mode. Closing settings pops one level and restores the pause menu's mouse mode instead of capturing the cursor, fixing PSE-03 structurally.
- `MenuStack` also routes `ui_cancel` to the top modal, so Escape during the Abandon confirmation dismisses only the confirmation (PSE-02, PSE-03, PSE-04).

### Confirmations
Abandon run and Quit to menu become `MenuStack.confirm(ConfirmSpec)` with `destructive = true`, so they honor `hold_to_confirm` and start focused on Cancel. Their bodies name what is lost using live numbers: `"Abandon floor {floor}? {n} items and {gold} gold from this run are lost."` from `RunFlow`'s loot accounting (`run_flow.gd:348`) (PSE-04, PSE-06).

### Restart floor
`RunFlow.restart_current_floor()` regenerates the current floor from the same seed, restores the player to the floor entrance, and keeps run loot. It is offered only in castle mode and only when the current floor has not been completed, with the reason in the hint otherwise (PSE-10).

### Front-end suppression
`toggle()` early-returns when `PlayerControls.allows_player_ui()` is false, so the pause menu is not merely unreachable in the front end but explicitly disabled (PSE-11; the gate itself is specified in [`title_main_continue.md`](title_main_continue.md)).

### Audio
`open_menu` calls `AudioDirector.set_pause_mix(true)`, which ducks music by `6` dB, mutes ambience and SFX buses, and plays a one-shot pause sting; `close_menu` restores. Bus names come from the existing `AudioSettings` bus layout (PSE-09).

### Signal cleanup and localization
`closed` gains a real consumer — `MenuStack` pops on it — or is deleted if the stack handles it directly (PSE-07). Keys: `PAUSE_TITLE`, `PAUSE_RESUME`, `PAUSE_SETTINGS`, `PAUSE_ABANDON`, `PAUSE_LEAVE_WAVES`, `PAUSE_RESTART_FLOOR`, `PAUSE_QUIT`, `PAUSE_HINT_RESUME`, `PAUSE_INFO_MODE`, `PAUSE_INFO_FLOOR`, `PAUSE_INFO_TIME`, `PAUSE_INFO_SEED`, `PAUSE_INFO_OBJECTIVE`, `PAUSE_CONFIRM_ABANDON_*`, `PAUSE_CONFIRM_QUIT_*`, plus mode names (PSE-06). The hint row uses `make_symbol_caption_row` with the `pause` glyph (PSE-08).

## Work plan
1. **Rebuild on open** — move `_build_ui` into `open_menu` behind a dirty flag, add `_rebuild_actions()` reading live `RunFlow` state, restoring Abandon run (PSE-01).
2. **Focus** — `initial_focus = Resume`, register with `MenuStack` (PSE-02).
3. **Mouse and cancel ownership** — remove the `Input.mouse_mode` assignments here and in `settings_ui.gd`, let `MenuStack` arbitrate (PSE-03, PSE-04).
4. **Run info panel** — mode, floor, time, seed, objective (PSE-05).
5. **Confirmations with live numbers** and destructive handling (PSE-04, PSE-06).
6. **Restart floor** — `RunFlow.restart_current_floor()` plus the button and its gating (PSE-10).
7. **Waves Leave entry** moved here from the settings overlay (PSE-01 support).
8. **Front-end suppression**, **audio mix**, **localization**, **signal cleanup** (PSE-07 … PSE-11).

## Data and schema changes
- `RunFlow`: new `restart_current_floor()`, and getters for elapsed run time and current objective if not already exposed.
- `AudioDirector`: new `set_pause_mix(bool)` and a pause sting cue.
- `settings_ui.gd`: the `WavesRunSection` at `:438-462` is removed; the action lives in the pause menu.
- `apps/game/client/translations/strings.csv`: the `PAUSE_*` keys above.
- No save-format change.

## Acceptance criteria
- [ ] Pausing during an active castle run shows Abandon run; pausing in the hub does not.
- [ ] Pausing during a waves run shows Leave waves, and `settings_ui.gd` no longer builds a waves section.
- [ ] Opening the pause menu focuses Resume; every button is reachable and pressable on a gamepad.
- [ ] Opening settings from the pause menu and closing it leaves the cursor visible and the pause menu focused.
- [ ] Escape during the Abandon confirmation dismisses only the confirmation and leaves the pause menu open.
- [ ] Reopening the pause menu after that never shows a stale confirmation.
- [ ] The run info panel shows the current mode, floor, elapsed time, seed, and objective, and the seed can be selected and copied.
- [ ] The Abandon confirmation body names the actual item count and gold at stake.
- [ ] Restart floor regenerates the same floor from the same seed and preserves run loot; it is absent in waves mode.
- [ ] `pause_menu.gd` contains no `Input.mouse_mode` assignment.
- [ ] The pause menu cannot be opened on the title screen or main menu.
- [ ] Pausing ducks music and mutes ambience; resuming restores both.
- [ ] Every visible string changes when the locale is switched to a stub translation.
- [ ] The resume hint shows the current `pause` glyph, not the literal `Esc`.

## Validation
Extend `apps/game/client/scripts/validation/suites/m7_suite.gd` and add `pause` cases:

| Test id | Assertion |
|---|---|
| `pause.abandon_present_in_run` | with `RunFlow` reporting an active castle run, the action list contains the abandon button |
| `pause.abandon_absent_in_hub` | with no active run, it does not |
| `pause.waves_leave_present` | in waves mode the action list contains Leave waves and `settings_ui.gd` contains no `WavesRunSection` |
| `pause.rebuild_per_open` | opening, entering a run, and reopening changes the action list without a scene reload |
| `pause.focus_on_open` | `gui_get_focus_owner()` is the Resume button |
| `pause.focus_graph` | BFS from Resume reaches every action button |
| `pause.settings_roundtrip_mouse` | open pause, open settings, close settings: `Input.mouse_mode == MOUSE_MODE_VISIBLE` and focus is inside the pause menu |
| `pause.cancel_scoped` | `ui_cancel` with a confirmation open closes only the confirmation; the pause menu remains `is_open()` |
| `pause.no_stale_overlay` | after that sequence, the tree contains no `ConfirmOverlay` |
| `pause.run_info_fields` | the info grid shows mode, floor, a `mm:ss` time, the seed from `DungeonSeedService`, and a non-empty objective |
| `pause.seed_copyable` | `SeedValue` is a read-only `LineEdit` with `select_all_on_focus` |
| `pause.confirm_body_numbers` | the abandon body contains the current loot count and gold |
| `pause.restart_floor_seed` | `restart_current_floor()` yields the same room graph seed and preserves `_loot_collected` |
| `pause.restart_absent_in_waves` | in waves mode there is no restart button |
| `pause.no_mouse_mode` | `pause_menu.gd` contains no `Input.mouse_mode` |
| `pause.front_end_suppressed` | with the current scene in the `front_end` group, `toggle()` leaves `is_open() == false` |
| `pause.audio_mix` | opening calls `set_pause_mix(true)`; closing calls it with `false` |
| `pause.localized` | every `Label` and `Button` text resolves from a `strings.csv` key |
| `pause.hint_glyph` | the hint contains `InputGlyphService.get_action_glyph("pause")` and not the literal `Esc` |

## Related
- Existing behavior: [`../existing_codebase/ui/pause_menu.md`](../existing_codebase/ui/pause_menu.md)
- [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`settings.md`](settings.md) · [`run_flow_ui.md`](run_flow_ui.md) · [`combat_hud.md`](combat_hud.md) · [`title_main_continue.md`](title_main_continue.md)
- [`../run-flow.md`](../run-flow.md) · [`../player-controls.md`](../player-controls.md) · [`../audio-director.md`](../audio-director.md) · [`../find-graph-seed.md`](../find-graph-seed.md)
