# Settings overlay

One scrolling overlay containing accessibility, audio, pixel-diorama, and save-recovery controls. Owned by the `PlayerControls` autoload, so the same instance serves the front end, the hub, and runs.

## File
`apps/game/client/scripts/ui/settings_ui.gd` — 551 lines, `extends Control`. No scene; created at `player_controls.gd:26` as a bare `Control` with the script attached.

Entry points: `main_menu.gd:145` (Settings button), `pause_menu.gd:82`, `player_controls.gd:100-102`. `main_menu.gd:88` and `:213` reach the node directly through `PlayerControls.get_settings_ui()`.

## Boot side effects
`_ready` (`:18-26`) loads five settings singletons before anything is shown: `AccessibilitySettings.load_from_save()`, `DisplaySettings.apply()`, `LeaderboardSettings.load_from_save()`, `AudioSettings.load_from_save()`, `PixelDioramaSettings.load_from_save()`. Because the node is an autoload child, this runs at startup, duplicating the same loads in `title_screen.gd` and `main_menu.gd` (see [`title_main_continue.md`](title_main_continue.md)).

## Control tree (`_build_ui_if_needed`, `:29-59`)
```
Control (SettingsUI, PROCESS_MODE_ALWAYS)
├── ColorRect "Backdrop"
└── PanelContainer "Panel"      (half SETTINGS_HALF_W+80 × SETTINGS_HALF_H+40)
    └── MarginContainer "Margin"
        └── VBoxContainer "ContentVBox"
            ├── Label "TitleLabel"   "Settings"
            ├── Label "HintLabel"    "Esc: back to main menu"
            └── ScrollContainer "Scroll"   (custom_minimum_size.y = 380)
                └── VBoxContainer "ScrollVBox"
                    ├── Accessibility rows          (:62-133)
                    ├── Audio rows                  (:136-162)
                    ├── VBoxContainer "PixelDioramaSection"   (:182-377)
                    ├── Advanced / Corruption Recovery rows   (:380-413)
                    └── VBoxContainer "WavesRunSection"       (:438-462, conditional)
```
`build_modal` is called with `clear_children = false` (`:40`) because `_build_ui_if_needed` frees the children itself at `:33-34`. The panel is re-centered on every open (`_recenter_panel` `:518-531`).

There is no Back or Close button; the only way out is `ui_cancel` or `pause` (`:545-550`).

