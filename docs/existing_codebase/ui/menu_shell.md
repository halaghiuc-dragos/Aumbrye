# Menu shell

A 125-line static helper class that assembles the standard modal scaffold — backdrop, centered panel, margin, content `VBoxContainer`, optional title — plus button factories and a confirmation overlay. It is the closest thing the project has to a menu framework; it is not a Godot `Theme` and holds no state.

## File
`apps/game/client/scripts/ui/menu_shell.gd` — `class_name MenuShell extends RefCounted`, all members `static`.

## API
| Member | Signature | Notes |
|---|---|---|
| `DEFAULT_BUTTON_MIN` | `Vector2(220, 36)` | `:8` |
| `DEFAULT_SEPARATION` | `14` | `:9` |
| `build_modal` | `(parent, title, half_w = GameUISkin.MENU_HALF_W, half_h = GameUISkin.MENU_HALF_H, clear_children = true) -> Dictionary` | `:12-43`; returns `{"panel", "content_vbox", "backdrop", "margin"}` |
| `add_subtitle` | `(parent: VBoxContainer, text) -> Label` | `:46-53`; centered, word-smart wrap, `style_body_label` |
| `add_hint` | `(parent: VBoxContainer, text) -> Label` | `:56-63`; names the node `HintLabel`, `style_hint_label` |
| `make_menu_button` | `(text, on_pressed: Callable, min_size = DEFAULT_BUTTON_MIN) -> Button` | `:66-76`; connects `pressed` and `GameUISkin.wire_button_sfx` |
| `add_button_row` | `(parent: VBoxContainer, buttons: Array[Button]) -> HBoxContainer` | `:79-86`; centered, separation `12` |
| `show_confirmation` | `(parent, title, message, on_confirm, on_cancel = Callable(), confirm_text = "Confirm", cancel_text = "Cancel") -> Control` | `:89-124` |

## Tree produced by `build_modal`
```
parent (set to PRESET_FULL_RECT by GameUISkin.ensure_full_rect, :19)
├── ColorRect "Backdrop"    (BACKDROP_COLOR, MOUSE_FILTER_STOP, show_behind_parent = true)
└── PanelContainer "Panel"  (PRESET_CENTER, ±half_w/±half_h clamped to 48% of the viewport)
    └── MarginContainer "Margin"      (PANEL_MARGIN = 18 on all four sides)
        └── VBoxContainer "ContentVBox"  (separation 14)
            └── Label "TitleLabel"       (only when title != "", style_menu_title)
```

With `clear_children = true` (the default) every existing child of `parent` is `queue_free()`d first (`:20-22`).

`show_confirmation` adds a second layer: a `Control` named `ConfirmOverlay` parented to `parent`, `move_to_front()`, then its own `build_modal(overlay, title, 300.0, 130.0)` with a message `Label` and a Cancel/Confirm row. It is the only place in the whole UI tree that sets `focus_neighbor_*` and calls `grab_focus` from shared code (`:121-123`).

## Consumers
| Script | Uses |
|---|---|
`pause_menu.gd:53-65` | `build_modal("Paused", MENU_HALF_W+40, MENU_HALF_H+80)`, 3-4 buttons, `add_hint` |
`settings_ui.gd:35`, `:44`, `:400` | `build_modal`, `add_hint`, `show_confirmation` |
`talents_ui.gd:28`, `:41` | `build_modal("Talents", 340, 260)`, `add_hint` |
`continue_menu.gd:26-42`, `:118` | `build_modal("Continue", 420, 360)`, `add_subtitle`, three buttons, two `add_button_row`, `show_confirmation` |
`character_create_ui.gd:43`, `:93-97` | `build_modal("Create Your Warden", 520, 500)`, `add_button_row` |
`main_menu.gd:84`, `:117`, `:157` | `make_menu_button` only — it builds its own panel with `GameUISkin.make_center_panel` (`main_menu.gd:44-48`) instead of `build_modal` |
`inventory_ui.gd:174-181` | `make_menu_button` only |
`waves_run_ui.gd:31`, `:85` | `make_menu_button` only |

