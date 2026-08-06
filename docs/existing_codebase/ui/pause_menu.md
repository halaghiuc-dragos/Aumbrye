# Pause menu

## Status: FINISHED

The in-run pause overlay: run info, Resume, run-dependent actions, Achievements, Settings, Quit to menu. Rebuilt on every `open_menu()` from live `RunFlow` state. Registered with the `MenuStack` autoload for mouse mode and `ui_cancel`; suppressed on `front_end` scenes via `PlayerControls.allows_player_ui()`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/pause_menu.gd` | Pause overlay logic |
| `apps/game/client/scripts/ui/menu_stack.gd` | Modal stack, confirmations, mouse mode |
| `apps/game/client/scripts/ui/confirm_spec.gd` | Destructive confirmation payload |
| `apps/game/client/scripts/app/run_flow.gd` | `restart_current_floor()`, run info getters |
| `apps/game/client/scripts/audio/audio_director.gd` | `set_pause_mix(bool)` |
| `apps/game/client/scripts/validation/suites/pause_menu_suite.gd` | PSE validation |

## Control tree (`_build_shell`, `:98-133`)
```
Control (PauseMenu, MOUSE_FILTER_IGNORE while closed, PROCESS_MODE_ALWAYS)
├── ColorRect "Backdrop"
└── PanelContainer "Panel"
    └── MarginContainer "Margin"
        └── VBoxContainer "ContentVBox"
            ├── Label (cloud status, when syncing)
            ├── PanelContainer "RunInfo"     SectionFrame — mode, floor, time, seed, objective
            ├── VBoxContainer "Actions"      rebuilt per open in `_rebuild_actions`
            └── HBoxContainer "HintRow"      pause glyph + PAUSE_HINT_RESUME
```

Shell builds once in `_ready` (`:32`). `_rebuild_actions()` (`:165-196`) runs on every `open_menu()` (`:57`).

## Lifecycle
| Method | Behavior |
|---|---|
| `open_menu()` `:54-68` | `_rebuild_actions`, `_refresh_run_info`, `_refresh_hint`; `visible`, tree paused, `MenuStack.push`, `AudioDirector.set_pause_mix(true)`, `Resume.grab_focus` |
| `close_menu()` `:71-81` | hides, unpauses, `MenuStack.pop`, `set_pause_mix(false)`, emits `closed` |
| `toggle()` `:44-51` | early-return when `allows_player_ui()` false; else open/close |
| `is_open()` `:40-41` | read by `player_controls.gd` |

`cancel_requested` (`:94-95`) closes the menu; `MenuStack` dispatches `ui_cancel` to the top modal only (`menu_stack.gd:131-148`).

## Actions (rebuilt per open)
| Condition | Buttons |
|---|---|
| always | Resume, Achievements, Settings, Quit to menu |
| `RunFlow.is_run_active()` + castle, floor not cleared | + Restart floor, Abandon run |
| `RunFlow.is_run_active()` + castle, floor cleared | + Abandon run |
| `RunFlow.is_run_active()` + waves | + Leave waves |

Confirmations use `MenuStack.confirm(ConfirmSpec)` with `destructive = true`; overlay parents to `MenuStack` `ConfirmLayer`, not the pause menu (`menu_stack.gd:72-118`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Pause overlay with tree pause | IMPLEMENTED | `:54-81` |
| Rebuild actions on open | IMPLEMENTED | `:57`, `:165-196` |
| Abandon run (castle) | IMPLEMENTED | `:176-190` |
| Leave waves | IMPLEMENTED | `:177-180`; absent from `settings_ui.gd` |
| Restart floor | IMPLEMENTED | `:182-187`; `run_flow.gd:restart_current_floor` |
| Run info panel | IMPLEMENTED | `:113-126`, `:208-243` |
| Gamepad focus | IMPLEMENTED | `:67-68`, `:198-205` |
| MenuStack mouse/cancel | IMPLEMENTED | `:64-65`, `:78-79`; `menu_stack.gd` |
| Settings round-trip mouse | IMPLEMENTED | `settings_ui.gd:455-486` uses `MenuStack` without `Input.mouse_mode` |
| Front-end suppression | IMPLEMENTED | `:45-47`; `title_screen.gd`, `main_menu.gd` join `front_end` |
| Localization | IMPLEMENTED | all visible strings via `tr("PAUSE_*")`; `strings.csv` |
| Pause audio mix | IMPLEMENTED | `:66`, `:80`; `audio_director.gd:set_pause_mix` |
| Hint glyph | IMPLEMENTED | `:252` uses `InputGlyphService.get_action_glyph("pause")` |
| `closed` signal consumer | IMPLEMENTED | `:84-86` syncs `MenuStack.pop` |

## Related
- Improvement plan: [`../actual_improvements/ui/pause_menu.md`](../actual_improvements/ui/pause_menu.md)
- [`menu_shell.md`](menu_shell.md) · [`settings.md`](settings.md) · [`run_flow_ui.md`](run_flow_ui.md) · [`combat_hud.md`](combat_hud.md)
- [`../run-flow.md`](../run-flow.md) · [`../player-controls.md`](../player-controls.md) · [`../audio-director.md`](../audio-director.md)
