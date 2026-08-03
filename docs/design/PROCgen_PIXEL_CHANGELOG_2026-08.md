# August 2026 — Pixel Pipeline, Procgen, and Tooling Changelog

> Session work: camera follow fix, crisp low-res rendering, room-graph procgen, GDScript warning cleanup, MCP plugin fix, enemy HP bar billboarding.  
> **Date:** 2026-08-03

## Pixel diorama viewport (camera + crisp upscale)

### Problem

Earlier attempts to achieve pixel upscaling broke the orbit camera (player spawned in hub but camera stayed at origin) or produced a soft/foggy image.

### Solution

`PixelDioramaViewport` (`apps/game/client/scripts/art/pixel_diorama_viewport.gd`) now uses a **shared-world SubViewport** with a **mirrored render camera**:

- Scene nodes are **not** reparented.
- `SubViewport.own_world_3d = false` — same `World3D` as gameplay.
- Internal resolution 480×270; `SubViewportContainer` uses `TEXTURE_FILTER_NEAREST`.
- Each frame the SubViewport `Camera3D` copies transform, FOV, projection, and cull mask from the player camera.
- Root viewport `disable_3d = true` while pipeline active; player camera `current = false`.

### Orbit camera

`orbit_camera.gd` — removed pixel snap that wrote `global_position` on `CameraPivot` / `Camera3D` (fought `SpringArm3D` follow).

### Integration

Called from `hub.gd`, `castle_run.gd`, `waves_run.gd`, `settings_ui.gd`. Autoload: `PixelDioramaViewport` in `project.godot`.

**Doc:** [PIXEL_DIORAMA_PIPELINE.md](PIXEL_DIORAMA_PIPELINE.md)

---

## Enemy HP bar billboarding

### Problem

With `disable_3d` on the root viewport, `get_viewport().get_camera_3d()` returned null or the wrong camera. HP bars only faced correctly from some angles.

### Solution

- Added `PixelDioramaViewport.get_gameplay_camera()` — returns SubViewport mirror camera when low-res is on, else root camera.
- Updated:
  - `apps/game/client/scripts/ui/enemy_health_bar.gd`
  - `apps/game/client/scripts/ui/combat_hud.gd`
  - `apps/game/client/scripts/debug/debug_overlay.gd`

---

## Room graph procedural generation (client GDScript)

Two-phase Isaac / Shattered Pixel–style generator under `apps/game/client/scripts/dungeon/procgen/`:

| Phase | Modules |
|-------|---------|
| 1 — abstract graph | `room_graph_slot.gd`, `room_graph_config.gd`, `room_graph_generator.gd`, `room_graph.gd`, `room_graph_debug.gd`, `room_graph_paths.gd` |
| 2 — geometry + content | `room_template_catalog.gd`, `room_graph_assigner.gd`, `room_graph_geometry.gd`, `room_content_assigner.gd`, `room_content_validator.gd`, `dungeon_procgen.gd`, `procgen_placements.gd` |

Wired via `local_procgen.gd` → `DungeonProcgen.generate()`.

New validation suites: `room_graph_suite.gd`, `room_content_suite.gd`.

**Doc:** [PROCGEN_ROOM_GRAPH.md](PROCGEN_ROOM_GRAPH.md)

### Known open issues (validation)

Three procgen tests still fail (room count target vs generator output ~11 vs biome 18–22):

- `procgen.different_seeds_differ`
- `room_graph.phase1_validated`
- `m7.procgen.floor_layout_differs`

---

## GDScript warning fixes

| File | Fix |
|------|-----|
| `room_content_assigner.gd`, `room_content_validator.gd`, `procgen_placements.gd`, `room_graph_geometry.gd`, `room_graph_assigner.gd`, `room_graph_generator.gd`, `room_graph_config.gd`, `dungeon_procgen.gd` | Unused params → `_prefix`; `seed` param → `run_seed`; integer division → `int(x / 3.0)` (**not** `//`); enum type `RoomGraphSlot.SlotType` |

---

## Godot MCP plugin fix

`scene_run` crashed in Godot 4.7 (`EditorInterface` opcode 68).

| File | Change |
|------|--------|
| `addons/godot_mcp/tools/base_tools.gd` | Cache `EditorInterface` via `MCPBaseTool.set_editor_interface()` instead of `Engine.get_singleton` |
| `addons/godot_mcp/plugin.gd` | Call `set_editor_interface(get_editor_interface())` on plugin load |

Updated [KNOWN_ISSUES_M6.md](KNOWN_ISSUES_M6.md) MCP section.

---

## Documentation changes

| Action | Path |
|--------|------|
| **Created** | `docs/design/PIXEL_DIORAMA_PIPELINE.md` |
| **Created** | `docs/design/PROCGEN_ROOM_GRAPH.md` |
| **Created** | `docs/design/PROCgen_PIXEL_CHANGELOG_2026-08.md` (this file) |
| **Updated** | `docs/plan/systems/06-PROCEDURAL.md` |
| **Updated** | `docs/plan/systems/16-ART-PIPELINE.md` |
| **Updated** | `docs/plan/systems/01-MOVEMENT-CAMERA.md` |
| **Updated** | `docs/design/VALIDATION_PLATFORM.md` |
| **Updated** | `docs/design/KNOWN_ISSUES_M6.md` |
| **Removed** | `docs/design/HUB_ENHANCEMENT_PLAN.md` — implemented in `hub_diorama.gd` / `pixel_diorama_style.gd` (see M4 log) |

---

## Validation run (reference)

`./scripts/run-mcp-validation.ps1` — **414 passed, 3 failed** (procgen room-count mismatches above).
