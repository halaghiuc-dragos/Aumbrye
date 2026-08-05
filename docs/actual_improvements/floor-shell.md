# Floor shell — improvement plan

## Current state

`CastleBlockout` is a competent runtime box-builder: correct walls, door cutouts, per-wall occluders, and a baked navmesh from six numbers. It is also the reason 84 of 90 room scenes have no authored geometry, and its navmesh is baked from two floor triangles that ignore walls and cover, so pathfinding believes every room is an empty rectangle. `FloorShellBuilder` deliberately avoids a monolithic floor and then adds a monolithic ceiling that covers every empty grid cell, and its `FloorShell` node is never freed on a floor transition. See [`../existing_codebase/floor-shell.md`](../existing_codebase/floor-shell.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| FSH-01 | P0 | The navmesh is baked from two flat floor triangles, so walls, cover pillars, and props are invisible to pathfinding and enemies walk into them | `castle_blockout.gd:223-233`, cover added afterward at `:252-273` |
| FSH-02 | P0 | Cover obstacles are children of `Geometry`, so any later `_rebuild()` deletes them silently | `castle_blockout.gd:79-86,256` |
| FSH-03 | P1 | Each of the four door setters triggers a full geometry teardown plus navmesh re-bake, so opening a room's doors rebuilds it up to four times per build | `castle_blockout.gd:22-40,57-59`, `dungeon_builder.gd:182-183` |
| FSH-04 | P1 | The ceiling is one slab spanning the whole floor bounding box, covering every empty grid cell, with collision and no occluder | `floor_shell_builder.gd:29-35` |
| FSH-05 | P1 | `FloorShell` is never freed, so ceilings and perimeter walls accumulate across floor transitions | `dungeon_builder.gd:897-918` vs `floor_shell_builder.gd:17-19` |
| FSH-06 | P1 | Doorways are full-height 3.0 x 6.0 gaps; `DOOR_HEIGHT` is never used to cut them, so no room has a door lintel | `castle_blockout.gd:119-141`, `castle_room_constants.gd:7` |
| FSH-07 | P1 | `CastleRoomScene` resolves its biome from the global `RunFlow.current_biome_id` before its own `template_id`, so a room can be dressed and materialled as the wrong biome | `castle_room_scene.gd:26-29` |
| FSH-08 | P2 | `add_height_stairs()` is implemented with no call sites | `castle_blockout.gd:276` |
| FSH-09 | P2 | `FloorShellBuilder` scans for `Shortcut*` children to serve `_build_shortcut_corridors`, which has no call site | `floor_shell_builder.gd:121-127`, `dungeon_builder.gd:388` |
| FSH-10 | P2 | Each wall segment is its own `StaticBody3D` with its own occluder and `BoxMesh`, so a four-door room is 9 bodies and 8 occluders | `castle_blockout.gd:144-197` |
| FSH-11 | P2 | `GRID_UNIT` is only a minimum clamp and encodes no real grid relationship to `RoomGraphConfig` spacing | `castle_room_constants.gd:5`, `castle_blockout.gd:9,14` |
| FSH-12 | P2 | The blockout has no exported way to suppress its generated walls, which blocks authored geometry from reusing it for collision and navmesh | no `hide_walls`-style export in `castle_blockout.gd:7-45` |

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

- [ ] A room's baked navmesh excludes every wall segment and every cover obstacle: no navmesh polygon overlaps a wall or cover collider in XZ (FSH-01).
- [ ] `agent_radius >= 0.45` and `agent_max_climb >= 0.5` on every baked room navmesh (FSH-01).
- [ ] Setting a door flag after `add_cover_obstacle` leaves the cover body alive (FSH-02).
- [ ] Building a four-door room performs exactly one navmesh bake (FSH-03).
- [ ] No `CeilingSlab` exists under `FloorShell` for a dungeon floor; every room has its own ceiling (FSH-04).
- [ ] Freeing `DungeonRoot` leaves no `FloorShell` node in the run scene (FSH-05).
- [ ] Every blockout doorway has a wall segment above `DOOR_HEIGHT` (FSH-06).
- [ ] Instantiating a `crystal_courtyard` while `RunFlow.current_biome_id == "poison_swamp"` yields crystal materials (FSH-07).
- [ ] With `hide_walls = true`, the blockout has zero wall `MeshInstance3D`s and the same number of `CollisionShape3D`s as with it false (FSH-12).
- [ ] Every `KIND_SPECS` width and depth is a multiple of `GRID_UNIT` (FSH-11).
- [ ] `FloorShellBuilder._compute_bounds` contains no reference to `Shortcut` (FSH-09).

## Validation

New suite `apps/game/client/scripts/validation/suites/floor_shell_suite.gd`:

- `test_navmesh_excludes_walls` — build a 20 x 20 four-door blockout; for 200 sampled navmesh points assert none is within `WALL_THICKNESS / 2 + 0.4` of a wall plane.
- `test_navmesh_excludes_cover` — add three cover obstacles, finalize, and assert no navmesh point falls inside a cover AABB.
- `test_navmesh_agent_params` — assert `agent_radius`, `agent_height`, `agent_max_climb`, `cell_size` on every room's navmesh.
- `test_single_bake_per_room` — instrument the bake with a counter; set all four door flags and place cover; assert the counter is 1.
- `test_cover_survives_door_change` — assert the cover body is still in the tree after a door flag flip.
- `test_door_has_lintel` — assert a wall with a door has three segments and that one spans `DOOR_HEIGHT` to `wall_height`.
- `test_per_room_ceiling` — assert every room has a ceiling collider at `wall_height` and that `FloorShell` has no `CeilingSlab` on a dungeon floor.
- `test_hide_walls` — assert the collider count matches and the mesh count is zero.
- `test_grid_quantum` — assert every `KIND_SPECS` dimension is a multiple of `GRID_UNIT`.
- `test_biome_precedence` — set `RunFlow.current_biome_id` to a mismatching biome, instantiate a room, assert the material matches the template's biome.

Extend `apps/game/client/scripts/validation/suites/dungeon_suite.gd`:

- `test_shell_freed_on_unload` — build, unload, assert no `FloorShell`.
- `test_no_ceiling_over_empty_cells` — for 20 seeds, assert every ceiling collider's XZ footprint is contained in some room's footprint.

Manual checklist: with a debug camera above the floor, confirm empty grid cells show open space rather than a ceiling underside, and that doorways read as framed openings from inside a room.

## Related

- [`../existing_codebase/floor-shell.md`](../existing_codebase/floor-shell.md)
- [`room-templates.md`](room-templates.md) — RTP-01 footprints, RTP-04 authored geometry needs `hide_walls`
- [`dungeon-builder.md`](dungeon-builder.md) — DBL-01/DBL-02 navigation, DBL-05 height steps, `DungeonRoot`
- [`biome-registry.md`](biome-registry.md) — material lookup
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — ceiling lighting and props
- [`visual-lighting.md`](visual-lighting.md) — lighting profiles the ceiling change affects
- [`debug-arenas.md`](debug-arenas.md) — `build_arena_shell`
- [`enemies.md`](enemies.md) — agent radius must match the widest enemy
