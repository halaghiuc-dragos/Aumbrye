# Display settings — improvement plan

## Current state
`display_settings.gd` is twelve lines that set `root.content_scale_factor` from `AccessibilitySettings.ui_scale`. It is named for the display domain but covers one accessibility field; nothing in the game can change window mode, vsync, monitor, frame cap, or resolution. The project's `integer` stretch scale mode probably rounds fractional UI scales back to `1x`. Four separate startup paths call `apply()`. See [`../existing_codebase/ui/display_settings.md`](../existing_codebase/ui/display_settings.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DSP-01 | P0 | No display settings exist. Window mode, borderless, monitor, vsync, and frame cap cannot be changed from inside the game, on any platform. | `:7-11`; 0 `DisplayServer.window_set_mode` matches under `scripts/ui/` |
| DSP-02 | P1 | UI scale may be silently ineffective: `window/stretch/scale_mode="integer"` rounds the final stretch scale down to a whole number, so `content_scale_factor` values between `1.05` and `1.5` can round back to `1x`. | `project.godot:57-60`; `:11` |
| DSP-03 | P1 | The clamp range `0.75 … 1.75` and the slider range `0.80 … 1.50` are independent literals in two files. | `:11`; `settings_ui.gd:70-72` |
| DSP-04 | P1 | Changing scale does not re-lay-out code-built panels; those that computed a half-size on open keep the old geometry until reopened. | `:7-11`; `settings_ui.gd:518-531` |
| DSP-05 | P2 | No change signal, so every consumer must remember to call `apply()`; there are already four startup call sites doing it redundantly. | `title_screen.gd:15`, `main_menu.gd:20`, `player_controls.gd:18`, `settings_ui.gd:23` |
| DSP-06 | P2 | Misplaced and misnamed: a static non-UI helper in `scripts/ui/` named for a domain it does not implement. | `:1-11` |

## Target design

### A real display service
`scripts/app/display_service.gd`, autoloaded as `DisplayService`, owns everything the window and the viewport need:

| Field | Type | Applied through |
|---|---|---|
| `window_mode` | `windowed` / `borderless` / `fullscreen` | `DisplayServer.window_set_mode` + `window_set_flag(WINDOW_FLAG_BORDERLESS, …)` |
| `window_size` | `Vector2i` | `DisplayServer.window_set_size`, clamped to the usable screen rect |
| `monitor_index` | `int` | `DisplayServer.window_set_current_screen` |
| `vsync_mode` | `disabled` / `enabled` / `adaptive` | `DisplayServer.window_set_vsync_mode` |
| `max_fps` | `0` = uncapped, else `30…360` | `Engine.max_fps` |
| `ui_scale` | `float` | `root.content_scale_factor` |
| `hud_safe_area` | `float` `0.0…0.1` | HUD margin multiplier for TV overscan |

`DisplayService.apply_all()` runs once from the boot service (see [`title_main_continue.md`](title_main_continue.md)); `display_settings.gd` is deleted and its four call sites collapse to that one (DSP-01, DSP-05, DSP-06).

`DisplayService` emits `display_changed(field, value)`. `combat_hud.gd`, `MenuStack`, and the minimap listen and re-lay-out; every code-built modal recomputes its clamped half-size on `display_changed` instead of only on open (DSP-04).

### UI scale that actually scales
Two related changes:
1. `SCALE_MIN = 0.75`, `SCALE_MAX = 1.75`, `SCALE_STEP = 0.05` become constants on `DisplayService`, and the settings row reads its range from them, so the clamp and the slider cannot diverge (DSP-03).
2. Because `scale_mode = "integer"` conflicts with fractional UI scale, UI scale is applied as a `Theme` scale rather than a viewport stretch: `DisplayService` sets `root.content_scale_factor` only at whole steps (`1.0`, `2.0`) and otherwise drives a `ui_text_scale` on the shared theme's font sizes and control minimum sizes. The pixel-art world keeps integer stretch; the UI layer scales in typography instead of resampling (DSP-02).

Rejected alternative: switching `scale_mode` to `fractional`. That would blur the pixel-art world for a UI-only benefit and undo the choice recorded in `project.godot:60`.

### Persistence
A `display` block in the meta save:

```json
"display": {
  "window_mode": "windowed",
  "window_size": [1920, 1080],
  "monitor_index": 0,
  "vsync_mode": "enabled",
  "max_fps": 0,
  "ui_scale": 1.0,
  "hud_safe_area": 0.0
}
```

`ui_scale` moves out of the `accessibility` block with a save migration that copies the old value forward and leaves the old key readable for one version (see [`../save-migrator.md`](../save-migrator.md)).

### Safety rails
- On boot, if the persisted `window_size` does not fit any connected monitor's usable rect, fall back to windowed at the largest fitting `16:9` size and log once.
- If the persisted `monitor_index` no longer exists, fall back to `0`.
- Exclusive fullscreen changes are applied with a confirmation timeout: the setting reverts after `10` s unless the player confirms, so an unusable mode cannot lock the player out.

## Work plan
1. **Create `DisplayService`** with the fields, `apply_all()`, `display_changed`, and boot-safety fallbacks (DSP-01).
2. **Delete `display_settings.gd`** and repoint `title_screen.gd:15`, `main_menu.gd:20`, `player_controls.gd:18`, `settings_ui.gd:23` and `:77` at the boot service and the settings row (DSP-05, DSP-06).
3. **Move the scale constants** onto `DisplayService` and have the settings schema read them (DSP-03).
4. **Split UI scale** into integer viewport steps plus theme text scale (DSP-02).
5. **Add the `display` save block and the migration** for `ui_scale`.
6. **Relayout on change** — have the HUD, `MenuStack`, and modals listen to `display_changed` (DSP-04).
7. **Fullscreen confirmation timeout** and monitor/size fallbacks.

## Data and schema changes
- New `scripts/app/display_service.gd`, autoloaded before `PlayerControls`.
- `scripts/ui/display_settings.gd` deleted.
- New meta-save `display` block; `accessibility.ui_scale` migrated.
- Display rows added to the settings schema (see [`settings.md`](settings.md)).

## Acceptance criteria
- [ ] Window mode, monitor, size, vsync, and frame cap can be changed in game and survive a restart.
- [ ] A UI scale of `1.25` visibly enlarges menu text with `scale_mode = "integer"` still set.
- [ ] The world render stays pixel-crisp at every UI scale.
- [ ] The scale range appears exactly once in the codebase.
- [ ] Changing UI scale while a modal is open re-lays-out that modal immediately.
- [ ] A saved window size that no longer fits any monitor falls back to a windowed size that does, with one log line.
- [ ] Entering exclusive fullscreen and pressing nothing reverts to the previous mode within `10` s.
- [ ] `display_settings.gd` no longer exists and no script references it.

## Validation
Extend `apps/game/client/scripts/validation/suites/m6_suite.gd`:

| Test id | Assertion |
|---|---|
| `display.service_present` | `DisplayService` is an autoload and exposes all seven fields |
| `display.legacy_helper_gone` | no file at `res://scripts/ui/display_settings.gd` and no reference to `DisplaySettings` |
| `display.roundtrip` | setting each field, saving, reloading, and calling `apply_all()` reproduces the same values |
| `display.scale_single_source` | the literals `0.75` and `1.75` for UI scale appear only in `display_service.gd` |
| `display.text_scale_effect` | `ui_scale = 1.25` increases a menu label's effective font size while `root.content_scale_factor` stays integral |
| `display.relayout_on_change` | with a modal open, emitting `display_changed` changes the modal's panel rect |
| `display.window_size_fallback` | a persisted `4000 x 3000` size on a `1920 x 1080` screen yields a fitting windowed size and one log entry |
| `display.monitor_fallback` | a persisted monitor index above the screen count falls back to `0` |
| `display.fullscreen_revert` | an unconfirmed fullscreen switch reverts after the timeout |
| `display.migration_ui_scale` | a save with `accessibility.ui_scale = 1.2` and no `display` block loads with `DisplayService.ui_scale == 1.2` |

## Related
- Existing behavior: [`../existing_codebase/ui/display_settings.md`](../existing_codebase/ui/display_settings.md)
- [`settings.md`](settings.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`title_main_continue.md`](title_main_continue.md) · [`combat_hud.md`](combat_hud.md)
- [`../accessibility.md`](../accessibility.md) · [`../pixel-diorama-settings.md`](../pixel-diorama-settings.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md) · [`../save-migrator.md`](../save-migrator.md)