Scene-based menus (`merchant_ui`, `blacksmith_ui`, `storage_ui`, `quest_board_ui`, `dialogue_ui`, `loadout_ui`, `results_screen`, the three portal menus) do not use `MenuShell` at all; they call `GameUISkin.apply_modal_menu` on an authored `.tscn` instead.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Shared modal scaffold | IMPLEMENTED | `menu_shell.gd:12-43` |
| Panel size clamping to viewport | IMPLEMENTED — 48 % of each axis | `game_ui_skin.gd:74-79` via `make_center_panel` |
| Button factory with SFX | IMPLEMENTED | `:66-76`; `game_ui_skin.gd:234-241` |
| Confirmation dialog | IMPLEMENTED with focus and left/right neighbors | `:89-124` |
| Pixel-theme application | ABSENT from `build_modal` — `GameUISkin.apply_pixel_theme` is called only by `apply_modal_menu` (`game_ui_skin.gd:186`), which scene-based menus use. Every code-built modal therefore keeps default texture filtering | `menu_shell.gd:12-43` has no `apply_pixel_theme` call |
| Focus on open | ABSENT — `build_modal` never focuses anything; only `show_confirmation` does | `:12-43` vs `:123` |
| `ui_cancel` handling | ABSENT — each consumer re-implements Esc in its own `_input`/`_unhandled_input`; `ConfirmOverlay` has none of its own | `pause_menu.gd:68-73`, `main_menu.gd:200-219`, `inventory_ui.gd:231-239` |
| Confirmation lifetime vs owner | BROKEN — `ConfirmOverlay` is parented to the menu that opened it. `pause_menu.close_menu()` only sets `visible = false`, so pressing Esc while the Abandon confirmation is up hides but does not free the overlay; reopening the pause menu shows a stale confirmation on top | `menu_shell.gd:101` parents to `parent`; `pause_menu.gd:41-49`, and `pause_menu.gd:68-73` fires while the overlay is open |
| Esc inside a confirmation | BROKEN in `main_menu` — `_input` special-cases only `_quit_overlay` (`main_menu.gd:203-207`), so Esc during the "New Warden" confirmation falls through to `_prompt_quit()` and stacks a second confirmation | `main_menu.gd:117-128` vs `:200-219` |
| Focus restore on close | ABSENT — `show_confirmation` frees the overlay without returning focus to the previously focused control | `:111-119` |
| Return type safety | PARTIAL — `build_modal` returns an untyped `Dictionary`; every consumer indexes it with string keys and casts | `:43`; e.g. `pause_menu.gd:59` |
| Godot `Theme` resource | ABSENT — styling is per-node `add_theme_*_override` created fresh per call; no `.theme` file exists in the client | `game_ui_skin.gd:54-63`, `:135-163`; 0 `.theme`/`.tres` theme files under `apps/game/client` |
| Localization | ABSENT — `confirm_text`/`cancel_text` default to the English literals `"Confirm"`/`"Cancel"`, and every call site passes English | `:95-96`; `pause_menu.gd:94-95`, `main_menu.gd:126-127`, `:166-167` |
| Scroll support for tall content | ABSENT — `ContentVBox` is not inside a `ScrollContainer`, so content taller than the clamped panel overflows | `:33-36` |
| Modal stack / input ownership | ABSENT — no registry of open modals; each menu sets `Input.mouse_mode` itself | `pause_menu.gd:38`, `:48`; `inventory_ui.gd:289`, `:302` |
| Open/close animation | ABSENT — panels appear instantly with no fade or scale | `:12-43` |

## Related
- Improvement plan: [`../actual_improvements/ui/menu_shell.md`](../actual_improvements/ui/menu_shell.md)
- Accessibility twin: [`menu_shell_a11y.md`](menu_shell_a11y.md)
- [`game_ui_skin.md`](game_ui_skin.md) · [`pause_menu.md`](pause_menu.md) · [`settings.md`](settings.md) · [`continue_menu.md`](continue_menu.md) · [`main_menu.md`](main_menu.md) · [`character_create.md`](character_create.md) · [`talents.md`](talents.md)
- [`../accessibility.md`](../accessibility.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md)
