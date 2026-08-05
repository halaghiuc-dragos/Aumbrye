# Pixel diorama pipeline — improvement plan

## Current state

`PixelDioramaViewport` correctly solves the hard part: it mirrors the gameplay camera into a shared-world `SubViewport` sized to an integer divisor of the window, so the nearest-neighbour upscale lands on whole pixels. See [`../existing_codebase/pixel-diorama-pipeline.md`](../existing_codebase/pixel-diorama-pipeline.md). What is wrong is the configuration it ships with and the observability around it: the default resolution preset is `1920 x 1080` native with `pixel_scale = 2.0`, so a fresh install renders at full resolution with a pixel filter faint enough that the whole art direction is invisible. Three public accessors and one signal have no consumers, the snap grid is sized for a hard-coded 5 m camera boom, and the validation suite asserts only that files exist.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PDP-01 | P0 | Shipped default is the `1920 x 1080 (Full HD, default)` native preset: `stretch_shrink = 1` and shader tuning `pixel_scale 2.0 / color_levels 16 / shade_bands 8 / edge_strength 0.1 / pattern_strength 0.2`. A new install does not look like a pixel diorama. | `pixel_diorama_settings.gd:32-33`, `:64-75`; `pixel_diorama_viewport.gd:192-196` |
| PDP-02 | P0 | No behavioural validation. The suite checks file existence, two autoload paths, and two substrings in a shader. Nothing asserts that the render camera is `current`, that `SubViewport.size * stretch_shrink` equals the window height, or that the finish material is bound. | `pixel_pipeline_suite.gd:14-77` |
| PDP-03 | P1 | `SNAP_FOCUS_DISTANCE` is a constant `5.0` m. The actual boom length is whatever `CameraPivot/SpringArm3D.spring_length` is at the time, so the world-space pixel step used for snapping is wrong whenever the camera zooms or the lock-on camera pulls back. | `pixel_diorama_viewport.gd:12`, `:106-111` |
| PDP-04 | P1 | `world_attached(scene_root)` is emitted but has no listeners, and `get_subviewport()`, `get_render_camera()`, and `get_world_root()` have no call sites. Four public API surfaces with no contract. | `pixel_diorama_viewport.gd:9`, `:144`, `:168`, `:172`, `:176` |
| PDP-05 | P1 | `_dbg_dump()` walks the entire scene tree and prints per-light lines 3.0 s after boot in every debug build, with no setting and no way to re-trigger it on demand. | `pixel_diorama_viewport.gd:29`, `:32-55` |
| PDP-06 | P1 | `_process()` does unconditional per-frame work: six property copies, a transform snap, and (for native presets) `_enforce_native_viewport_size()` which compares and may resize the viewport every frame. No dirty check on the source camera transform. | `pixel_diorama_viewport.gd:86-101`, `:215-224` |
| PDP-07 | P1 | The source camera is resolved by the literal path `CameraPivot/SpringArm3D/Camera3D` with no error when it is missing; `_process` silently re-binds every frame forever, so a renamed rig produces a black screen with no diagnostic. | `pixel_diorama_viewport.gd:91-94`, `:280-289` |
| PDP-08 | P2 | `pulse_damage_vignette()` is the only screen-space game feedback hook, is invoked through `has_method` string calls from two places, and has no companion for heal, parry, low-stamina, or status-applied. Strength values are magic numbers at the call sites (`0.72 * feedback_intensity`, `0.22`). | `pixel_diorama_viewport.gd:239-251`; `hit_feedback.gd:168`; `combat_hud.gd:463` |
| PDP-09 | P2 | `_root_3d_was_disabled` is captured only when `_layer.visible` is false. If `_enable_pipeline()` runs while the layer is already visible (it does — `attach_to_scene()` → deferred `_bind_source_camera()` → `_enable_pipeline()`), the saved value is whatever the previous attach recorded, so `_disable_pipeline()` restores a stale flag. | `pixel_diorama_viewport.gd:259-261`, `:272` |

## Target design

