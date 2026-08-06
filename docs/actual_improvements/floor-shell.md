# Floor shell — improvement plan

## Status: FINISHED

## Current state

`CastleBlockout` bakes navmesh from static colliders via `parse_source_geometry_data`, defers rebuilds behind `finalize_geometry()`, stores cover in a preserved `CoverObstacles` sibling, builds per-room ceilings with lintels above doorways, and exposes `hide_walls` for authored kits. `FloorShellBuilder` parents perimeter walls under `DungeonRoot` with no dungeon-floor `CeilingSlab`. `CastleRoomScene._resolve_biome_id()` prefers the template's biome. See [`../existing_codebase/floor-shell.md`](../existing_codebase/floor-shell.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| FSH-01 | P0 | Navmesh ignored walls and cover | **FINISHED** — `parse_source_geometry_data` bake (`castle_blockout.gd:323-348`); agent radius 0.45 |
| FSH-02 | P0 | Cover deleted on rebuild | **FINISHED** — `CoverObstacles` sibling preserved (`castle_blockout.gd:151-168`, `:381-395`) |
| FSH-03 | P1 | Four door setters = four bakes | **FINISHED** — `_geometry_dirty` + `finalize_geometry()` (`castle_blockout.gd:84-99`); builder calls once (`dungeon_builder.gd:589`) |
| FSH-04 | P1 | Monolithic ceiling slab | **FINISHED** — per-room `_build_ceiling()` (`castle_blockout.gd:218-256`); `FloorShellBuilder` perimeter only (`floor_shell_builder.gd:21-24`) |
| FSH-05 | P1 | `FloorShell` never freed | **FINISHED** — parented under `DungeonRoot` (`dungeon_builder.gd:112,579`); freed at `:1076-1077` |
| FSH-06 | P1 | No door lintel | **FINISHED** — third segment above `DOOR_HEIGHT` (`castle_blockout.gd:283-295`) |
| FSH-07 | P1 | Wrong biome from `RunFlow` | **FINISHED** — template id first (`castle_room_scene.gd:48-52`) |
| FSH-08 | P2 | `add_height_stairs` dead | **FINISHED** — `DungeonBuilder._build_height_transitions()` (`dungeon_builder.gd:371`) |
| FSH-09 | P2 | `Shortcut*` scan dead | **FINISHED** — removed from `_compute_bounds` |
| FSH-10 | P2 | Per-segment wall bodies | **FINISHED** — shared `_walls_body` via `_create_walls_body()` (`castle_blockout.gd:298-318`) |
| FSH-11 | P2 | `GRID_UNIT` meaningless | **FINISHED** — all `KIND_SPECS` dims multiples of 4 (`room_template_catalog.gd:113-193`); `floor_shell_suite.gd` `grid_quantum` |
| FSH-12 | P2 | No `hide_walls` | **FINISHED** — `@export hide_walls` (`castle_blockout.gd:54-57`, `:300-301`) |
## Target design

The blockout stays — it is the right tool for collision, navmesh, and graybox iteration. What changes is that it stops being the *visible* geometry, and its navmesh starts telling the truth.

### 1. Honest navmesh (FSH-01, FSH-02)

Bake from real source geometry instead of two triangles:

```gdscript
func _build_navigation_mesh() -> void:
    var nav_mesh := NavigationMesh.new()
    nav_mesh.agent_height = 1.8          # matches the player capsule
    nav_mesh.agent_radius = 0.45         # matches the widest enemy
    nav_mesh.agent_max_climb = 0.5       # matches add_height_stairs step_height
    nav_mesh.cell_size = 0.2
    nav_mesh.cell_height = 0.2
    var source := NavigationMeshSourceGeometryData3D.new()
    NavigationServer3D.parse_source_geometry_data(nav_mesh, source, self)
    NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
```

`parse_source_geometry_data` walks the subtree, so the floor, the wall segments, the cover obstacles, and any authored `StaticBody3D` all contribute. `nav_mesh.geometry_parsed_geometry_type` is set to `PARSED_GEOMETRY_STATIC_COLLIDERS` and `geometry_source_geometry_mode` to `SOURCE_GEOMETRY_CHILDREN` so only this room's colliders are considered.

