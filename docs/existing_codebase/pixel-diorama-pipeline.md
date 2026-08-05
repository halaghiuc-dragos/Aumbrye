# Pixel diorama pipeline

Autoload `PixelDioramaViewport` renders the shared 3D world through a `SubViewport` sized to an integer divisor of the window and lets `SubViewportContainer` upscale the result with nearest-neighbour filtering. It is on the live play path: every playable scene attaches to it (`hub.gd:117`, `castle_run.gd:507`, `waves_run.gd:396`, `combat_arena.gd:31`), and it auto-attaches any new `current_scene` that is not in the `pixel_viewport_exclude` group.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/pipeline/pixel_diorama_viewport.gd` | Autoload `PixelDioramaViewport` — builds the layer/container/viewport/camera, mirrors the gameplay camera, applies the screen finish |
| `apps/game/client/scripts/art/pipeline/pixel_diorama_bootstrap.gd` | `PixelDioramaBootstrap` (`RefCounted`) — static `prime()` / `attach()` / `attach_deferred()` helpers |
| `apps/game/client/scripts/validation/suites/pixel_pipeline_suite.gd` | `graphics` suite — file-existence and autoload-path assertions only |

## How it works

**Boot.** `PixelDioramaBootstrap.prime()` calls `PixelDioramaSettings.load_from_save()` then `PixelDioramaSettings.apply_rendering_project_settings()`. It is called from `run_flow.gd:56`, `title_screen.gd:16`, `hub.gd:42`, and `combat_arena.gd:29`.

**Node construction** (`_build_nodes`, `pixel_diorama_viewport.gd:58-83`), all created in code, no scene file:

| Node | Name | Notable settings |
|------|------|------------------|
| `CanvasLayer` | `PixelDioramaViewportLayer` | `layer = -1`, `visible = false` until the pipeline is enabled |
| `SubViewportContainer` | `PixelViewportContainer` | `PRESET_FULL_RECT`, `stretch = true`, `MOUSE_FILTER_IGNORE` |
| `SubViewport` | `PixelSubViewport` | `own_world_3d = false`, `disable_3d = false`, `transparent_bg = false`, `gui_disable_input = true`, `render_target_update_mode = UPDATE_ALWAYS` |
| `Camera3D` | `PixelRenderCamera` | `current = false` at build time |

The scene graph is never reparented into the `SubViewport`. Because `own_world_3d = false`, the `SubViewport` sees the same `World3D` as the root; only the camera is duplicated. The file's header comment records `own_world_3d`, `scaling_3d_scale`, and pivot snapping as rejected alternatives.

**Camera mirroring** (`_process`, `:86-101`). Every frame, while `PixelDioramaSettings.low_res_viewport_enabled` is true, the render camera copies `projection`, `fov`, `near`, `far`, `keep_aspect`, and `cull_mask` from `_source_camera`, and sets `global_transform` from `_mirrored_transform()` → `PixelCameraSnap.snap_transform(source.global_transform, source.fov, SNAP_FOCUS_DISTANCE)`. `SNAP_FOCUS_DISTANCE` is the constant `5.0` (`:12`). Snapping is applied to the render camera only; the comment at `:104-105` records that snapping the gameplay `CameraPivot` decoupled yaw from movement and broke `SpringArm3D` follow.

**Source camera binding** (`_bind_source_camera`, `:280-289`). Finds the first node in group `player` (falling back to a child named `Player`) and resolves the hard-coded path `CameraPivot/SpringArm3D/Camera3D`. If that node is missing, `_source_camera` stays `null` and `_process` retries the bind every frame.

**Enable/disable** (`:254-277`). `_enable_pipeline()` sets `root.scaling_3d_scale = 1.0`, saves the previous `root.disable_3d` into `_root_3d_was_disabled` (only when the layer is not already visible), sets `root.disable_3d = true`, shows the layer, clears `_source_camera.current`, and sets `_render_camera.current = true`. `_disable_pipeline()` restores `root.disable_3d` from `_root_3d_was_disabled`, returns `current` to the source camera, and hides the layer.

**Internal resolution** (`_apply_internal_size`, `:186-212`). The resolution is expressed as an integer divisor of the window, not an absolute size, because `SubViewportContainer.stretch` drives the `SubViewport` size and a fractional ratio would put the upscale on non-integer pixel boundaries. `_container.stretch` is toggled off first because `SubViewport.size` cannot change while stretch is on.

- Native preset (`PixelDioramaSettings.is_native_hd_preset()`): `_viewport.size = target`, `stretch_shrink = 1`, `active_render_height = target.y`. `_enforce_native_viewport_size()` re-asserts this every frame from `_process` (`:89-90`).
- Non-native preset: `shrink = maxi(1, int(round(window_height / maxi(90, target.y))))`, `active_render_height = round(window_height / shrink)`.

In both cases `snap_2d_transforms_to_pixel` and `snap_2d_vertices_to_pixel` are set on the `SubViewport`, and the container's `texture_filter` is `TEXTURE_FILTER_NEAREST` or `TEXTURE_FILTER_LINEAR` depending on `PixelDioramaSettings.nearest_texture_filter`.

**Screen finish** (`_apply_screen_finish`, `:227-236`). When `screen_finish_enabled`, `PixelDioramaSettings.make_screen_finish_material()` (shader `res://assets/shared/pixel_screen_finish.gdshader`) is assigned as the container's `material`, so the pass runs on the low-res texture *before* the upscale.