### Presets and the shipped default

`RESOLUTION_PRESETS` keeps its shape but gains an explicit `default: true` marker and the default moves to `480 x 270`, which at a 1080-line window gives `stretch_shrink = 4` — an exact integer, four screen pixels per rendered pixel. The two native entries stay as accessibility/performance options and keep their shader overrides. Rationale for `480 x 270` over `320 x 180`: at 320x180 a 1.8 m tall character is 34 px, which is too few to read the ~10-box `DioramaCharacterSkin` silhouette described in [`character-authoring.md`](character-authoring.md); at 480x270 it is 51 px, and 270 divides 1080 exactly.

```gdscript
{"label": "480 x 270 (chunky, default)", "width": 480, "height": 270, "default": true}
```

`apply_beauty_defaults()` selects the preset flagged `default` rather than assigning `DEFAULT_VIEWPORT_WIDTH/HEIGHT` literals.

### Focus distance from the live rig

Replace the constant with a per-frame read of the actual boom, cached on bind:

```gdscript
var _spring_arm: SpringArm3D  # bound alongside _source_camera

func _focus_distance() -> float:
    if is_instance_valid(_spring_arm):
        return maxf(0.5, _spring_arm.spring_length)
    return SNAP_FOCUS_DISTANCE_FALLBACK  # 5.0
```

`_mirrored_transform()` passes `_focus_distance()` to `PixelCameraSnap.snap_transform()`. `SNAP_FOCUS_DISTANCE` is renamed `SNAP_FOCUS_DISTANCE_FALLBACK` so the fallback is honest.

### Camera binding contract

Introduce a group instead of a path. The player rig adds its camera to group `pixel_render_source`; `_bind_source_camera()` prefers `get_first_node_in_group("pixel_render_source")` and falls back to the existing literal path for scenes that have not been updated. Binding failure is reported once per scene:

```gdscript
func _bind_source_camera(scene_root: Node) -> void:
    ...
    if _source_camera == null:
        if not _bind_warned:
            _bind_warned = true
            push_warning("PixelDioramaViewport: no source camera in %s" % scene_root.name)
        return
```

`_bind_warned` resets in `detach()`. Rejected alternative: keep the path and add an exported `NodePath` — that pushes per-scene configuration onto every level author for no gain.

### Per-frame cost

`_process()` gains an early-out when nothing changed:

```gdscript
var _last_source_xform: Transform3D
var _last_source_fov := -1.0

func _process(_delta: float) -> void:
    ...
    var xform := _source_camera.global_transform
    if xform.is_equal_approx(_last_source_xform) and is_equal_approx(_source_camera.fov, _last_source_fov):
        return
```

`_enforce_native_viewport_size()` moves out of `_process` and is called from `_on_root_size_changed()` and `apply_settings()` only. The reason it was in `_process` — `SubViewportContainer.stretch` re-deriving the size — is handled by leaving `stretch_shrink = 1` and `stretch = true` and re-asserting on the two events that can change the window rect.

### Public API

Delete `get_subviewport()`, `get_render_camera()`, and `get_world_root()`. Keep `world_attached` and give it one real consumer: `VfxService` connects to it in `_ready()` and reparents `VfxRoot` under the attached scene so pooled particles are freed with the scene instead of surviving across runs (see [`vfx-service.md`](vfx-service.md), VFX-03).

### Screen-space feedback

Generalise the vignette into a typed pulse API so new feedback does not need new methods:

```gdscript
enum ScreenPulse { DAMAGE, HEAL, PARRY, LOW_STAMINA }

const PULSE_TUNING := {
    ScreenPulse.DAMAGE:      {"param": "damage_pulse", "peak": 0.72, "decay": 0.28, "tint": Color(0.62, 0.08, 0.08)},
    ScreenPulse.HEAL:        {"param": "damage_pulse", "peak": 0.34, "decay": 0.45, "tint": Color(0.24, 0.68, 0.32)},
    ScreenPulse.PARRY:       {"param": "damage_pulse", "peak": 0.55, "decay": 0.16, "tint": Color(0.98, 0.88, 0.35)},
    ScreenPulse.LOW_STAMINA: {"param": "damage_pulse", "peak": 0.22, "decay": 0.60, "tint": Color(0.35, 0.32, 0.52)},
}

func pulse_screen(kind: ScreenPulse, scale: float = 1.0) -> void
```