## Control inventory
| Control | Persists | Applies at runtime | Status | Evidence |
|---|---|---|---|---|
| UI scale slider 0.80–1.50 | yes | yes — `DisplaySettings.apply()` sets `root.content_scale_factor` | IMPLEMENTED, no label | `:68-79`; `display_settings.gd:11` |
| Reduce camera shake | yes | yes — read by `hit_feedback.gd:116` and `:138` | IMPLEMENTED | `:80-87` |
| Subtitle scale slider 0.80–1.60 | yes | partly — only `dialogue_ui.gd:79-81` reads it, and only while building a line, so an open dialogue does not restyle | PARTIAL, no label | `:88-98` |
| Vibration slider 0.0–1.0 | yes | yes — read by `hit_feedback.gd:157` | IMPLEMENTED, no label | `:99-109` |
| Colorblind mode (Default/Protanopia/Deuteranopia/Tritanopia) | yes | no — the only caller of `AccessibilitySettings.get_damage_color` in the client is the validation suite | FAKE, no label | `:110-125`; `accessibility_settings.gd:37-69`; sole call site `validation/suites/m6_suite.gd:281` |
| Leaderboard opt-in | yes | yes — read by `run_flow.gd:768-769`, gated in `api_client.gd:142-143` | IMPLEMENTED, but filed under Accessibility | `:126-133` |
| Master / Music / SFX / Ambience / UI volume | yes | yes — `AudioSettings.save()` calls `apply()`, which sets bus volumes; all five buses exist | IMPLEMENTED | `:143-162`; `audio_settings.gd:25-52`; `assets/audio/default_bus_layout.tres:4-33` |
| Render resolution preset | yes | yes — `save_and_apply()` | IMPLEMENTED | `:213-231` |
| Low-res viewport upscale | yes | yes — also attaches/detaches `PixelDioramaViewport` | IMPLEMENTED | `:233-244` |
| 21 pixel-diorama toggles and sliders | yes | yes — every widget ends in `PixelDioramaSettings.save_and_apply()` | IMPLEMENTED | `:246-364`, `:425-435`, `:465-493`; `pixel_diorama_settings.gd:176-190` |
| Restore recommended look | yes | yes — `apply_beauty_defaults()` ends in `save_and_apply()`, then the section is rebuilt so widgets show applied values | IMPLEMENTED | `:366-372`; `pixel_diorama_settings.gd:194-223` |
| Restore backup *n* | n/a | yes — `LocalSave.restore_backup(index)` behind a confirmation | IMPLEMENTED | `:394-413` |
| Leave Waves (hub, no rewards kept) | n/a | yes — `RunFlow.quit_waves_run()` | IMPLEMENTED, but a run action inside the settings panel | `:438-462` |

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Four unlabeled controls | BROKEN — the UI scale, subtitle scale, and vibration sliders and the colorblind `OptionButton` are added with no `Label`, so they appear as three bare sliders and one dropdown under the Accessibility heading | `:68-79`, `:88-98`, `:99-109`, `:110-125` — no `Label` is created for any of them, unlike `_volume_slider` (`:165-179`) and `_labeled_slider` (`:465-493`) |
| Keyboard/gamepad focus | ABSENT — `open_settings` never calls `grab_focus`, and no focus neighbors are set, so with ~40 controls the panel is mouse-only | `:500-515`; 0 `grab_focus` matches in the file |
| Colorblind mode | FAKE — persisted and shown, no runtime consumer outside the validation suite | `:110-125`; sole `get_damage_color` call at `m6_suite.gd:281` |
| Key rebinding / controls section | ABSENT — no `InputMap` editing anywhere in the file, and no other UI script exposes rebinding | 0 `InputMap` matches under `scripts/ui/` |
| Video / window settings | ABSENT — no fullscreen, window mode, vsync, resolution, or frame-cap control; only the internal render-resolution preset | `:29-59` builds four sections; 0 `DisplayServer.window_set_mode` matches under `scripts/ui/` |
| Language selector | ABSENT | 0 `TranslationServer` matches under `scripts/ui/` |
| Localization of the panel itself | ABSENT — every heading, label, toggle, note, and confirmation body is hardcoded English (about 50 strings) | `:37`, `:44`, `:66`, `:81`, `:111-114`, `:127`, `:140-162`, `:201-377`, `:384-403`, `:452-456`; 0 `tr(` calls |
| Hint text | BROKEN — reads `"Esc: back to main menu"`, but `ui_cancel` only closes the overlay and returns to whatever was underneath | `:44` vs `:545-550` |
| Mouse mode on close | BROKEN — captures the cursor whenever a node in the `player` group exists, so closing settings that were opened from the pause menu or from the hub can capture the mouse while another menu is still open | `:534-542`; `pause_menu.gd:80-82` |
| Save write per slider tick | PARTIAL — every accessibility step writes the whole save file, and every pixel slider step calls `save_and_apply()`, which clears material caches and reapplies project settings | `:76`, `:96`, `:107`; `accessibility_settings.gd:24-34` → `local_save.gd:406-407`; `:490` → `pixel_diorama_settings.gd:176-190` |
| Backup list freshness | PARTIAL — built once inside `_build_ui_if_needed`, which early-returns on later opens, so the list never reflects backups rotated in during the session | `:29-31`, `:58`, `:387` |
| Slider value display | PARTIAL — pixel sliders show raw floats with three decimals (`"Pixel scale (4.000)"`); volume sliders show no value at all; the accessibility sliders show neither name nor value | `:476`, `:488`; `:165-179` |
| Section styling | PARTIAL — the Accessibility heading skips `style_section_title`, unlike Audio, Pixel Diorama, and Advanced | `:65-67` vs `:139-142`, `:200-203`, `:383-386` |
| Presets / reset | PARTIAL — only the pixel section has a restore action; accessibility and audio have no reset-to-default | `:366-372` |
| Scroll ergonomics | PARTIAL — about 40 rows in one 380-px scroll with no tabs, categories, or search | `:45-58` |
| `_hint_label` field | STUB — assigned at `:44` and never read again | `:7`, `:44` |
| Icons | ABSENT — no icon or glyph anywhere; all rows are text | `:62-462` |

## Related
- Improvement plan: [`../actual_improvements/ui/settings.md`](../actual_improvements/ui/settings.md)
- [`display_settings.md`](display_settings.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`pause_menu.md`](pause_menu.md) · [`title_main_continue.md`](title_main_continue.md) · [`dialogue_quests.md`](dialogue_quests.md)
- [`../accessibility.md`](../accessibility.md) · [`../audio-director.md`](../audio-director.md) · [`../pixel-diorama-settings.md`](../pixel-diorama-settings.md) · [`../local-save.md`](../local-save.md) · [`../hit-feedback.md`](../hit-feedback.md)