**Damage vignette.** `pulse_damage_vignette(strength := 0.7)` sets the `damage_pulse` shader parameter and tweens it back to `0.0` over `0.28` s. Called with `0.72 * feedback_intensity` from `hit_feedback.gd:168` and with `0.22` from `combat_hud.gd:463`, both guarded by `has_method`.

**Attach / detach.** `attach_to_scene(scene_root)` detaches any previous scene, connects `tree_exiting` on the new one, defers `_bind_source_camera`, calls `apply_settings()`, and emits `world_attached`. `bootstrap_scene()` is the deferred entry used by `PixelDioramaBootstrap.attach_deferred()` and additionally runs `PixelDioramaSettings.apply_to_scene()`. `_on_root_child_entered` → `_try_auto_attach` attaches any newly entered root child that is `get_tree().current_scene`, is not a `Window`, and is not in group `pixel_viewport_exclude`.

**Debug dump.** `_ready()` schedules a 3.0 s one-shot timer to `_dbg_dump()` (`:29`). In debug builds it walks the entire tree, counting `GeometryInstance3D.cast_shadow` values and printing one line per `DirectionalLight3D` plus the active rendering method (`:32-55`).

## Contracts

- Autoload name `PixelDioramaViewport` → `res://scripts/art/pipeline/pixel_diorama_viewport.gd` (`project.godot:51`). `pixel_pipeline_suite.gd:40-57` asserts this exact mapping.
- `get_gameplay_camera()` is the sanctioned way to get the active `Camera3D` for billboards, lock-on, and HUD projection. Consumers: `combat_hud.gd:452`, `enemy_health_bar.gd:131`, `debug_overlay.gd:131`.
- `pulse_damage_vignette(strength: float)` — called via `has_method` guards, so the autoload can be absent.
- Node names `PixelDioramaViewportLayer`, `PixelViewportContainer`, `PixelSubViewport`, `PixelRenderCamera`.
- Player camera path contract: `CameraPivot/SpringArm3D/Camera3D` under the `player` group node.
- Scene opt-out: group `pixel_viewport_exclude`.
- `PixelDioramaBootstrap._get_viewport()` resolves the autoload by node name from `SceneTree.root`, so it works from `RefCounted` static context.
- Signal `world_attached(scene_root: Node)` is declared and emitted; nothing connects to it.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| SubViewport mirror + nearest upscale | IMPLEMENTED | `pixel_diorama_viewport.gd:58-101` |
| Screen finish pass on low-res texture | IMPLEMENTED | `pixel_diorama_viewport.gd:227-236` |
| Damage vignette pulse | IMPLEMENTED | `pixel_diorama_viewport.gd:239-251` |
| Auto-attach on scene change | IMPLEMENTED | `pixel_diorama_viewport.gd:301-318` |
| Shipped default is the `1920 x 1080` native preset (`stretch_shrink = 1`, `pixel_scale 2.0`) | PLACEHOLDER | `pixel_diorama_settings.gd:32-33`, `:64-75`; `pixel_diorama_viewport.gd:192-196` |
| `world_attached` signal | STUB | emitted at `pixel_diorama_viewport.gd:144`, no connections in the repo |
| `get_subviewport()`, `get_render_camera()`, `get_world_root()` | STUB | defined at `:168`, `:172`, `:176`; no call sites |
| `SNAP_FOCUS_DISTANCE` fixed at 5.0 m regardless of boom length | FAKE | `pixel_diorama_viewport.gd:12`, `:106-111` |
| `_dbg_dump()` full-tree walk + `print()` in every debug build | PLACEHOLDER | `pixel_diorama_viewport.gd:29`, `:32-55` |
| Validation coverage | PARTIAL | `pixel_pipeline_suite.gd:14-77` asserts file existence, two autoload paths, and two substrings in the surface shader; no behavioural assertion |

## Related
- Improvement plan: [`../actual_improvements/pixel-diorama-pipeline.md`](../actual_improvements/pixel-diorama-pipeline.md)
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — every tunable this module reads
- [`pixel-camera-snap.md`](pixel-camera-snap.md) — the grid snap applied in `_mirrored_transform()`
- [`pixel-style.md`](pixel-style.md) — the surface/emissive shaders the viewport renders
- [`ui/display_settings.md`](ui/display_settings.md) — the Settings controls that drive `apply_settings()`