`pixel_screen_finish.gdshader` gains a `uniform vec4 pulse_tint : source_color` and `damage_tint` becomes that uniform's default, so one edge-weighted pulse path serves all four. `pulse_damage_vignette()` stays as a thin deprecated wrapper for one release so the two `has_method` call sites keep working, then both call sites move to `pulse_screen(ScreenPulse.DAMAGE, feedback_intensity)`.

### Debug dump

`_dbg_dump()` moves behind `DisplayServer`-independent explicit opt-in: it runs only when `OS.get_environment("AUMBRYE_GFX_DUMP") != ""`, and it is also exposed as `dump_render_state() -> Dictionary` returning the counts instead of printing, so `debug_overlay.gd` can show them and the validation suite can assert on them.

### `disable_3d` bookkeeping

`_root_3d_was_disabled` becomes a nullable capture that is only written when it has no value, and is cleared in `detach()`:

```gdscript
var _root_3d_was_disabled: Variant = null   # bool once captured

func _enable_pipeline() -> void:
    ...
    if _root_3d_was_disabled == null:
        _root_3d_was_disabled = root.disable_3d
    root.disable_3d = true
```

## Work plan

1. **Default preset** — `pixel_diorama_settings.gd`: add `default: true` to a new `480 x 270` entry, remove the `native` flag from nothing (both HD entries stay), and rewrite `apply_beauty_defaults()` and the `DEFAULT_VIEWPORT_*` constants to derive from the flagged preset. Closes PDP-01.
2. **Focus distance** — `pixel_diorama_viewport.gd`: bind `_spring_arm` in `_bind_source_camera()`, add `_focus_distance()`, rename the constant, pass the live value into `PixelCameraSnap.snap_transform()`. Closes PDP-03.
3. **Camera binding contract** — `pixel_diorama_viewport.gd` + the player rig scene: add group `pixel_render_source`, prefer the group, warn once on failure. Closes PDP-07.
4. **Per-frame cost** — `pixel_diorama_viewport.gd`: transform/fov dirty check in `_process()`, move `_enforce_native_viewport_size()` to `_on_root_size_changed()` and `apply_settings()`. Closes PDP-06.
5. **API cleanup** — delete the three unused accessors; connect `world_attached` in `vfx_service.gd::_ready()` and reparent `VfxRoot` on attach. Closes PDP-04.
6. **`disable_3d` capture** — `pixel_diorama_viewport.gd`: nullable capture, cleared in `detach()`. Closes PDP-09.
7. **Debug dump** — gate `_dbg_dump()` behind `AUMBRYE_GFX_DUMP`, add `dump_render_state() -> Dictionary`. Closes PDP-05.
8. **Screen pulse API** — `pixel_screen_finish.gdshader` gains `pulse_tint`; `pixel_diorama_viewport.gd` gains `ScreenPulse` + `PULSE_TUNING` + `pulse_screen()`; migrate `hit_feedback.gd:168` and `combat_hud.gd:463`. Closes PDP-08.
9. **Validation** — extend `pixel_pipeline_suite.gd` with the assertions listed below. Closes PDP-02.

Each step leaves the game runnable: steps 1–8 are independent of one another, and step 9 only adds assertions.

## Data and schema changes

- `LocalSave` meta block `pixel_diorama` (`pixel_diorama_settings.gd:10`) gains no new keys; `viewport_width`/`viewport_height` continue to carry the preset. Existing saves that hold `1920`/`1080` keep the native preset — this is intentional, only new profiles get the new default.
- No `content/schemas/` file governs pixel settings, and none is added: these are per-machine display settings, not content.
- No save-format change, so no `save_migrator.gd` version bump. `save_migrator.gd:11-26` governs the character save's `schemaVersion` and does not touch the meta block.

