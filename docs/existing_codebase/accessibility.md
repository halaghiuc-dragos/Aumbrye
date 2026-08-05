# Accessibility

`AccessibilitySettings` stores five player prefs under the LocalSave meta key `accessibility` and exposes them to settings UI and a few runtime consumers. Prefs load on title/main-menu/settings open and apply through `DisplaySettings` or direct reads. Colorblind mode is saved and has a palette helper, but no combat or UI caller uses it.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/accessibility/accessibility_settings.gd` | `AccessibilitySettings` — static prefs, save/load, `get_damage_color` |
| `apps/game/client/scripts/ui/display_settings.gd` | `DisplaySettings.apply()` — writes `content_scale_factor` from `ui_scale` |
| `apps/game/client/scripts/ui/settings_ui.gd` | Builds the Accessibility section and persists on change |
| `apps/game/client/scripts/combat/hit_feedback.gd` | Reads `reduce_camera_shake` and `vibration_intensity` |
| `apps/game/client/scripts/ui/dialogue_ui.gd` | Reads `subtitle_scale` when a dialogue line is shown |

## How it works

### Prefs and persistence
`SAVE_KEY := "accessibility"` (`accessibility_settings.gd:6`). Defaults (`accessibility_settings.gd:8-12`):

| Pref | Type | Default |
|------|------|---------|
| `ui_scale` | float | `1.0` |
| `reduce_camera_shake` | bool | `false` |
| `colorblind_mode` | String | `"default"` |
| `subtitle_scale` | float | `1.0` |
| `vibration_intensity` | float | `1.0` |

`load_from_save()` (`accessibility_settings.gd:15-21`) reads `LocalSave.get_meta_data()[SAVE_KEY]`. `save()` (`accessibility_settings.gd:24-34`) writes the five keys and calls `LocalSave.autosave()`.

Load call sites: `title_screen.gd:14`, `main_menu.gd:19`, `player_controls.gd:17`, `settings_ui.gd:22`.

### Per-setting consumers

**`ui_scale`.** Settings slider `0.8`–`1.5` step `0.05` (`settings_ui.gd:68-77`). On change and on boot, `DisplaySettings.apply()` (`display_settings.gd:7-11`) sets `tree.root.content_scale_factor = clampf(ui_scale, 0.75, 1.75)`. Also applied from `title_screen.gd:15`, `main_menu.gd:20`, `player_controls.gd:18`.

**`reduce_camera_shake`.** Checkbox in settings (`settings_ui.gd:80-86`). `HitFeedback._apply_camera_punch` returns early when true (`hit_feedback.gd:116-117`). `_apply_camera_shake` zeroes the timer and camera offsets when true (`hit_feedback.gd:138-142`).

**`vibration_intensity`.** Slider `0.0`–`1.0` (`settings_ui.gd:99-108`). `_apply_vibration` (`hit_feedback.gd:156-163`) skips when `<= 0.0`, otherwise `Input.start_joy_vibration(joypads[0], 0.0, intensity * 0.45, 0.12)`.

**`subtitle_scale`.** Slider `0.8`–`1.6` (`settings_ui.gd:88-97`). On each `line_changed`, `dialogue_ui.gd:79-81` sets speaker font to `int(14 * subtitle_scale)` and body font to `int(16 * subtitle_scale)`. Changing the slider while dialogue is closed has no live preview until the next line.

**`colorblind_mode`.** OptionButton maps indices to `"default"`, `"protanopia"`, `"deuteranopia"`, `"tritanopia"` (`settings_ui.gd:110-124`). `get_damage_color(damage_type)` (`accessibility_settings.gd:37-44`) returns remapped `Color`s for fire/frost/poison/arcane/physical via `_default_damage_color` / `_cb_damage_color` (`accessibility_settings.gd:47-69`). Grep across `apps/game/client/scripts/` finds **no gameplay caller** of `get_damage_color` — only `m6_suite.gd:281` in validation.

### Settings UI section
`_build_accessibility_section` (`settings_ui.gd:62-133`) also hosts the leaderboard opt-in checkbox (owned by `LeaderboardSettings`, documented under achievements-meta).

## Contracts

**Save key:** `meta.accessibility` with the five fields above.

**Autoload / class dependencies:** `LocalSave`; class names `AccessibilitySettings`, `DisplaySettings`.

**Runtime readers:** `DisplaySettings`, `HitFeedback`, `DialogueUI`. Colorblind palette is internal to `AccessibilitySettings` only.

**Validation:** `m6_suite.gd` asserts load and `get_damage_color("fire")` return a Color, and that static fields round-trip after assignment (`m6_suite.gd:275-296`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| `ui_scale` → `content_scale_factor` | IMPLEMENTED | `display_settings.gd:11`, `settings_ui.gd:74-77` |
| `reduce_camera_shake` suppresses punch/shake | IMPLEMENTED | `hit_feedback.gd:116-117`, `138-142` |
| `vibration_intensity` scales joy vibration | IMPLEMENTED | `hit_feedback.gd:156-163` |
| `subtitle_scale` scales dialogue fonts | IMPLEMENTED | `dialogue_ui.gd:79-81` |
| `colorblind_mode` / `get_damage_color` | FAKE | Saved and selectable (`settings_ui.gd:110-124`); zero gameplay callers of `get_damage_color` outside `m6_suite.gd:281` |
| Live subtitle preview while settings open | ABSENT | Scale applied only inside `_on_line_changed` |
| Screen-reader / remappable input a11y | ABSENT | Searched `scripts/accessibility/` — only this file |

## Related
- Improvement plan: [`../actual_improvements/accessibility.md`](../actual_improvements/accessibility.md)
- [`ui/settings.md`](ui/settings.md), [`ui/display_settings.md`](ui/display_settings.md), [`hit-feedback.md`](hit-feedback.md), [`ui/dialogue_quests.md`](ui/dialogue_quests.md), [`achievements-meta.md`](achievements-meta.md)
