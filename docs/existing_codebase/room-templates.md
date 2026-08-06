# Room templates

`RoomTemplateCatalog.KIND_SPECS` is the authoritative table of room dimensions and door masks. `CastleBlockout` derives `room_width`, `room_depth`, and door flags from `kind` or the parent scene's `template_id` at runtime. The kit is 100 scenes (10 themes Ã— 10 kinds including `corridor`). `CastleRoomScene.sync_kit_contract()` enforces four sockets, marker nodes, and boss `Authored` geometry on every instantiate.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/procgen/room_template_catalog.gd` | `KIND_SPECS`, `ALL_DOORS`, `pick_template_for_doors(..., required_kind)`, `socket_wall_position()` |
| `apps/game/client/scripts/dungeon/room_template.gd` | Scene base: `socket_toward()`, `socket_for_direction()` |
| `apps/game/client/scripts/dungeon/doorway_socket.gd` | `Marker3D` with `direction`, `is_secret`, `get_world_facing()` |
| `apps/game/client/scripts/dungeon/castle/castle_blockout.gd` | `kind`, `hide_walls`, `_apply_kind_spec()`, `sync_dimensions_from_kind()` |
| `apps/game/client/scripts/dungeon/castle/castle_room_scene.gd` | `sync_kit_contract()`, socket/marker enforcement |
| `apps/game/client/scenes/rooms/<theme>/<theme>_<kind>.tscn` | 100 room scenes (90 legacy + 10 corridor) |
| `apps/game/client/scripts/dungeon/biome_registry.gd` | Data-driven scene loading via `ROOM_KINDS` |
| `content/biomes/*.json` | `roomTemplateIds`, materials, prop kits |
| `packages/procedural/Biome/RoomTemplateCatalog.cs` | C# mirror; parity fixture `content/fixtures/room_kit_specs.json` |

## How it works

### KIND_SPECS

`RoomTemplateCatalog.KIND_SPECS` (`room_template_catalog.gd:13-38`) is keyed by kind (`kind_from_template_id`, `:68-72`):

| Kind | Width | Depth | Doors |
|------|-------|-------|-------|
| `entrance` | 16 | 12 | N, E, S, W |
| `stairs` | 8 | 16 | N, E, S, W |
| `corridor` | 8 | 12 | N, S |
| `courtyard` | 20 | 20 | N, E, S, W |
| `hall` | 16 | 16 | N, E, S, W |
| `treasure` | 12 | 12 | N |
| `secret` | 8 | 8 | E |
| `arena` | 24 | 24 | S, W |
| `boss` | 28 | 28 | N |
| `puzzle` | 16 | 16 | N, E, S, W |

`get_spec()` (`:75-87`) returns width, depth, doors, and half-extents. `half_extent_x/z` (`:155-164`) rotate half-extents by room yaw for `RoomGraphGeometry`.

### Runtime kind derivation

`CastleBlockout._resolve_kind()` (`castle_blockout.gd:537-544`) reads exported `kind` or the parent `RoomTemplate.template_id`. `_apply_kind_spec()` (`:541-565`) overwrites `room_width`, `room_depth`, and the four `door_*` flags before `_rebuild()`. Clone-theme scenes that still export stale 16Ã—12 numbers are corrected automatically.

`CastleRoomScene.sync_kit_contract()` (`castle_room_scene.gd:36-45`) calls `sync_dimensions_from_kind()`, positions four `DoorwaySocket` children on wall faces, and adds the marker contract per kind.

### Template substitution

`pick_template_for_doors(preferred, required_doors, biome_templates, rng, required_kind)` (`room_template_catalog.gd:194-237`) filters candidates by `required_kind` when set; returns `""` if no id of that kind supports the mask. `RoomGraphAssigner` passes `required_kind` for `entrance`, `stairs`, and `secret` slots (`room_graph_assigner.gd:87-88,116-118,153-155`). The STAIRS slot still sets `type: "corridor"` (`:119`); `RunFloorConfig.is_stairs_room()` matches `type == "corridor"` or `_stairs` suffix (`run_floor_config.gd:47-51`).

### Socket resolution

`RoomTemplate.socket_toward(other)` (`room_template.gd:38-51`) normalizes the world-space delta to `other` and picks the socket whose `get_world_facing()` (room-basis direction, `doorway_socket.gd:18-29`) has the highest dot product above 0.5.

`DungeonBuilder._open_blockout_door_toward()` (`dungeon_builder.gd:257-275`) opens the blockout door flag matching the resolved socket's `direction` enum.

