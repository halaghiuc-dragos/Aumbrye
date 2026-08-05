# Title screen

The project's boot scene. A `.tscn` containing nothing but a script host; the entire screen — backdrop, vignette, a stacked-`ColorRect` tower, panel, lore text, and a pulsing prompt — is built in `_ready`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scenes/ui/title_screen.tscn` | 13 lines: one `Control` named `TitleScreen`, `anchors_preset = 15`, with the script attached. No child nodes. |
| `apps/game/client/scripts/ui/title_screen.gd` | 139 lines; builds and drives everything |

`project.godot:19` sets `run/main_scene="res://scenes/ui/title_screen.tscn"`, so this is the first thing the player sees.

## Boot work done here
`_ready()` (`:12-19`) runs, in order: `process_mode = PROCESS_MODE_ALWAYS`, `AccessibilitySettings.load_from_save()`, `DisplaySettings.apply()`, `PixelDioramaBootstrap.prime()`, `AudioDirector.play_menu_music()`, `_build_ui()`, then `call_deferred("_enable_continue")`.

`_enable_continue` (`:111-112`) sets `_ready_to_continue = true` one frame later, which is the only gate on advancing.

## Control tree (`_build_ui`, `:22-91`)
```
Control (TitleScreen, FULL_RECT)
├── ColorRect          backdrop, Color(0.015, 0.02, 0.08, 1.0), FULL_RECT
│   └── Control        tower host (PRESET_CENTER_TOP, 180×220 px)
│       └── 6 × ColorRect   widths 120 → 60 px, height 18, Color(0.12, 0.14, 0.22, 0.55)
├── ColorRect          vignette, Color(0, 0, 0, 0.35), FULL_RECT
└── PanelContainer "Panel"  (make_center_panel, half 260 × 180)
    └── MarginContainer     (28 px on all sides)
        └── VBoxContainer   (separation 14)
            ├── Label   ornament, text "◆ ◆ ◆", style_hint_label
            ├── Label   "AUMBRYE", style_menu_title
            ├── Label   "Echo of the Fallen Warden", style_body_label
            ├── ColorRect  2 px rule, Color(0.55, 0.48, 0.32, 0.65)
            ├── Label   three-sentence lore paragraph, style_body_label
            ├── Label   "Press any key to enter the tower", style_hint_label   -> _hint_label
            └── Label   "Early Access — Pixel Diorama build", style_hint_label
```

The tower host is added as a child of the backdrop (`:34` passes `backdrop` to `_build_tower_silhouette`), and the vignette is added after it, so the vignette dims the tower.

## Behavior
- `_process` (`:115-119`) pulses `_hint_label.modulate.a` as `0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.004)`, i.e. roughly one cycle per 1.57 s, forever, once `_ready_to_continue` is set.
- `_input` (`:126-138`) advances on any pressed non-echo `InputEventKey`, any pressed `InputEventMouseButton`, or any pressed `InputEventJoypadButton`, then `change_scene_to_file("res://scenes/ui/main_menu.tscn")`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Boots the game and initializes accessibility, display, pixel bootstrap, and menu music | IMPLEMENTED | `title_screen.gd:12-19` |
| Any-input advance | IMPLEMENTED for keyboard, mouse, and gamepad buttons | `:126-138` |
| Authored scene content | ABSENT — `title_screen.tscn` has zero child nodes; every visual is runtime `ColorRect`/`Label` | `title_screen.tscn:5-13` |
| Title art or logo | PLACEHOLDER — the title is the text `"AUMBRYE"` in the shared menu-title style, and the "tower" is six stacked translucent rectangles | `:54-58`, `:102-108` |
| Decorative ornament | PARTIAL — the Unicode string `"◆ ◆ ◆"` in a `Label` stands in for a masthead ornament | `:49` |
| Version string | PLACEHOLDER — hardcoded `"Early Access — Pixel Diorama build"` rather than read from `project.godot` `config/version` or a build stamp | `:88` |
| Hint prompt wording | PARTIAL — `"Press any key to enter the tower"` is literal English and does not name a button, so it is device-agnostic by accident rather than by using `InputGlyphService` | `:82` |
| Pulse animation | IMPLEMENTED, unconditional — no reduced-motion gate exists | `:115-119` |
| Save-state awareness | ABSENT — the title makes no distinction between a first launch and a returning player | `:12-19` reads nothing from `LocalSave` |
| Focus / focusable controls | n/a — the screen has no `Button`, so there is nothing to focus; `_input` covers every device | `:22-91` creates only `Label`, `ColorRect`, `PanelContainer` |
| Localization | ABSENT — six hardcoded English strings including a three-sentence lore paragraph | `:49`, `:55`, `:61`, `:73-77`, `:82`, `:88`; 0 `tr(` calls |
| Skip-to-menu speed | PARTIAL — advance is gated on one deferred frame, so it is effectively immediate; there is no minimum display time and no fade | `:19`, `:111-112` |
| Transition to main menu | PARTIAL — a hard `change_scene_to_file` with no fade | `:122-123` |
| Audio | IMPLEMENTED — `AudioDirector.play_menu_music()`; no dedicated title sting | `:17` |

## Related
- Improvement plan: [`../actual_improvements/ui/title_screen.md`](../actual_improvements/ui/title_screen.md)
- Entry-flow coordination: [`title_main_continue.md`](title_main_continue.md)
- [`main_menu.md`](main_menu.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`settings.md`](settings.md)
- [`../pixel-style.md`](../pixel-style.md) · [`../audio-director.md`](../audio-director.md) · [`../local-save.md`](../local-save.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md)