`agent_radius = 0.45` is the important change: the current 0.25 lets agents hug walls that they physically collide with.

The bake must therefore happen **after** cover is placed. Restructure so the builder calls `blockout.finalize_geometry()` once, at the end of the room-preparation phase, and `_rebuild()` only rebuilds meshes and colliders. Cover obstacles move out of `Geometry` into a sibling `CoverObstacles` node that `_clear_children` preserves, so a rebuild no longer destroys them (FSH-02).

### 2. Batched rebuild (FSH-03)

Setters set a dirty flag and defer:

```gdscript
func _request_rebuild() -> void:
    if not is_inside_tree() or _rebuild_queued:
        return
    _rebuild_queued = true
    if Engine.is_editor_hint():
        _rebuild()                      # editor wants immediate feedback
        _rebuild_queued = false
    else:
        call_deferred("_flush_rebuild")
```

`DungeonBuilder` then calls `blockout.finalize_geometry()` explicitly after all four door flags and the cover are set, which both collapses the four rebuilds into one and guarantees the navmesh bake sees final geometry.

### 3. Per-room ceilings, no monolith (FSH-04, FSH-10, FSH-12)

Move the ceiling into `CastleBlockout` as a `room_width x 0.4 x room_depth` slab at `wall_height`, built with the same wall material and its own occluder, gated by a new `build_ceiling: bool = true` export. Rooms then occlude properly, and empty grid cells are genuinely empty rather than covered by a slab whose underside is visible from any gap.

`FloorShellBuilder.build()` keeps only the perimeter walls (which stop the camera and stray projectiles from leaving the floor) and the per-room lighting call. `build_arena_shell()` keeps its single ceiling since an arena has no empty cells.

While in the file, merge the four wall segments of a room into a single `StaticBody3D` with four `CollisionShape3D` children and one `MeshInstance3D` per segment (meshes cannot merge without an authored mesh, but bodies can), and emit one room-sized occluder box rather than one per wall (FSH-10).

Add `hide_walls: bool = false`: when true, the blockout builds colliders, navmesh, and occluders but no wall `MeshInstance3D`s, so an authored scene can supply the visible geometry and still get correct collision and navigation (FSH-12). This is the hook [`room-templates.md`](room-templates.md) RTP-04 depends on.

### 4. Door lintels and frames (FSH-06)

`_build_wall` gains a third segment above the door: `DOOR_WIDTH x (wall_height - DOOR_HEIGHT) x WALL_THICKNESS` centerd at `DOOR_HEIGHT + (wall_height - DOOR_HEIGHT) / 2`. That makes doorways read as doorways from inside the room and gives the diorama camera a silhouette to work with. Authored door frames then sit against a real opening rather than a floor-to-ceiling slot.

### 5. Deterministic per-floor lifetime (FSH-05, FSH-09)

`FloorShellBuilder.build()` takes the `DungeonRoot` node introduced in [`dungeon-builder.md`](dungeon-builder.md) step 5 and parents `FloorShell` under it, so freeing one node frees the shell. Delete the `Shortcut*` branch of `_compute_bounds` along with the builder's shortcut code (FSH-09).

### 6. Biome resolution from the room, not the world (FSH-07)

`CastleRoomScene._resolve_biome_id()` inverts its precedence: `BiomeRegistry.biome_from_template_id(template_id)` first, `RunFlow.current_biome_id` only as a fallback when the template id yields nothing. A room's own template id is authoritative — that is what selected the scene in the first place.

### 7. Height steps (FSH-08, FSH-11)

`add_height_stairs` gets its caller in [`dungeon-builder.md`](dungeon-builder.md) DBL-05, and `agent_max_climb = 0.5` above makes the resulting steps navigable. `GRID_UNIT` becomes the documented quantum for all `KIND_SPECS` dimensions — every width and depth must be a multiple of 4.0, asserted by the suite — which is what makes rooms tile cleanly (FSH-11).

## Work plan

