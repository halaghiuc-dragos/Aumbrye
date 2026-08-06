# Accessibility — improvement plan

## Status: FINISHED

## Current state
Five prefs persist under `LocalSave` meta `accessibility` and all affect the live client. `colorblind_mode` routes floating damage numbers and status icon borders/tints through `get_damage_color`. Subtitle scale refreshes an open `DialogueUI` panel; accessibility sliders show live multiplier labels. See [`../existing_codebase/accessibility.md`](../existing_codebase/accessibility.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| A11-01 | P0 | ~~`colorblind_mode` / `get_damage_color` has no gameplay consumer~~ **FINISHED** — `damage_number.gd`, `hit_feedback.gd`, `hitbox.gd`, `hurtbox.gd` | was `accessibility_settings.gd:37-69` only in `m6_suite.gd` |
| A11-02 | P1 | ~~Subtitle scale applied only on new line~~ **FINISHED** — `dialogue_ui.gd:refresh_accessibility`, `settings_ui.gd:_refresh_open_dialogue_subtitles` | was `dialogue_ui.gd:79-81` |
| A11-03 | P1 | ~~Vibration/shake prefs lack labels; no Off at 0.0~~ **FINISHED** — `settings_ui.gd:_format_vibration_label`, scale row labels | was `settings_ui.gd:80-108` |
| A11-04 | P2 | ~~No shared damage-number / status-color path~~ **FINISHED** — `combat_hud.gd:_refresh_status_icons` tints from `damageType` | was zero `get_damage_color` callers outside a11y |

## Target design

### Honest colorblind path
Pick one consumer family and route every type-colored combat cue through it:

```gdscript
# accessibility_settings.gd (existing API kept)
static func get_damage_color(damage_type: String = "physical") -> Color
```

Wire at least:

| Call site | Use |
|-----------|-----|
| Floating damage numbers (or hit feedback flash tint) | `get_damage_color(info.damage_type)` |
| Status icon border / tint where the status JSON declares an elemental type | Same helper |
| Enemy / player health-bar chip for elemental DoT (if present) | Same helper |

Rejected alternative: delete the Setting. The palette tables already exist and match the four modes the UI offers; deleting the control would remove a real a11y need. Wiring is the honest fix.

If no floating damage numbers exist yet, add a minimal `DamageNumber` Label3D spawn from `HitFeedback` / `Hurtbox` so the Setting has a visible effect on day one of the fix — do not ship the option without a surface.

### Subtitle / UI scale feedback
`settings_ui.gd` after writing `subtitle_scale` calls a small `DialogueUI.refresh_accessibility()` if a dialogue panel is open. `DisplaySettings.apply()` already covers `ui_scale`. Add a one-line label under each slider showing the current multiplier (`"UI scale 1.25x"`).

### Settings copy
Label the vibration slider `"Controller vibration"` and treat `0.0` as off in the adjacent value label. Keep the shake checkbox text `"Reduce camera shake"`.

## Work plan

1. **Inventory every red/green type color in combat UI** — list call sites that hardcode elemental `Color(...)` in `hit_feedback.gd`, HUD, status icons. Landable alone; no behaviour change.
2. **Route damage numbers (or flash tint) through `get_damage_color`** — introduce or update the number spawn; assert mode `protanopia` changes fire color away from default `Color(1.0, 0.4, 0.1)`. Closes A11-01 for the primary surface.
3. **Route status / DoT chips through the same helper** where a type string exists. Closes A11-04 for those surfaces.
4. **Live subtitle refresh + slider value labels** — `dialogue_ui.gd`, `settings_ui.gd`. Closes A11-02, A11-03.

## Data and schema changes

No `content/` schema change. Save shape already has `colorblind_mode` (`accessibility_settings.gd:29`); no migrator bump.

## Acceptance criteria
- [x] With `colorblind_mode = "protanopia"`, a fire hit's on-screen damage cue is not the default `Color(1.0, 0.4, 0.1)` and matches `AccessibilitySettings.get_damage_color("fire")`. (A11-01)
- [x] Changing `subtitle_scale` while `DialogueUI` is open updates speaker and body font sizes on the same frame. (A11-02)
- [x] Vibration slider shows a numeric or "Off" label; `0.0` produces no `start_joy_vibration` call. (A11-03)
- [x] Grep for hardcoded elemental damage colors in hit presentation returns zero hits outside `accessibility_settings.gd` tests. (A11-04)

## Validation
Extend `apps/game/client/scripts/validation/suites/m6_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `a11y.colorblind.has_consumer` | File contains a non-test call to `get_damage_color` under `scripts/combat/` or `scripts/ui/` |
| `a11y.colorblind.protanopia_fire_differs` | `get_damage_color("fire")` under `"default"` vs `"protanopia"` returns unequal Colors |
| `a11y.subtitle.applies_on_line` | With `subtitle_scale = 1.5`, after a synthetic `line_changed`, speaker font size equals `21` |

Manual: open Settings, toggle each mode, take one fire hit and one frost hit, confirm colors change.

## Related
- Existing state: [`../existing_codebase/accessibility.md`](../existing_codebase/accessibility.md)
- [`hit-feedback.md`](hit-feedback.md), [`ui/settings.md`](ui/settings.md), [`ui/status_icons_glyphs.md`](ui/status_icons_glyphs.md)
