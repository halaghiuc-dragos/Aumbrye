# Pixel diorama pipeline

Autoload `PixelDioramaViewport` renders the shared 3D world through a `SubViewport` sized to an integer divisor of the window and lets `SubViewportContainer` upscale the result with nearest-neighbour filtering. It is on the live play path: every playable scene attaches to it (`hub.gd:117`, `castle_run.gd:507`, `waves_run.gd:396`, `combat_arena.gd:31`), and it auto-attaches any new `current_scene` that is not in the `pixel_viewport_exclude` group.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/pipeline/pixel_diorama_viewport.gd` | Autoload `PixelDioramaViewport` — builds the layer/container/viewport/camera, mirrors the gameplay camera, applies the screen finish |
| `apps/game/client/scripts/art/pipeline/pixel_diorama_bootstrap.gd` | `PixelDioramaBootstrap` (`RefCounted`) — static `prime()` / `attach()` / `attach_deferred()` helpers |
| `apps/game/client/scripts/validation/suites/pixel_pipeline_suite.gd` | `graphics` suite — file existence, autoload paths, and behavioural assertions |

## How it works

**Boot.** `PixelDioramaBootstrap.prime()` calls `PixelDioramaSettings.load_from_save()` then `PixelDioramaSettings.apply_rendering_project_settings()`. It is called from `run_flow.gd:56`, `title_screen.gd:16`, `hub.gd:42`, and `combat_arena.gd:29`.

**Node construction** (`_build_nodes`, `pixel_diorama_viewport.gd`), all created in code, no scene file:

| Node | Name | Notable settings |
|------|------|------------------|
| `CanvasLayer` | `PixelDioramaViewportLayer` | `layer = -1`, `visible = false` until the pipeline is enabled |
| `SubViewportContainer` | `PixelViewportContainer` | `PRESET_FULL_RECT`, `stretch = true`, `MOUSE_FILTER_IGNORE` |
| `SubViewport` | `PixelSubViewport` | `own_world_3d = false`, `disable_3d = false`, `transparent_bg = false`, `gui_disable_input = true`, `render_target_update_mode = UPDATE_ALWAYS` |
| `Camera3D` | `PixelRenderCamera` | `current = false` at build time |

The scene graph is never reparented into the `SubViewport`. Because `own_world_3d = false`, the `SubViewport` sees the same `World3D` as the root; only the camera is duplicated.

**Camera mirroring** (`_process`). While `PixelDioramaSettings.low_res_viewport_enabled` is true, the render camera copies projection properties from `_source_camera` only when transform or `fov` changed (`_last_source_xform`, `_last_source_fov` dirty check). `global_transform` comes from `_mirrored_transform()` → `PixelCameraSnap.snap_transform(source.global_transform, source.fov, _focus_distance())`. `_focus_distance()` reads `_spring_arm.spring_length` when bound, else `SNAP_FOCUS_DISTANCE_FALLBACK` (`5.0`).

**Source camera binding** (`_bind_source_camera`). Prefers the first node in group `pixel_render_source`; falls back to `player` group (or child `Player`) and path `CameraPivot/SpringArm3D/Camera3D`. Binds `_spring_arm` alongside `_source_camera`. Emits one `push_warning` per scene when binding fails (`_bind_warned` resets in `detach()`). Player scene registers its camera in `pixel_render_source` (`player.tscn`).

**Enable/disable.** `_enable_pipeline()` captures `root.disable_3d` into nullable `_root_3d_was_disabled` only on first capture, sets `root.disable_3d = true`, shows the layer, and makes `_render_camera` current. `_disable_pipeline()` restores `disable_3d` from the captured value when non-null.

**Internal resolution** (`_apply_internal_size`). Non-native presets compute `stretch_shrink` as an integer divisor of window height. `_enforce_native_viewport_size()` runs from `apply_settings()` and `_on_root_size_changed()` for native presets only (not per-frame).

**Screen finish** (`_apply_screen_finish`). Shader `res://assets/shared/pixel_screen_finish.gdshader` with `pulse_tint` uniform for edge-weighted pulses.

**Screen pulses.** `pulse_screen(kind: ScreenPulse, scale := 1.0)` drives `damage_pulse` and `pulse_tint` from `PULSE_TUNING` (`DAMAGE`, `HEAL`, `PARRY`, `LOW_STAMINA`). `pulse_damage_vignette(strength)` is a thin wrapper calling `pulse_screen(ScreenPulse.DAMAGE, strength / 0.72)`. Callers: `hit_feedback.gd` (`pulse_screen` DAMAGE), `combat_hud.gd` (low-health DAMAGE pulse).

**Attach / detach.** `attach_to_scene(scene_root)` detaches any previous scene, defers `_bind_source_camera`, calls `apply_settings()`, and emits `world_attached`. `VfxService` connects to `world_attached` and reparents `VfxRoot` under the attached scene.

**Debug.** `dump_render_state() -> Dictionary` returns cast-shadow counts and directional-light summary. `_dbg_dump()` prints that state only when `AUMBRYE_GFX_DUMP` is set; the 3.0 s boot timer is scheduled only in that case.

## Contracts

- Autoload name `PixelDioramaViewport` → `res://scripts/art/pipeline/pixel_diorama_viewport.gd` (`project.godot:51`).
- `get_gameplay_camera()` is the sanctioned active `Camera3D` for billboards, lock-on, and HUD projection.
- `pulse_screen(kind, scale)` and deprecated `pulse_damage_vignette(strength)`.
- Camera group `pixel_render_source` (preferred) or legacy path `CameraPivot/SpringArm3D/Camera3D` under `player`.
- Scene opt-out: group `pixel_viewport_exclude`.
- Signal `world_attached(scene_root)` — one consumer: `VfxService._on_pixel_world_attached`.
- Default resolution preset: `480 x 270` flagged `default: true` in `RESOLUTION_PRESETS`; `apply_beauty_defaults()` selects it.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| SubViewport mirror + nearest upscale | IMPLEMENTED | `pixel_diorama_viewport.gd` |
| Default preset `480 x 270` with `default: true` | IMPLEMENTED | `pixel_diorama_settings.gd` |
| Live spring-arm focus distance | IMPLEMENTED | `_focus_distance()`, `_spring_arm` |
| Camera group binding + bind warning | IMPLEMENTED | `pixel_render_source`, `_bind_warned` |
| Per-frame dirty check | IMPLEMENTED | `_last_source_xform`, `_last_source_fov` |
| `world_attached` → VfxService reparent | IMPLEMENTED | `vfx_service.gd` |
| Screen pulse API + `pulse_tint` shader | IMPLEMENTED | `ScreenPulse`, `pixel_screen_finish.gdshader` |
| Gated debug dump + `dump_render_state()` | IMPLEMENTED | `AUMBRYE_GFX_DUMP` |
| Behavioural validation suite | IMPLEMENTED | `pixel_pipeline_suite.gd` |

## Related
- Improvement plan: [`../actual_improvements/pixel-diorama-pipeline.md`](../actual_improvements/pixel-diorama-pipeline.md) — **FINISHED**
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — every tunable this module reads
- [`pixel-camera-snap.md`](pixel-camera-snap.md) — the grid snap applied in `_mirrored_transform()`
- [`pixel-style.md`](pixel-style.md) — the surface/emissive shaders the viewport renders
- [`vfx-service.md`](vfx-service.md) — `world_attached` consumer
- [`ui/display_settings.md`](ui/display_settings.md) — the Settings controls that drive `apply_settings()`
