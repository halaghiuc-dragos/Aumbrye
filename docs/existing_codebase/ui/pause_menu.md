# Pause menu

The in-run pause overlay: Resume, Settings, Abandon run, Quit to menu. Built once in `_ready` on `MenuShell.build_modal`, owned by the `PlayerControls` autoload, so it exists in every scene including the front end.

## File
`apps/game/client/scripts/ui/pause_menu.gd` — 111 lines, `extends Control`.

Created at `player_controls.gd:28` by `_make_scripted_ui("PauseMenu", "res://scripts/ui/pause_menu.gd")`, i.e. a bare `Control` with the script attached and no scene.

## Control tree (`_build_ui`, `:52-65`)
```
Control (PauseMenu, MOUSE_FILTER_IGNORE while closed, PROCESS_MODE_ALWAYS)
├── ColorRect "Backdrop"     (MenuShell.build_modal → GameUISkin.make_backdrop)
└── PanelContainer "Panel"   (half 300 × 230 — MENU_HALF_W+40, MENU_HALF_H+80)
    └── MarginContainer "Margin"    (PANEL_MARGIN = 18)
        └── VBoxContainer "ContentVBox"   (separation 14)
            ├── Label "TitleLabel"   "Paused"
            ├── Button "Resume"
            ├── Button "Settings"
            ├── Button "Abandon run"     — only when RunFlow.is_run_active() at build time
            ├── Button "Quit to menu"
            └── Label "HintLabel"    "Esc to resume"
```

`_build_ui` is called from `_ready` (`:17`), which runs during `PlayerControls`' own `_ready` at autoload time.

## Lifecycle
| Method | Behavior |
|---|---|
| `open_menu()` `:31-38` | early-returns when already open; sets `visible`, `mouse_filter = STOP`, `get_tree().paused = true`, `Input.mouse_mode = MOUSE_MODE_VISIBLE` |
| `close_menu()` `:41-49` | early-returns when closed; hides, `mouse_filter = IGNORE`, `get_tree().paused = false`, `Input.mouse_mode = MOUSE_MODE_CAPTURED`, emits `closed` |
| `toggle()` `:24-28` | the entry point `player_controls.gd:149-150` calls |
| `is_open()` `:20-21` | read by `player_controls.gd:126-127` |

`_unhandled_input` (`:68-73`) closes on `ui_cancel` or `pause` while open. Both are bound to Escape (`project.godot:91`, `:188`).

Opening is gated in `player_controls.gd:140-151`: the `pause` action is ignored while the inventory, talents, or loadout is open, closes the settings overlay if that is open, and otherwise calls `toggle()`.

## Actions
| Button | Handler | Effect |
|---|---|---|
| Resume | `_on_resume` `:76-77` | `close_menu()` |
| Settings | `_on_settings` `:80-82` | `PlayerControls.open_settings()`; the pause menu stays open and the tree stays paused |
| Abandon run | `_on_abandon` `:85-96` | `show_confirmation` then `close_menu()` + `RunFlow.abandon_active_run()` (`run_flow.gd:344-352`) |
| Quit to menu | `_on_quit_to_menu` `:99-110` | `show_confirmation` then `close_menu()` + `RunFlow.return_to_main_menu()` (`run_flow.gd:697-704`) |

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Pause overlay with tree pause | IMPLEMENTED | `:31-38` |
| Abandon and quit confirmations | IMPLEMENTED | `:85-110` |
| Abandon run button | BROKEN — `_build_ui` runs once during autoload init, when no run can be active, so `RunFlow.is_run_active()` is false and the button is never created. Abandoning a run is unreachable from the pause menu | `:17` calls `_build_ui`; `:62-63` gates on `RunFlow.is_run_active()`; `player_controls.gd:28` builds this UI at autoload time, and `RunFlow._run_active` starts false (`run_flow.gd:675-676`) |
| Keyboard/gamepad focus | ABSENT — no `grab_focus`, no `focus_neighbor_*`, so with the tree paused and no focus owner none of the buttons can be reached; only Escape works | 0 `grab_focus` matches in the file; buttons at `:60-64` |
| Mouse mode after closing settings from pause | BROKEN — `settings_ui.close_settings` sets `MOUSE_MODE_CAPTURED` whenever a player node exists (`settings_ui.gd:539-540`), so returning from settings captures the cursor while the pause menu is still visible and the tree is still paused | `:80-82`; `settings_ui.gd:534-542` |
| Confirmation lifetime | BROKEN — `show_confirmation` parents the overlay to this node (`menu_shell.gd:101`), and `close_menu` only hides it, so pressing Escape while the Abandon confirmation is open closes the pause menu and leaves the overlay alive for the next open | `:41-49`, `:68-73`; `menu_shell.gd:98-124` |
| `closed` signal | STUB — declared at `:5` and emitted at `:49` with no listener anywhere in the client | 0 connections to a pause-menu `closed` |
| Front-end presence | PARTIAL — the node exists on the title screen and main menu because `PlayerControls` is an autoload; there it is only unreachable because those screens consume Escape first | `project.godot:49`; `main_menu.gd:200-219` uses `_input` |
| Run context in the panel | ABSENT — the pause menu shows no floor, run timer, seed, objective, or run-mode label | `:52-65` builds a title, buttons, and a hint |
| Art | PLACEHOLDER — shared `StyleBoxFlat` panel, text buttons, no icons | `menu_shell.gd:23-32`; `game_ui_skin.gd:54-63` |
| Localization | ABSENT — eight hardcoded English strings including both confirmation bodies | `:55`, `:60-65`, `:88-95`, `:102-109`; 0 `tr(` calls |
| Hint text accuracy | PARTIAL — `"Esc to resume"` hardcodes the key rather than resolving the `pause` glyph | `:65` |
| Pause-state audio ducking | ABSENT — no `AudioDirector` call on open or close | `:31-49` |
| Restart-run action | ABSENT — no retry or restart entry, only abandon and quit | `:60-64` |
| Screenshot / photo mode | ABSENT | `:60-64` |

## Related
- Improvement plan: [`../actual_improvements/ui/pause_menu.md`](../actual_improvements/ui/pause_menu.md)
- [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`settings.md`](settings.md) · [`run_flow_ui.md`](run_flow_ui.md) · [`combat_hud.md`](combat_hud.md)
- [`../run-flow.md`](../run-flow.md) · [`../player-controls.md`](../player-controls.md) · [`../local-save.md`](../local-save.md)
