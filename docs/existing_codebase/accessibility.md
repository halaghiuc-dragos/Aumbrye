# Accessibility

`AccessibilitySettings` stores five player prefs under the LocalSave meta key `accessibility` and exposes them to settings UI and runtime consumers. Prefs load on title/main-menu/settings open and apply through `DisplaySettings`, `DialogueUI.refresh_accessibility`, or direct reads. `colorblind_mode` tints floating damage numbers and status icon borders via `get_damage_color`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/accessibility/accessibility_settings.gd` | `AccessibilitySettings` â€” static prefs, save/load, `get_damage_color` |
| `apps/game/client/scripts/ui/display_settings.gd` | `DisplaySettings.apply()` â€” writes `content_scale_factor` from `ui_scale` |
| `apps/game/client/scripts/ui/settings_ui.gd` | Builds the Accessibility section, live slider labels, dialogue subtitle refresh |
| `apps/game/client/scripts/combat/hit_feedback.gd` | Reads shake/vibration prefs; passes `damage_type` to damage numbers |
| `apps/game/client/scripts/combat/damage_number.gd` | `Label3D` spawn; tints via `get_damage_color(damage_type)` |
| `apps/game/client/scripts/ui/dialogue_ui.gd` | `subtitle_scale` on each line and `refresh_accessibility()` for live updates |
| `apps/game/client/scripts/ui/combat_hud.gd` | Status icon tint/border from `get_damage_color` + status `damageType` |

## How it works

### Prefs and persistence
`SAVE_KEY := "accessibility"` (`accessibility_settings.gd:6`). Defaults (`accessibility_settings.gd:8-13`):

| Pref | Type | Default |
|------|------|---------|
| `ui_scale` | float | `1.0` |
| `reduce_camera_shake` | bool | `false` |
| `reduce_hitstop` | bool | `false` |
| `colorblind_mode` | String | `"default"` |
| `subtitle_scale` | float | `1.0` |
| `vibration_intensity` | float | `1.0` |

`load_from_save()` (`accessibility_settings.gd:16-23`) reads `LocalSave.get_meta_data()[SAVE_KEY]`. `save()` (`accessibility_settings.gd:26-37`) writes the six keys and calls `LocalSave.autosave()`.

Load call sites: `title_screen.gd:14`, `main_menu.gd:19`, `player_controls.gd:17`, `settings_ui.gd:26`.

### Per-setting consumers

**`ui_scale`.** Settings slider `0.8`â€“`1.5` step `0.05` with live `"UI scale 1.25x"` label (`settings_ui.gd:74-85`). On change and on boot, `DisplaySettings.apply()` (`display_settings.gd:7-11`) sets `tree.root.content_scale_factor = clampf(ui_scale, 0.75, 1.75)`. Also applied from `title_screen.gd:15`, `main_menu.gd:20`, `player_controls.gd:18`.

**`reduce_camera_shake`.** Checkbox `"Reduce camera shake"` (`settings_ui.gd:87-95`). `HitFeedback._apply_camera_punch` returns early when true (`hit_feedback.gd:145-146`). `_apply_camera_shake` zeroes the timer and camera offsets when true (`hit_feedback.gd:171-175`).

**`vibration_intensity`.** Slider `0.0`â€“`1.0` with label `"Controller vibration Off"` at `0.0` or `"Controller vibration 45%"` at non-zero (`settings_ui.gd:108-114`, `_format_vibration_label`). `_apply_vibration` (`hit_feedback.gd:191-198`) skips when `<= 0.0`, otherwise `Input.start_joy_vibration(joypads[0], 0.0, intensity * 0.45, 0.12)`.

**`subtitle_scale`.** Slider `0.8`â€“`1.6` with live `"Subtitle scale 1.50x"` label (`settings_ui.gd:96-107`). On each `line_changed`, `dialogue_ui.gd:_apply_subtitle_scale` sets speaker font to `int(14 * subtitle_scale)` and body font to `int(16 * subtitle_scale)`. Changing the slider while dialogue is open calls `refresh_accessibility()` via `settings_ui.gd:_refresh_open_dialogue_subtitles`.

**`colorblind_mode`.** OptionButton maps indices to `"default"`, `"protanopia"`, `"deuteranopia"`, `"tritanopia"` (`settings_ui.gd:120-139`). `get_damage_color(damage_type)` (`accessibility_settings.gd:40-47`) returns remapped `Color`s for fire/frost/poison/arcane/physical via `_default_damage_color` / `_cb_damage_color` (`accessibility_settings.gd:50-87`). Consumers: `damage_number.gd:41` (floating numbers), `combat_hud.gd:223-232` (status icon tint/border from status JSON `damageType`), `hit_feedback.gd` / `hitbox.gd` / `hurtbox.gd` (pass `damage_type` through hit pipeline).

### Settings UI section
`_build_accessibility_section` (`settings_ui.gd:67-149`) also hosts the leaderboard opt-in checkbox (owned by `LeaderboardSettings`, documented under achievements-meta).

## Contracts

**Save key:** `meta.accessibility` with the six fields above.

**Autoload / class dependencies:** `LocalSave`; class names `AccessibilitySettings`, `DisplaySettings`.

**Runtime readers:** `DisplaySettings`, `HitFeedback`, `DamageNumberSpawner`, `DialogueUI`, `CombatHUD`. Colorblind palette centralized in `AccessibilitySettings.get_damage_color`.

**Validation:** `m6_suite.gd` asserts load, `get_damage_color("fire")`, static field round-trip, `a11y.colorblind.has_consumer`, `a11y.colorblind.protanopia_fire_differs`, `a11y.subtitle.applies_on_line`, and no hardcoded hit colors in `damage_number.gd`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| `ui_scale` â†’ `content_scale_factor` | IMPLEMENTED | `display_settings.gd:11`, `settings_ui.gd:74-85` |
| `reduce_camera_shake` suppresses punch/shake | IMPLEMENTED | `hit_feedback.gd:145-146`, `171-175` |
| `vibration_intensity` scales joy vibration | IMPLEMENTED | `hit_feedback.gd:191-198`, `settings_ui.gd:_format_vibration_label` |
| `subtitle_scale` scales dialogue fonts | IMPLEMENTED | `dialogue_ui.gd:_apply_subtitle_scale`, `settings_ui.gd:96-107` |
| Live subtitle preview while settings open | IMPLEMENTED | `dialogue_ui.gd:refresh_accessibility`, `settings_ui.gd:_refresh_open_dialogue_subtitles` |
| `colorblind_mode` / `get_damage_color` on damage numbers | IMPLEMENTED | `damage_number.gd:41`, `hit_feedback.gd`, `hitbox.gd:147`, `hurtbox.gd:148` |
| `colorblind_mode` on status icons | IMPLEMENTED | `combat_hud.gd:223-232` |
| Screen-reader / remappable input a11y | ABSENT | Searched `scripts/accessibility/` â€” only settings file |

## Related
- Improvement plan: [`../actual_improvements/accessibility.md`](../actual_improvements/accessibility.md) - **FINISHED**
- [`ui/settings.md`](ui/settings.md), [`ui/display_settings.md`](ui/display_settings.md), [`hit-feedback.md`](hit-feedback.md), [`ui/dialogue_quests.md`](ui/dialogue_quests.md), [`achievements-meta.md`](achievements-meta.md)