1. **Navmesh from real geometry** — `parse_source_geometry_data`, agent radius 0.45, `finalize_geometry()` entry point (FSH-01).
2. **Cover survives rebuild** — `CoverObstacles` sibling node, preserved by `_clear_children` (FSH-02).
3. **Deferred rebuild** — dirty flag plus `finalize_geometry()` call from the builder (FSH-03).
4. **`hide_walls` and `build_ceiling`** — new exports; per-room ceiling; single wall body; one room occluder (FSH-04, FSH-10, FSH-12).
5. **Shell reduction** — `FloorShellBuilder` drops the ceiling slab, parents under `DungeonRoot`, drops the `Shortcut*` branch (FSH-04, FSH-05, FSH-09).
6. **Door lintels** — third wall segment above each door (FSH-06).
7. **Biome precedence** — `CastleRoomScene._resolve_biome_id` inversion (FSH-07).
8. **Grid quantum** — assert all `KIND_SPECS` dimensions are multiples of `GRID_UNIT`; fix any that are not (FSH-11).
9. **Height steps** — lands with DBL-05 (FSH-08).

## Data and schema changes

None to `content/schemas/`. This topic is code and scene work only.

`KIND_SPECS` dimension audit (step 8): all current values (8, 10, 14, 16, 20, 24, 28) are multiples of 2 but `10` and `14` are not multiples of `GRID_UNIT = 4.0`. Either relax the constant to 2.0 or adjust `treasure` to 12 x 12 and `puzzle` to 16 x 16 and `hall` stays 16 x 16. Preference: adjust the kinds, because a 4-unit quantum keeps every socket on a grid line and simplifies authored tiling. That change is owned by [`room-templates.md`](room-templates.md) and requires re-authoring the affected scenes' socket positions.

## Acceptance criteria

- [x] Navmesh excludes walls and cover in XZ (FSH-01) — `floor_shell_suite.gd` `navmesh_excludes_walls`, `navmesh_excludes_cover`.
- [x] `agent_radius >= 0.45` and `agent_max_climb >= 0.5` (FSH-01) — `floor_shell_suite.gd` `navmesh_agent_params`.
- [x] Cover survives door flag change (FSH-02) — `floor_shell_suite.gd` `cover_survives_door_change`.
- [x] Exactly one navmesh bake per room build (FSH-03) — `floor_shell_suite.gd` `single_bake_per_room`.
- [x] No dungeon `CeilingSlab`; per-room ceilings (FSH-04) — `floor_shell_suite.gd` `per_room_ceiling`; `dungeon_suite.gd` `no_ceiling_over_empty_cells`.
- [x] `DungeonRoot` free removes `FloorShell` (FSH-05) — `dungeon_suite.gd` `shell_freed_on_unload`.
- [x] Door lintels above `DOOR_HEIGHT` (FSH-06) — `floor_shell_suite.gd` `door_has_lintel`.
- [x] Template biome beats `RunFlow` (FSH-07) — `floor_shell_suite.gd` `biome_precedence`.
- [x] `hide_walls` suppresses meshes, keeps colliders (FSH-12) — `floor_shell_suite.gd` `hide_walls`.
- [x] All `KIND_SPECS` dims are `GRID_UNIT` multiples (FSH-11) — `floor_shell_suite.gd` `grid_quantum`.
- [x] `add_height_stairs()` called from builder (FSH-08) — `dungeon_builder.gd:371`.
- [x] No `Shortcut` in `_compute_bounds` (FSH-09).

## Validation

`floor_shell_suite.gd` — 10 assertions (FSH-01 through FSH-12). Registered in `validation_runner.gd:51`.

`dungeon_suite.gd` — `shell_freed_on_unload`, `no_ceiling_over_empty_cells`.

Godot headless (2026-08-06): `--suite=floor_shell_suite` exited 0 via `scripts/godot-bin.ps1`.
## Related

- [`../existing_codebase/floor-shell.md`](../existing_codebase/floor-shell.md)
- [`room-templates.md`](room-templates.md) — RTP-01 footprints, RTP-04 authored geometry needs `hide_walls`
- [`dungeon-builder.md`](dungeon-builder.md) — DBL-01/DBL-02 navigation, DBL-05 height steps, `DungeonRoot`
- [`biome-registry.md`](biome-registry.md) — material lookup
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — ceiling lighting and props
- [`visual-lighting.md`](visual-lighting.md) — lighting profiles the ceiling change affects
- [`debug-arenas.md`](debug-arenas.md) — `build_arena_shell`
- [`enemies.md`](enemies.md) — agent radius must match the widest enemy
