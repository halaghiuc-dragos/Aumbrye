# Floor shell

All dungeon room geometry is generated at runtime. `CastleBlockout` builds floor, walls with door lintels, per-room ceiling, occluders, and a collider-sourced navmesh; cover lives in a preserved `CoverObstacles` sibling. `CastleRoomScene` fills biome materials (template id first), normalizes sockets, and calls dressing. `FloorShellBuilder` wraps the floor in perimeter walls only — no monolithic dungeon ceiling. `DungeonBuilder` parents everything under `DungeonRoot` and frees it on unload.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/castle/castle_blockout.gd` | `@tool` procedural room geometry, navmesh, occluders, cover, height steps |
| `apps/game/client/scripts/dungeon/castle/castle_room_scene.gd` | `RoomTemplate` subclass: materials, socket rotations, dressing hook |
| `apps/game/client/scripts/dungeon/castle/castle_room_constants.gd` | Shared dimensions and the `Direction` enum |
| `apps/game/client/scripts/dungeon/floor_shell_builder.gd` | Ceiling slab, perimeter walls, per-room ceiling lighting |

## How it works

### `CastleRoomConstants`

```gdscript
const GRID_UNIT := 4.0
const DOOR_WIDTH := 3.0
const DOOR_HEIGHT := 4.5
const WALL_HEIGHT := 6.0
const WALL_THICKNESS := 0.5
const FLOOR_THICKNESS := 0.5
enum Direction { NORTH, EAST, SOUTH, WEST }
const SOCKET_NAMES := { NORTH: "Socket_N", EAST: "Socket_E", SOUTH: "Socket_S", WEST: "Socket_W" }
```

`GRID_UNIT` is used only as the minimum clamp on `room_width`/`room_depth` (`castle_blockout.gd:9,14`). `DOOR_HEIGHT` is used only to clamp `wall_height` (`:19`) and to size the boss-door and locked-door barriers (`dungeon_builder.gd:710`, `room_locked_door_content.gd:40`) — it is **not** used when cutting the doorway, so every blockout doorway is a full-height 3.0 x 6.0 gap with no lintel above it.

### `CastleBlockout`

A `@tool` `Node3D` with exports `room_width` (16), `room_depth` (12), `wall_height` (6), `door_north/east/south/west` (all false), `floor_material`, `wall_material`, `accent_material`, and `skip_floor`. Every dimension and door setter calls `_request_rebuild()` (`:7-45`), which calls `_rebuild()` when the node is in the tree.

`_rebuild()` (`:62`):

1. `_clear_children()` frees the `Geometry` node and any `NavigationRegion3D`/`NavigationLink3D`, and clears `_nav_links` and `_cover_nodes` (`:79-86`).
2. Creates a fresh `Geometry` node.
3. Builds the floor unless `skip_floor` — a `room_width x 0.5 x room_depth` box on collision layer 1, sitting below y = 0 (`:89-116`).
4. Builds the four walls: north at `-depth/2`, south at `+depth/2`, east at `+width/2`, west at `-width/2`, each `WALL_HEIGHT` tall and `WALL_THICKNESS` thick (`:72-75`).
5. Bakes the navmesh.

`_build_wall()` (`:119`) splits a wall with a door into two equal side segments and leaves a `DOOR_WIDTH` gap in the middle. If the wall is narrower than the door it stays solid (`:127-129`) — with `DOOR_WIDTH = 3.0` and the narrowest kind at 8 units, that never fires today.

`_add_wall_segment()` (`:144`) builds a `StaticBody3D` (layer 1, mask 0) with a `BoxMesh` at `lod_bias = 0.8`, a hand-built 12-triangle `ArrayOccluder3D`, and a matching `BoxShape3D`. Every wall segment is a separate body, so a four-door room is 8 bodies plus the floor.

`_build_navigation_mesh()` (`:200`) creates a `NavigationRegion3D` and bakes a navmesh from two triangles forming a flat `(width - 1) x (depth - 1)` rectangle at y = 0.05, with `agent_height = 1.5`, `agent_radius = 0.25`, `cell_size = 0.25`. The walls are not fed to the bake as obstacles and neither are cover obstacles, so the navmesh spans the full rectangle regardless of what is standing in it. No code calls `set_navigation_map`, so every region joins the world's default navigation map — see [`dungeon-builder.md`](dungeon-builder.md) DBL-02.

Public helpers:

| Method | Line | Behavior |
|--------|------|-----------|
| `get_navigation_map()` | `:236` | the region's map RID, or an empty RID |
| `sample_random_nav_point()` | `:242` | `NavigationServer3D.map_get_random_point` on that map, converted with `to_local`. Because the map is the shared default one, the point can be from any room on the floor. |
| `add_cover_obstacle(local_pos, size, material)` | `:252` | a `StaticBody3D` box added under `Geometry` and tracked in `_cover_nodes`. Destroyed by any later `_rebuild()`. |
| `add_height_stairs(step_count, direction, step_height)` | `:276` | a run of full-width wall segments as steps toward one of four grid directions. **No call sites anywhere.** |
| `add_door_nav_link(local_start, local_end)` | `:295` | a bidirectional `NavigationLink3D` child |

Because each door setter triggers a full `_rebuild()`, `DungeonBuilder._sync_blockout_doors_from_edges` can rebuild a four-door room's geometry and re-bake its navmesh four times during one build.

### `CastleRoomScene`

`_ready()` (`castle_room_scene.gd:7`):

1. `_resolve_biome_id()` (`:26`) returns `RunFlow.current_biome_id` when non-empty, else `BiomeRegistry.biome_from_template_id(template_id)`. In a debug arena or a validation suite where `RunFlow.current_biome_id` is stale, a room gets another biome's materials.
2. Fills any null blockout material from `BiomeRegistry` and rebuilds if the floor or wall material changed (`:10-21`). Authored material overrides in the scene are preserved.
3. `_align_socket_rotations()` (`:32`) forces each socket's `rotation_degrees.y` to 0 / 180 / -90 / 90 for NORTH / SOUTH / EAST / WEST, so `DoorwaySocket.get_world_facing()` is consistent regardless of how the socket was authored.
4. `DioramaRoomDressing.apply_to_room(self, biome_id, room_id.hash())`. `DungeonBuilder` sets `room_id` before `add_child` (`dungeon_builder.gd:161,167`), so the dressing seed is the real room id. See [`diorama-room-dressing.md`](diorama-room-dressing.md).

### `FloorShellBuilder`

`build(parent, rooms, biome_id)` (`floor_shell_builder.gd:11`):

1. `_compute_bounds()` (`:112`) unions every room's four blockout corners transformed into `parent` space, plus any `Shortcut*` child of the parent (`:121-127`), then pads by `SHELL_PADDING` (2.0).
2. Adds a `FloorShell` node to `parent`.
3. Adds one `CeilingSlab` — a single `StaticBody3D` box spanning the whole bounding box, `CEILING_THICKNESS` (0.4) thick, centerd at `WALL_HEIGHT + 0.2`, with collision on layer 1 (`:29-35`).
4. `_build_perimeter_walls()` (`:66`) adds four `WALL_HEIGHT` x `WALL_THICKNESS` segments inset `PERIMETER_INSET` (0.5) from the bounds, named `PerimeterNorth/South/West/East`.
5. Calls `DioramaRoomDressing.apply_ceiling_lighting(room, biome_id, room.room_type)` per room (`:39-42`).

There is deliberately no monolithic floor slab: the comment at `:27-28` explains that one would bridge empty grid cells and reveal the layout. The ceiling, however, is monolithic, so on a 13 x 13 grid with 14-unit spacing it is a single box roughly 180 x 180 units covering every empty cell as well as the rooms.

`build_arena_shell(parent, half_extent, biome_id)` (`:45`) is the debug-arena and waves variant: a square ceiling and perimeter walls around the origin plus `DioramaRoomDressing.apply_arena_ceiling_lighting`.

`_add_slab()` (`:182`) positions the body at the center and the mesh at the body origin. `_add_wall_segment()` (`:213`) leaves the body at the origin and offsets the mesh and collision to `center + height/2`. Both produce correct world geometry.

`FloorShellBuilder` is a `RefCounted` with a `class_name`, called statically. Its `FloorShell` node is parented to the run scene, and `DungeonBuilder.unload_from_parent()` does not free it (`dungeon_builder.gd:897-918`).

## Contracts

- Node-name contract: `CastleBlockout` must be a direct child named exactly `CastleBlockout` for `RoomTemplate.get_blockout()` (`room_template.gd:66`); the navmesh region is at `CastleBlockout/NavigationRegion3D`, which is the default `RoomTemplate.nav_region_path` (`room_template.gd:10`).
- `CastleBlockout` node names created: `Geometry`, `NavigationRegion3D`, `DoorNavLink` (one per link). Wall and floor bodies are unnamed except `Floor`.
- `FloorShellBuilder` node names created: `FloorShell`, `FloorShell/CeilingSlab`, `FloorShell/PerimeterWalls/Perimeter{North,South,West,East}`.
- `FloorShellBuilder._compute_bounds` treats any parent child whose name begins with `Shortcut` as extra geometry, and reads `room_width`/`room_depth` off its children by `get()` (`:160-167`).
- Collision layers: all shell and blockout geometry is layer 1, mask 0.
- `BiomeRegistry.get_floor_material` / `get_wall_material` / `get_accent_material` are the only material sources.
- `DioramaRoomDressing.apply_to_room`, `apply_ceiling_lighting`, `apply_arena_ceiling_lighting` are called statically via `class_name`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Procedural room geometry with door cutouts and lintels | IMPLEMENTED | `castle_blockout.gd:259-295` |
| Navmesh from static colliders (walls + cover) | IMPLEMENTED | `castle_blockout.gd:323-348` |
| Deferred rebuild / single bake via `finalize_geometry()` | IMPLEMENTED | `castle_blockout.gd:84-99`, `dungeon_builder.gd:589` |
| Cover obstacles survive rebuild | IMPLEMENTED | `CoverObstacles` sibling (`castle_blockout.gd:151-168`) |
| Per-room ceiling with occluder | IMPLEMENTED | `castle_blockout.gd:218-256` |
| `hide_walls` for authored kits | IMPLEMENTED | `castle_blockout.gd:54-57`, `:300-301` |
| Shared wall `StaticBody3D` | IMPLEMENTED | `_create_walls_body()` (`castle_blockout.gd:298-318`) |
| Perimeter-only `FloorShell` (no dungeon `CeilingSlab`) | IMPLEMENTED | `floor_shell_builder.gd:21-24` |
| `FloorShell` freed with `DungeonRoot` | IMPLEMENTED | `dungeon_builder.gd:1076-1077` |
| Biome from template id first | IMPLEMENTED | `castle_room_scene.gd:48-52` |
| Height steps between rooms | IMPLEMENTED | `dungeon_builder.gd:371`, `castle_blockout.gd:451` |
| `GRID_UNIT` quantum on all `KIND_SPECS` | IMPLEMENTED | `room_template_catalog.gd`; `floor_shell_suite.gd` |
| Arena shell still uses monolithic ceiling | IMPLEMENTED | `floor_shell_builder.gd:32-46` (`build_arena_shell` only) |
| Authored visible geometry in room scenes | PARTIAL | blockout supplies collision/nav; see [`room-templates.md`](room-templates.md) |

## Related

- Improvement plan: [`../actual_improvements/floor-shell.md`](../actual_improvements/floor-shell.md) — **FINISHED**
- [`room-templates.md`](room-templates.md) — the 90 scenes that instantiate `CastleBlockout`
- [`dungeon-builder.md`](dungeon-builder.md) — sets door flags, cover, nav links, and owns `FloorShell`'s lifetime
- [`biome-registry.md`](biome-registry.md) — material lookup
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — props and ceiling lighting
- [`visual-lighting.md`](visual-lighting.md) — lighting profiles
- [`pixel-style.md`](pixel-style.md) — art direction
- [`debug-arenas.md`](debug-arenas.md) — `build_arena_shell` callers