## Acceptance criteria

- [ ] A profile with no `pixel_diorama` meta block boots at internal height 270 and `SubViewportContainer.stretch_shrink == 4` in a 1920x1080 window. (PDP-01)
- [ ] With the camera zoomed to `spring_length = 2.0`, `PixelDioramaSettings.camera_snap_step()` receives `2.0`, not `5.0`. (PDP-03)
- [ ] Grepping the repo for `get_subviewport`, `get_render_camera`, and `get_world_root` returns no matches; `world_attached` has exactly one `connect` call site. (PDP-04)
- [ ] With `AUMBRYE_GFX_DUMP` unset, a debug build produces no `[DBG]` output. (PDP-05)
- [ ] Holding the camera still for 60 frames results in zero writes to `_render_camera.global_transform`. (PDP-06)
- [ ] Renaming `CameraPivot` in a test scene produces exactly one `push_warning` and no per-frame log spam. (PDP-07)
- [ ] `pulse_screen(ScreenPulse.HEAL)` tints the vignette green; `pulse_damage_vignette(0.7)` still tints it red. (PDP-08)
- [ ] Attaching scene A, then scene B, then disabling the low-res viewport restores `root.disable_3d` to the value it had before scene A attached. (PDP-09)

## Validation

Extend `apps/game/client/scripts/validation/suites/pixel_pipeline_suite.gd` (category `graphics`) with:

| Test id | Assertion |
|---------|-----------|
| `pixel_pipeline.default_preset` | With `PixelDioramaSettings.apply_beauty_defaults()`, `current_resolution_preset()` points at the entry flagged `default` and `viewport_height == 270` |
| `pixel_pipeline.integer_shrink` | For each of the four non-native presets, `round(1080.0 / preset.height)` reproduces `1080 / preset.height` exactly (no fractional upscale at the reference window size) |
| `pixel_pipeline.render_camera_current` | After `attach_to_scene()` on a fixture `Node3D` containing a `player`-group node with the camera rig, `get_gameplay_camera() == get_render_camera()` and `_render_camera.current` is true |
| `pixel_pipeline.finish_material_bound` | With `screen_finish_enabled`, the container's `material` is a `ShaderMaterial` whose shader path ends with `pixel_screen_finish.gdshader`, and `contrast`/`saturation`/`vignette_strength` match the settings statics |
| `pixel_pipeline.focus_distance_tracks_boom` | With a fixture `SpringArm3D.spring_length = 2.5`, `_focus_distance()` returns `2.5` |
| `pixel_pipeline.no_dead_accessors` | `PixelDioramaViewport.has_method("get_subviewport")` is false (guards against reintroduction) |
| `pixel_pipeline.screen_pulse_params` | `pulse_screen()` for each `ScreenPulse` value sets `pulse_tint` and a non-zero `damage_pulse`, and the value returns to `0.0` after `decay + 0.05` s |
| `pixel_pipeline.debug_dump_gated` | With `AUMBRYE_GFX_DUMP` unset, `dump_render_state()` returns a populated `Dictionary` and `_dbg_dump()` is not scheduled |

Manual checklist (genuinely not automatable — the failure mode is perceptual):

- At the default preset, walking a full lap of the hub plaza shows no shimmer on the fountain rim or the tent roof panels.
- Switching preset from `480 x 270` to `1920 x 1080` and back through Settings does not leave the screen finish unbound or the world at the wrong scale.

## Related
- Existing behaviour: [`../existing_codebase/pixel-diorama-pipeline.md`](../existing_codebase/pixel-diorama-pipeline.md)
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — preset table and project-setting application
- [`pixel-camera-snap.md`](pixel-camera-snap.md) — consumer of the focus distance
- [`vfx-service.md`](vfx-service.md) — new `world_attached` consumer
- [`character-authoring.md`](character-authoring.md) — silhouette pixel budget that motivates the default preset
