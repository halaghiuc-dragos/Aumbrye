# Settings overlay — improvement plan

## Current state
One 551-line script builds about 40 controls into a single 380-px scroll. Four accessibility controls have no label at all. Nothing is focused on open, so the panel is mouse-only. Colorblind mode persists but has no runtime consumer outside the validation suite. There is no key rebinding, no window/display control, and no language selector. Every string is hardcoded English, the hint text names the wrong destination, closing the overlay can capture the cursor while another menu is open, and every slider step rewrites the entire save file. See [`../existing_codebase/ui/settings.md`](../existing_codebase/ui/settings.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| SET-01 | P0 | Four controls are added with no label: UI scale, subtitle scale, vibration sliders and the colorblind dropdown. Under the Accessibility heading a player sees three anonymous sliders. | `:68-79`, `:88-98`, `:99-109`, `:110-125`; contrast with `_volume_slider` `:165-179` and `_labeled_slider` `:465-493` |
| SET-02 | P0 | The panel is mouse-only: no `grab_focus` on open, no focus neighbors, ~40 controls. | `:500-515`; 0 `grab_focus` matches |
| SET-03 | P0 | Colorblind mode is a fake control — it saves and reloads but changes nothing; `get_damage_color` is only called from the validation suite. | `:110-125`; `accessibility_settings.gd:37-69`; sole call at `m6_suite.gd:281` |
| SET-04 | P0 | No key rebinding at all. A player cannot see or change any binding, and two actions currently collide on gamepad button 7. | 0 `InputMap` matches under `scripts/ui/`; `project.godot:91`, `:188` |
| SET-05 | P1 | No window or display settings: fullscreen, borderless, vsync, monitor, and frame cap are all unreachable in game. | `:29-59`; 0 `DisplayServer.window_set_mode` matches under `scripts/ui/` |
| SET-06 | P1 | Closing settings captures the cursor whenever a `player` node exists, even when the pause menu or a vendor panel is still open behind it. | `:534-542`; `pause_menu.gd:80-82` |
| SET-07 | P1 | The hint reads `"Esc: back to main menu"` but Escape only closes the overlay. | `:44` vs `:545-550` |
| SET-08 | P1 | Zero localization across ~50 strings and no language selector. | `:37`-`:456`; 0 `tr(` and 0 `TranslationServer` matches |
| SET-09 | P1 | Every accessibility slider step writes the whole save file, and every pixel slider step clears material caches and reapplies project settings. Dragging one slider produces dozens of full saves and rendering rebuilds. | `:76`, `:96`, `:107` → `accessibility_settings.gd:34` → `local_save.gd:406-407`; `:490` → `pixel_diorama_settings.gd:176-190` |
| SET-10 | P1 | Subtitle scale only affects dialogue lines being built; an open dialogue does not restyle, and nothing else in the UI respects it. | `:88-98`; sole consumer `dialogue_ui.gd:79-81` |
| SET-11 | P2 | A run action (Leave Waves) lives inside the settings panel. | `:438-462` |
| SET-12 | P2 | The backup list is built once and never refreshed, because `_build_ui_if_needed` early-returns on later opens. | `:29-31`, `:58`, `:387` |
| SET-13 | P2 | Values are displayed inconsistently: raw three-decimal floats for pixel sliders, nothing for volumes, nothing for accessibility sliders. | `:476`, `:488`; `:165-179` |
| SET-14 | P2 | About 40 rows in one flat scroll with no tabs, no search, and no reset-to-default outside the pixel section. | `:45-58`, `:366-372` |
| SET-15 | P2 | The Accessibility heading skips `style_section_title`, so it renders at body weight while the other three headings do not. | `:65-67` vs `:139-142` |
| SET-16 | P2 | Leaderboard opt-in is filed under Accessibility. | `:126-133` |
| SET-17 | P2 | `_hint_label` is assigned and never read. | `:7`, `:44` |

## Target design

### Tabbed settings screen driven by a schema
Replace the single scroll with a tabbed shell and drive rows from a declarative table so every row gets a label, a value readout, a tooltip, a default, and a focus slot for free.

```
SettingsUI (Control, PROCESS_MODE_ALWAYS)
├── ColorRect "Backdrop"
└── PanelContainer "Panel"           SettingsPanel theme variation
    └── MarginContainer "Margin"
        └── VBoxContainer "ContentVBox"
            ├── Label "TitleLabel"                MenuTitle
            ├── HBoxContainer "TabBar"            SettingsTab buttons
            │   Gameplay │ Display │ Audio │ Controls │ Accessibility │ Advanced
            ├── ScrollContainer "Scroll"
            │   └── VBoxContainer "PageHost"      one SettingsPage child, rebuilt per tab
            │       └── (SettingsRow instances)
            └── HBoxContainer "FooterRow"
                ├── Button "ResetPageButton"      "Reset this page"
                └── Button "BackButton"           + hint caption with the ui_cancel glyph
```

Each row is one scene, `scenes/ui/settings_row.tscn`, script `settings_row.gd`:

```
SettingsRow (PanelContainer, focus_mode = FOCUS_ALL)
├── HBoxContainer
│   ├── VBoxContainer "Text"
│   │   ├── Label "NameLabel"        SettingsRowName
│   │   └── Label "DescLabel"        SettingsRowDesc, autowrap
│   ├── Control "Widget"             slider / checkbox / option / button host
│   └── Label "ValueLabel"           SettingsRowValue, fixed 72 px, right-aligned
```

`settings_schema.gd` holds one entry per setting:

| Field | Meaning |
|---|---|
| `id` | `ui_scale`, `master_volume`, `colorblind_mode`, … |
| `page` | `gameplay` / `display` / `audio` / `controls` / `accessibility` / `advanced` |
| `kind` | `slider` / `toggle` / `option` / `action` / `binding` |
| `name_key`, `desc_key` | `strings.csv` keys |
| `range` | `{min, max, step}` for sliders |
| `format` | `percent`, `multiplier`, `decimal2`, `enum` — drives `ValueLabel` |
| `default` | value used by Reset |
| `getter`, `setter` | `Callable`s onto the settings singletons |
| `requires_restart` | shows a `RESTART_REQUIRED` badge |

A row with no `name_key` fails validation, which makes SET-01 unrepresentable rather than merely fixed. `format` gives every slider a readable value: UI scale as `110%`, volumes as `75%`, pixel scale as `4.0` (SET-13).

Rejected alternative: adding four `Label` nodes to the existing hand-built code. It closes SET-01 only until the next control is added by hand.

### Pages
| Page | Contents |
|---|---|
| Gameplay | leaderboard opt-in (moved off Accessibility), hold-to-confirm destructive actions, damage numbers, tutorial hints, auto-pickup |
| Display | window mode (windowed / borderless / exclusive fullscreen), monitor, vsync, frame cap, UI scale, then the pixel-diorama block with a `Show advanced pixel options` disclosure |
| Audio | the five bus volumes as percentages, each with a `Test` button that plays a bus-appropriate cue |
| Controls | the full `InputMap` rebinder (below) |
| Accessibility | reduce camera shake, vibration, subtitle scale, text scale, colorblind mode, reduced motion, screen-shake-free hit feedback, high-contrast HUD |
| Advanced | backup restore list, save folder path, seed display, log export, validation-suite launcher in debug builds |

The Leave Waves action moves to the pause menu (SET-11, specified in [`pause_menu.md`](pause_menu.md)).

### Controls page
A `binding` row per rebindable action, grouped Movement / Combat / Interface, each with primary keyboard and primary gamepad columns:

```
BindingRow (SettingsRow variant)
├── Label "NameLabel"                  "Dodge"
├── Button "KeyboardBindingButton"     glyph + name from InputGlyphService
├── Button "PadBindingButton"
└── Button "ResetBindingButton"
```

Pressing a binding button opens a `BindingCaptureModal` that listens for the next `InputEventKey`, `InputEventJoypadButton`, or `InputEventJoypadMotion` past a `0.5` deadzone, then:
1. rejects reserved events (`ui_cancel`, and left mouse in menus),
2. detects collisions across all rebindable actions and offers Swap / Cancel,
3. writes through `InputMapService.set_binding(action, device_family, event)`, which persists to the `input` block of meta save and reapplies on boot.

This closes SET-04 and gives the gamepad-button-7 collision (`project.godot:91`, `:188`) a place to be seen and fixed by the player as well as by the input map itself.

### Colorblind mode made real
`AccessibilitySettings.get_damage_color` becomes the single source for damage-number and status tint colors, called from the floating damage number spawner, `combat_hud.gd` resource bars, and `StatusIconAtlas` tinting. A `colorblind_mode` change emits `AccessibilitySettings.changed`, which those consumers listen to. Additionally each palette gains a shape channel so the same information survives a monochrome screenshot (see [`status_icons_glyphs.md`](status_icons_glyphs.md)) (SET-03).

### Live signals instead of per-tick saves
`AccessibilitySettings`, `AudioSettings`, and `PixelDioramaSettings` gain a `changed(id, value)` signal and a `commit()` that writes once. Rows apply on `value_changed` and commit on `drag_ended` / focus loss / panel close, with a `0.5` s debounce fallback. `PixelDioramaSettings.save_and_apply()` splits into `apply_live()` (cheap uniform updates) and `commit()` (save plus cache clear), so dragging a shader slider no longer clears material caches per step (SET-09).

Subtitle scale and a new `ui_text_scale` are applied through a `UITextScale` helper that walks registered labels on `changed`, so an open dialogue restyles immediately (SET-10).

### Focus, mouse, and exit
- `initial_focus` is the active tab button; `ui_cancel` goes back one level through `MenuStack`.
- Tab bar is reachable with `ui_page_prev` / `ui_page_next` (`Q`/`E`, `LB`/`RB`) from anywhere on the page.
- Rows are focusable containers; left/right on a focused row adjusts sliders and cycles options without entering the widget.
- `Scroll` follows focus via `ensure_control_visible`.
- The overlay no longer touches `Input.mouse_mode`; `MenuStack` restores the mode of the layer below, which fixes the capture-behind-pause bug (SET-02, SET-06).
- The footer hint is built with `make_symbol_caption_row` and the live `ui_cancel` glyph, and says `SETTINGS_HINT_BACK` — "Back" — not "back to main menu" (SET-07).

### Localization
Keys are derived from the schema: `SETTINGS_<ID>_NAME` and `SETTINGS_<ID>_DESC` for every row, `SETTINGS_PAGE_<PAGE>`, `SETTINGS_VALUE_ON`/`OFF`, `SETTINGS_RESET_PAGE`, `SETTINGS_BACK`, `SETTINGS_RESTART_REQUIRED`, `SETTINGS_BINDING_PROMPT`, `SETTINGS_BINDING_CONFLICT`. A `language` row on the Gameplay page sets `TranslationServer.set_locale` and persists it (SET-08).

### Backup list and headings
The Advanced page rebuilds on show, so `LocalSave.list_backups()` is re-read each time (SET-12). Every heading uses the `SettingsSection` theme variation from the shared theme rather than a per-call styling helper (SET-15).

## Work plan
1. **Schema and row scene** — `settings_schema.gd`, `settings_row.tscn`/`gd`, value formatting, defaults (SET-01, SET-13).
2. **Tabbed shell** — tab bar, `PageHost`, footer, per-page reset (SET-14).
3. **Focus and stack integration** — initial focus, page paging actions, `ensure_control_visible`, removal of all `Input.mouse_mode` writes (SET-02, SET-06).
4. **Display page** — window mode, monitor, vsync, frame cap, UI scale, pixel block behind a disclosure (SET-05).
5. **Controls page** — `InputMapService`, binding rows, capture modal, collision swap, persistence (SET-04).
6. **Change signals and commit** — split apply from save on all three settings singletons (SET-09).
7. **Colorblind and text scale consumers** — wire `get_damage_color` and `UITextScale` into HUD, damage numbers, status icons, dialogue (SET-03, SET-10).
8. **Localization and language row** (SET-08).
9. **Move Leave Waves to the pause menu; move leaderboard opt-in to Gameplay; refresh backups on show; heading variation; delete `_hint_label`** (SET-07, SET-11, SET-12, SET-15, SET-16, SET-17).

## Data and schema changes
- New `scripts/ui/settings_schema.gd`, `scripts/ui/settings_row.gd`, `scenes/ui/settings_row.tscn`, `scripts/ui/binding_capture_modal.gd`, `scripts/input/input_map_service.gd`.
- `AccessibilitySettings`: new `reduced_motion`, `ui_text_scale`, `high_contrast_hud`; new `changed` signal; `save()` split into `apply()` + `commit()`.
- `AudioSettings`, `PixelDioramaSettings`: same `changed`/`commit` split; `PixelDioramaSettings.apply_live()`.
- New meta-save blocks: `input` (bindings), `display` (window mode, vsync, frame cap, monitor), `locale`.
- `settings_ui.gd` loses the five `load_from_save` calls in `_ready`; boot loading belongs to the boot service in [`title_main_continue.md`](title_main_continue.md).
- `apps/game/client/translations/strings.csv`: the `SETTINGS_*` keys above.

## Acceptance criteria
- [ ] Every settings row shows a name, a description, and a formatted value; no anonymous slider exists on any page.
- [ ] The whole panel is operable with keyboard only and with a gamepad only, including tab switching and binding capture.
- [ ] Changing colorblind mode visibly changes damage-number and status-tint colors without reopening the panel.
- [ ] The Controls page lists every rebindable action with its keyboard and gamepad binding, and rebinding survives a restart.
- [ ] Attempting to bind an event already used offers Swap or Cancel and never produces a duplicate.
- [ ] Window mode, vsync, and frame cap can be changed in game and survive a restart.
- [ ] Dragging a slider across its whole range writes the save file at most once.
- [ ] Dragging a pixel-shader slider does not clear material caches per step.
- [ ] Changing subtitle scale while a dialogue is open resizes that dialogue immediately.
- [ ] Closing settings opened from the pause menu leaves the cursor visible and the pause menu focused.
- [ ] The footer hint shows the live `ui_cancel` glyph and the word Back.
- [ ] The settings panel contains no run actions; Leave Waves is in the pause menu.
- [ ] Reopening the panel after a backup rotation shows the new backup.
- [ ] Switching to a stub locale changes every visible string, including page names and value words.

## Validation
Extend `apps/game/client/scripts/validation/suites/m6_suite.gd` and add `settings` cases:

| Test id | Assertion |
|---|---|
| `settings.schema_labels` | every schema entry has non-empty `name_key` and `desc_key`, and every key exists in `strings.csv` |
| `settings.no_anonymous_widget` | every `HSlider`, `CheckBox`, and `OptionButton` in the built tree has a `SettingsRow` ancestor with a non-empty `NameLabel` |
| `settings.focus_on_open` | `gui_get_focus_owner()` is the active tab button |
| `settings.focus_graph` | BFS from the initial focus reaches every row on every page |
| `settings.page_paging` | `ui_page_next` from a focused row switches page and focuses the new tab |
| `settings.no_mouse_mode` | `settings_ui.gd` contains no `Input.mouse_mode` |
| `settings.colorblind_live` | setting `colorblind_mode = "deuteranopia"` changes the color returned to the damage-number spawner and emits `changed` |
| `settings.colorblind_consumers` | `get_damage_color` has at least three non-test call sites |
| `settings.binding_roundtrip` | `InputMapService.set_binding("dodge", "keyboard", key)` then reload yields the same event in `InputMap` |
| `settings.binding_conflict_detected` | binding an event already used by another action reports a conflict |
| `settings.no_duplicate_pad_bindings` | no two rebindable actions share a joypad event after load |
| `settings.window_mode_roundtrip` | setting borderless persists and reapplies on boot |
| `settings.save_debounce` | 20 simulated slider steps produce exactly one `LocalSave` write |
| `settings.pixel_live_apply` | 20 pixel-slider steps call `apply_live` 20 times and `clear_material_caches` at most once |
| `settings.text_scale_live` | changing `subtitle_scale` with a dialogue open changes that dialogue's font size |
| `settings.hint_glyph` | the footer hint contains the `ui_cancel` glyph and no literal `main menu` |
| `settings.no_run_actions` | the built tree contains no node named `WavesRunSection` |
| `settings.backups_refresh` | writing a new backup and reopening the Advanced page lists it |
| `settings.localized` | every `Label`, `Button`, `CheckBox`, and `OptionButton` item resolves from a `strings.csv` key |
| `settings.reset_page` | Reset restores every row on the page to its schema `default` |

## Related
- Existing behavior: [`../existing_codebase/ui/settings.md`](../existing_codebase/ui/settings.md)
- [`display_settings.md`](display_settings.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`pause_menu.md`](pause_menu.md) · [`input_glyphs.md`](input_glyphs.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md) · [`title_main_continue.md`](title_main_continue.md)
- [`../accessibility.md`](../accessibility.md) · [`../audio-director.md`](../audio-director.md) · [`../pixel-diorama-settings.md`](../pixel-diorama-settings.md) · [`../local-save.md`](../local-save.md) · [`../hit-feedback.md`](../hit-feedback.md)
