# Pixel Diorama Pipeline

> Crisp low-resolution 3D rendering for the handcrafted pixel-diorama look.  
> Settings: `PixelDioramaSettings` (`apps/game/client/scripts/art/pixel_diorama_settings.gd`)  
> Runtime: `PixelDioramaViewport` autoload (`apps/game/client/scripts/art/pixel_diorama_viewport.gd`)

## Overview

The game renders 3D at an internal resolution (default **480×270**), then upscales to the window with **nearest-neighbor** filtering. Pixel shaders on materials (`pixel_diorama_surface.gdshader`, legacy `pixel_diorama.gdshader`) quantize color and add edge/stitch detail on top.

**Important:** The scene graph is **never reparented** into the SubViewport. Player, enemies, and cameras stay in the main world tree so physics and orbit-camera follow remain correct.

## Architecture

```
Player Camera3D (source, current=false when pipeline active)
        │
        │  transform mirrored each frame
        ▼
SubViewport Camera3D (PixelRenderCamera, current=true)
        │
        │  renders shared World3D at 480×270
        ▼
SubViewportContainer (stretch + TEXTURE_FILTER_NEAREST)
        │
        ▼
CanvasLayer (fullscreen over disabled root 3D pass)
```

When low-res mode is enabled:

1. Root viewport `disable_3d = true` (avoids double/blurred composite).
2. Player camera `current = false`; SubViewport mirror camera `current = true`.
3. `SubViewport.own_world_3d = false` — same `World3D` as the game scene.

## Gameplay camera lookup

Billboards and HUD must **not** call `get_viewport().get_camera_3d()` on nodes in the main tree — that viewport has 3D disabled.

Use:

```gdscript
var camera := PixelDioramaViewport.get_gameplay_camera()
```

Used by: `enemy_health_bar.gd`, `combat_hud.gd`, `debug_overlay.gd`.

## User settings (persisted in LocalSave meta)

| Key | Default | Effect |
|-----|---------|--------|
| `low_res_viewport_enabled` | `true` | Toggle SubViewport upscale pipeline |
| `viewport_width` / `viewport_height` | 480 / 270 | Internal render resolution |
| `nearest_texture_filter` | `true` | Nearest upscale + project texture defaults |
| `pixel_scale`, `color_levels`, … | see script | Shader quantization / edge strength |
| `camera_snap_enabled` | `true` | Reserved; orbit camera no longer snaps pivot (was breaking follow) |
| `anti_aliasing_off` | `true` | MSAA / screen-space AA off |

Toggle in-game via Settings UI → **Low-res viewport upscale**.

## Scene integration

Hub, castle run, and waves run call:

```gdscript
PixelDioramaSettings.load_from_save()
PixelDioramaSettings.apply_rendering_project_settings()
PixelDioramaViewport.attach_to_scene(self)  # deferred from _ready
```

`attach_to_scene` binds the player camera and enables the pipeline; it does **not** move nodes.

## Art stack (unchanged)

| Layer | Path |
|-------|------|
| Surface shaders | `apps/game/client/shaders/pixel_diorama_surface.gdshader` |
| Style helpers | `apps/game/client/scripts/art/pixel_diorama_style.gd` |
| Character skins | `apps/game/client/scripts/art/diorama_character_skin.gd` |
| Hub dressing | `apps/game/client/scripts/hub/hub_diorama.gd` |

Low-poly geometry + procedural pixel shaders (not HD-2D billboards). See [16-ART-PIPELINE.md](../plan/systems/16-ART-PIPELINE.md).

## Rejected approaches (do not reintroduce)

| Approach | Why it failed |
|----------|----------------|
| Reparent 3D children into SubViewport | Broke camera follow; broke `NodePath` siblings (HUD → Player) |
| `own_world_3d = true` + reparent | Isolated physics/camera registration |
| `Viewport.scaling_3d_scale` + bilinear | Worked for camera but looked soft/foggy |
| Snapping `CameraPivot.global_position` | Decoupled yaw pivot from player movement |

## Room geometry (2026-08-03)

Single-door templates (boss, treasure, secret, entrance) are **yaw-rotated** at build time so their doorway faces the graph neighbor. Placement uses rotated half-extents for non-square rooms. See `RoomTemplateCatalog.yaw_rad_for_incoming_door()` and `RoomGraphGeometry.build_rooms()`.

## Related docs

- [PROCgen_PIXEL_CHANGELOG_2026-08.md](PROCgen_PIXEL_CHANGELOG_2026-08.md) — full August 2026 change log
- [01-MOVEMENT-CAMERA.md](../plan/systems/01-MOVEMENT-CAMERA.md) — orbit camera + lock-on