### Corridor kit

Ten `<theme>_corridor.tscn` scenes (8Ã—12, `kind = corridor`) load via `BiomeRegistry.ROOM_KINDS` (`biome_registry.gd:17-28`) and appear in each biome's `roomTemplateIds` after `<theme>_stairs`.

### Markers

`CastleRoomScene._ensure_marker_contract()` (`castle_room_scene.gd:79-117`) guarantees:

| Path | Kinds |
|------|-------|
| `Props` | all |
| `Props/PropAnchor_0..3` | all |
| `SpawnPoints/LeverSpawn` + `Props/StairRamp` | `stairs` |
| `Props/BossSpawn` + `Props/ExitPortalMarker` | `boss` |
| `Authored/Dais` (`MeshInstance3D`) | `boss` (runtime) |

### Secret mechanisms

`DungeonBuilder._resolve_secret_socket()` (`dungeon_builder.gd:518-522`) prefers `socket_for_direction(direction, prefer_secret=true)` so `is_secret` on west courtyard sockets positions illusory walls (`castle_courtyard.tscn:50`).

## Contracts

| Path | Required by |
|------|-------------|
| `CastleBlockout` | `room_template.gd:75`, `dungeon_builder.gd` |
| `CastleBlockout/NavigationRegion3D` | `room_template.gd:10` |
| `DoorwaySockets/*` (`DoorwaySocket`) | `room_template.gd:13` â€” always 4 (N/E/S/W) after `sync_kit_contract()` |
| `SpawnPoints/PlayerSpawn` | `room_template.gd:9` |
| `SpawnPoints/LeverSpawn` | `dungeon_builder.gd:655` â€” `stairs` kinds |
| `Props` | `dungeon_builder.gd:317,596`, `stair_collision_builder.gd:10` |
| `Props/BossSpawn`, `Props/ExitPortalMarker` | `dungeon_builder.gd:552,585` â€” `boss` kinds |
| `Props/StairRamp` | `stair_collision_builder.gd:15` â€” `stairs` kinds |
| `Authored/*` | boss milestone geometry (`castle_room_scene.gd:119-133`) |

Template ids must resolve via `BiomeRegistry.get_room_scenes()` or `DungeonBuilder` logs `unknown template` (`dungeon_builder.gd:152`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| `KIND_SPECS` dimension/door table | IMPLEMENTED | `room_template_catalog.gd:13-38` |
| Runtime kind â†’ blockout dimensions | IMPLEMENTED | `castle_blockout.gd:541-565` |
| Four sockets per room | IMPLEMENTED | `castle_room_scene.gd:58-76` |
| `socket_toward()` on rotated rooms | IMPLEMENTED | `room_template.gd:38-51`, `doorway_socket.gd:18-29` |
| `required_kind` substitution guard | IMPLEMENTED | `room_template_catalog.gd:222-229`, `room_graph_assigner.gd:87-155` |
| Stair lever by `room_type == "corridor"` | IMPLEMENTED | `run_floor_config.gd:47-51`, `dungeon_builder.gd:791-805` |
| Corridor kit (10 themes) | IMPLEMENTED | `apps/game/client/scenes/rooms/*/*_corridor.tscn`, `biome_registry.gd:20` |
| Doorway bridge guard | IMPLEMENTED | `dungeon_builder.gd:305-311` errors on `span >= 0.5` |
| Marker contract | IMPLEMENTED | `castle_room_scene.gd:79-117` |
| Boss `Authored` geometry | IMPLEMENTED | runtime `Authored/Dais` (`castle_room_scene.gd:119-133`) |
| `DoorwaySocket.is_secret` | IMPLEMENTED | `dungeon_builder.gd:518-522` |
| C# catalog parity | IMPLEMENTED | `cross_stack_parity_suite.gd:86-122`, `room_kit_specs.json` |
| Authored meshes (non-boss kinds) | PLACEHOLDER | boss dais only; other kinds remain blockout + dressing |

## Related

- Improvement plan: [`../actual_improvements/room-templates.md`](../actual_improvements/room-templates.md) - **FINISHED**
- [`room-graph-procgen.md`](room-graph-procgen.md)
- [`dungeon-builder.md`](dungeon-builder.md)
- [`floor-shell.md`](floor-shell.md)
- [`biome-registry.md`](biome-registry.md)
- [`diorama-room-dressing.md`](diorama-room-dressing.md)
