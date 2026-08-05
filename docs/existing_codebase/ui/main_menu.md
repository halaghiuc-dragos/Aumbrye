# Main menu

The front-end hub: New Game, Continue, Settings, Quit. Like the title screen, its `.tscn` is an empty script host and the whole panel is built in code. It also owns the character creator and the continue menu as child nodes.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scenes/ui/main_menu.tscn` | 13 lines: one `Control` named `MainMenu`, `anchors_preset = 15`, script attached, no children |
| `apps/game/client/scripts/ui/main_menu.gd` | 220 lines |

Reached from `title_screen.gd:122-123` and from `loading_screen.gd:58` when a boot fails.

## Startup work
`_ready()` (`:17-35`): `process_mode = PROCESS_MODE_ALWAYS`, `AccessibilitySettings.load_from_save()`, `DisplaySettings.apply()`, `AudioSettings.load_from_save()`, `AudioDirector.play_menu_music()`, `_build_ui()`, `_connect_global_settings()`, then instantiates `CharacterCreateUI` and `ContinueMenu` as children and wires their signals.

Both submenus are created with `Script.new()` on a `Control`-derived script rather than from a scene (`:25-27`, `:30-32`), matching how `player_controls.gd:37-44` builds its global UIs.

## Control tree (`_build_ui`, `:38-80`)
```
Control (MainMenu, FULL_RECT)
├── ColorRect              Color(0.02, 0.02, 0.06, 1.0), FULL_RECT
├── PanelContainer "MenuPanel"   (make_center_panel, half 320 × 270 — MENU_HALF_W+60, MENU_HALF_H+120)
│   └── MarginContainer         (24 px all sides)
│       └── VBoxContainer       (separation 14)
│           ├── Label   "Aumbrye", style_menu_title
│           ├── Label   "Echo of the Fallen Warden", style_body_label
│           ├── Button  "New Game"
│           ├── Button  "Continue"   (named ContinueButton)
│           ├── Button  "Settings"
│           ├── Button  "Quit Game"
│           └── Label   "Esc: quit", style_hint_label
├── Control "CharacterCreateUI"  (character_create_ui.gd, hidden)
└── Control "ContinueMenu"       (continue_menu.gd, hidden)
```

All four buttons come from `MenuShell.make_menu_button` via the `_menu_button` wrapper (`:83-84`), so they are 220 × 36 and wired to `AudioDirector.play_ui_sfx`.

## Services and flow
| Action | Path |
|---|---|
New Game with an existing save | `MenuShell.show_confirmation` then `_character_create.open_creation()` + `move_to_front()` (`:115-132`) |
New Game with no save | straight to `open_creation()` (`:130-132`) |
Continue | gated on `LocalSave.has_playable_character()`, then `_continue_menu.open_menu()` (`:135-140`) |
Settings | `PlayerControls.open_settings()` — the global settings overlay, not a local one (`:143-145`) |
Quit | `_prompt_quit()` → `show_confirmation` → `get_tree().quit()` (`:148-168`) |
Character created | `LocalSave.queue_boot_new_game(class_id, name, appearance)` then `change_scene_to_file` to `loading_screen.tscn` (`:176-178`) |
Continue slot chosen | `LocalSave.queue_boot_continue_character(id)` then the loading screen (`:185-189`) |

`_refresh_continue_button` (`:95-98`) disables Continue when `LocalSave.has_playable_character()` is false; it is called on build, on settings close, and on slot delete.

`_show_main_panel(bool)` (`:101-102`) only toggles `MenuPanel.visible`, so the backdrop `ColorRect` stays visible under every submenu.

## Input
`_input` (`:200-219`) — note `_input`, not `_unhandled_input`, unlike every other menu — handles `ui_cancel` with this precedence: free `_quit_overlay` if present; return silently if the character creator or continue menu is open; close the global settings overlay if open; otherwise `_prompt_quit()`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Four-entry front end with confirmations | IMPLEMENTED | `:69-74`, `:115-168` |
| Continue disabled without a save | IMPLEMENTED | `:95-98` |
| Character create / continue submenu ownership | IMPLEMENTED | `:25-35` |
| Settings routed through `PlayerControls` | IMPLEMENTED | `:143-145` |
| Keyboard/gamepad focus | ABSENT — no `grab_focus` and no `focus_neighbor_*` anywhere in the file, so with no focus owner `ui_down` and `ui_accept` do nothing. The front end is mouse-only | 0 `grab_focus` matches in `main_menu.gd`; buttons at `:69-74` |
| Authored scene content | ABSENT — `main_menu.tscn` has no child nodes | `main_menu.tscn:5-13` |
| Uses the shared modal scaffold | PARTIAL — builds its own panel with `GameUISkin.make_center_panel` (`:44-58`) instead of `MenuShell.build_modal`, duplicating the margin and vbox setup and using 24 px margins where `PANEL_MARGIN` is 18 | `:50-58` vs `menu_shell.gd:26-36` |
| Esc inside the New Warden confirmation | BROKEN — `_on_new_game`'s overlay is not stored, and `_input` special-cases only `_quit_overlay`, so Esc there falls through to `_prompt_quit()` and stacks a second confirmation | `:117-128` vs `:203-207` |
| `_input` vs `_unhandled_input` | PARTIAL — the only menu using `_input`, so it sees `ui_cancel` before focused controls and before every other menu | `:200` against `pause_menu.gd:68`, `settings_ui.gd:545` |
| Backdrop under submenus | PARTIAL — `_show_main_panel(false)` hides only the panel; the flat `ColorRect` remains, and each submenu adds its own backdrop on top | `:101-102`; `menu_shell.gd:23` inside the submenus |
| Art | PLACEHOLDER — a flat `Color(0.02, 0.02, 0.06)` fill and text; no logo, no background, no button art | `:40-43`; `apps/game/client/**/*.png` returns 0 files |
| Localization | ABSENT — seven hardcoded English strings including both confirmation bodies | `:60`, `:65`, `:69-76`, `:119-127`, `:159-167`; 0 `tr(` calls |
| Hint text accuracy | PARTIAL — `"Esc: quit"` hardcodes the key name rather than resolving the `ui_cancel` glyph | `:76` |
| Mouse mode | ABSENT from this file — the submenus set `Input.mouse_mode` themselves | `continue_menu.gd:50`, `character_create_ui.gd:134` |
| Music | IMPLEMENTED — shared menu track, same call as the title screen | `:22` vs `title_screen.gd:17` |
| Credits / extras entry | ABSENT — four entries only, no credits, achievements, or leaderboard entry | `:69-74` |

## Related
- Improvement plan: [`../actual_improvements/ui/main_menu.md`](../actual_improvements/ui/main_menu.md)
- Entry-flow coordination: [`title_main_continue.md`](title_main_continue.md)
- [`title_screen.md`](title_screen.md) · [`continue_menu.md`](continue_menu.md) · [`character_create.md`](character_create.md) · [`settings.md`](settings.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md)
- [`../local-save.md`](../local-save.md) · [`../character-service.md`](../character-service.md) · [`../audio-director.md`](../audio-director.md)
