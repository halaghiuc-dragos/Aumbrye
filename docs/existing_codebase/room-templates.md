# Room templates

`RoomTemplateCatalog` is the authoritative table of room dimensions and door masks used by the generator to compute world positions. `RoomTemplate` is the scene-side base class the generator's `templateId` resolves to. The kit under `apps/game/client/scenes/rooms/` is 90 scenes (10 themes x 9 kinds). Only 6 of the 90 contain any authored mesh; the other 84 are pure `CastleBlockout` boxes. Seven of the ten themes carry dimensions and door masks that contradict `RoomTemplateCatalog`, which makes their rooms physically disconnected.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/procgen/room_template_catalog.gd` | `KIND_SPECS`, door-mask math, template substitution |
| `apps/game/client/scripts/dungeon/room_template.gd` | Scene base class: sockets, spawn point, nav region, blockout accessor |
| `apps/game/client/scripts/dungeon/doorway_socket.gd` | `Marker3D` with `direction`, `socket_id`, `is_secret` |
| `apps/game/client/scenes/rooms/<theme>/<theme>_<kind>.tscn` | 90 room scenes |
| `apps/game/client/scripts/dungeon/castle/castle_room_scene.gd` | Scene script for all 90 (materials + socket rotations + dressing) |
| `packages/procedural/Biome/RoomTemplateCatalog.cs` | C# mirror used by `procgen-cli` |

## How it works

### KIND_SPECS

`RoomTemplateCatalog.KIND_SPECS` (`room_template_catalog.gd:6-21`) is keyed by the part of the template id after the first underscore (`kind_from_template_id`, `:40`):

| Kind | Width | Depth | Doors |
|------|-------|-------|-------|
| `entrance` | 16 | 12 | S |
| `stairs` | 8 | 16 | N, S |
| `corridor` | 8 | 12 | N, S |
| `courtyard` | 20 | 20 | N, E, S, W |
| `hall` | 16 | 16 | E, S, W |
| `treasure` | 10 | 10 | N |
| `secret` | 8 | 8 | E |
| `arena` | 24 | 24 | S, W |
| `boss` | 28 | 28 | N |
| `puzzle` | 14 | 14 | N, S |

`corridor` is in `KIND_SPECS` but no theme ships a `<theme>_corridor` scene and no biome lists one in `roomTemplateIds`, so it is never instantiated. The assigner uses `corridor` as a room *type* for the stairs slot instead (`room_graph_assigner.gd:113`).

`get_spec()` (`:47`) pushes an error and falls back to `courtyard` for an unknown kind. `half_extent_x/z` (`:127`, `:133`) rotate the half-extents by the room yaw, which is what `RoomGraphGeometry` sums to place rooms.

### Template substitution

`pick_template_for_doors(preferred, required_doors, biome_templates)` (`:155`) returns the first id whose spec mask covers `required_doors`, searching in this order:

1. `preferred_template_id`
2. every entry of the biome's `roomTemplateIds`, in file order
3. `<prefix>_courtyard`, `<prefix>_hall`, `<prefix>_arena` (`FALLBACK_KINDS`, `:23`)
4. `castle_courtyard`, `castle_hall`, `castle_arena`
5. `<prefix>_courtyard` unconditionally

Because every biome JSON lists templates in the order `entrance, stairs, courtyard, hall, treasure, secret, arena, boss, puzzle` (`content/biomes/forgotten_castle.json:9-19`), and `courtyard` is the only kind with all four doors, a slot needing an unusual mask almost always resolves to `<prefix>_courtyard`. Consequences:

- The `entrance` slot has door mask S only in the spec, so any start cell with more than one door becomes a courtyard. `entrance`, `treasure`, and `secret` kits are used only when the slot's mask happens to match.
- The `stairs` slot (spec N|S) becomes a courtyard whenever the start's neighbor has an E or W door. Its `templateId` then does not end with `_stairs`, and `DungeonBuilder._setup_stair_levers()` (`dungeon_builder.gd:615`) matches on exactly that suffix, so no stair lever is created and the floor cannot be left. `RunFloorConfig.find_stairs_room_id()` (`run_floor_config.gd:47-53`) uses the more forgiving `ends_with("_stairs") or type == "corridor"`, so the two lookups disagree.
- `boss` is the only role that bypasses substitution (`room_graph_assigner.gd:92`), so `<prefix>_boss` is always instantiated even when its single N door does not match the slot mask.

### RoomTemplate

`RoomTemplate` (`room_template.gd`) exports `template_id`, `room_id`, `room_type`, `player_spawn_path` (default `SpawnPoints/PlayerSpawn`), and `nav_region_path` (default `CastleBlockout/NavigationRegion3D`).

- `get_sockets()` (`:13`) requires a child named `DoorwaySockets` and returns its `DoorwaySocket` children.
- `find_socket(direction)` (`:24`) matches the socket's exported `direction` enum — the room's **local** direction.
- `door_mask_toward(other)` (`:31`) compares **world** positions.
- `socket_toward(other)` (`:38`) combines the two, so on a yaw-rotated room it asks for a socket by world direction and matches by local direction. For a boss room rotated 180 degrees it asks for `Socket_S`, which `castle_boss.tscn` does not have (only `Socket_N`, `castle_boss.tscn:24-26`), and returns `null`.
- `get_blockout()` (`:66`) requires a child named exactly `CastleBlockout`.
- `contains_world_point()` (`:70`) returns false when there is no blockout.

`CastleRoomScene._ready()` (`castle_room_scene.gd:7`) fills any null blockout material from `BiomeRegistry`, rebuilds the blockout, forces socket rotations to the canonical yaw per direction (`:32-42`), and calls `DioramaRoomDressing.apply_to_room(self, biome_id, room_id.hash())`. See [`diorama-room-dressing.md`](diorama-room-dressing.md).

### What is actually in the 90 scenes

Exactly 6 scenes contain a `MeshInstance3D`; all other geometry in the kit is generated at runtime by `CastleBlockout`.

| Scene | Authored mesh |
|-------|---------------|
| `castle_courtyard.tscn`, `crystal_courtyard.tscn`, `swamp_courtyard.tscn` | `Props/SecretCuePanel` — a 0.4 x 2.5 x 2.5 accent box on the west wall, plus a `Props/SecretCueLight` `OmniLight3D` (`castle_courtyard.tscn:58-67`) |
| `castle_stairs.tscn`, `crystal_stairs.tscn`, `swamp_stairs.tscn` | `Props/StairRamp` — a 4 x 0.4 x 12 accent box pitched 25 degrees (`castle_stairs.tscn:49`). Only `castle_stairs.tscn` also has `SpawnPoints/LeverSpawn` (`:44`). |

The other 84 scenes contain only: the root `Node3D` with `CastleRoomScene`, a `CastleBlockout` child with width/depth/door flags and two materials, a `DoorwaySockets` node with 1-4 `Marker3D` sockets, and `SpawnPoints/PlayerSpawn`. `castle_boss.tscn` — the arena where every floor climaxes — is a bare 28 x 28 procedural box with one socket, a `BossSpawn` marker, and an `ExitPortalMarker` (`castle_boss.tscn:9-39`).

A `Props` node exists in only 18 of the 90 scenes: the `courtyard`, `arena`, `treasure`, `boss`, `stairs`, and `secret` kinds in each of `castle`, `crystal`, and `swamp`. The `entrance`, `hall`, and `puzzle` kinds in those three themes and **every** scene in the other seven themes have no `Props` node at all. That matters because `DungeonBuilder` silently skips work when it is missing: secret mechanisms (`dungeon_builder.gd:317-319`), the exit portal parent (`:596-598`), and stair collision (`stair_collision_builder.gd:10-12`).

Marker coverage across the kit:

| Marker | Scenes that have it |
|--------|---------------------|
| `SpawnPoints/PlayerSpawn` | all 90 |
| `Props` | 18 (six kinds x castle/crystal/swamp) |
| `Props/StairRamp` | 3 (`castle_stairs`, `crystal_stairs`, `swamp_stairs`) |
| `SpawnPoints/LeverSpawn` | 1 (`castle_stairs`) |
| `Props/BossSpawn`, `Props/ExitPortalMarker` | 3 (`castle_boss`, `crystal_boss`, `swamp_boss`) |

### Theme conformance to KIND_SPECS

`castle`, `crystal`, and `swamp` match `KIND_SPECS` on all 9 kinds. The other 7 themes (`frozen`, `cathedral`, `vault`, `prism`, `mire`, `hollow`, `umbral`) ship every kind as 16 x 12 with `door_south = false, door_north = false`, and only `<theme>_entrance` (16 x 12, `door_south = true`) is correct. Examples:

| Scene | Scene blockout | `KIND_SPECS` |
|-------|----------------|--------------|
| `umbral_courtyard.tscn:16-19` | 16 x 12, no doors, sockets N + S only | 20 x 20, N/E/S/W |
| `frozen_puzzle.tscn:16-19` | 16 x 12, no doors | 14 x 14, N/S |
| `hollow_entrance.tscn:16-19` | 16 x 12, `door_south = true`, `room_type = "hub"` | 16 x 12, S — matches |
| `umbral_boss.tscn` | 16 x 12, `door_north = true` | 28 x 28, N |
| `vault_stairs.tscn` | 16 x 12, `room_type = "combat"` | 8 x 16, N/S |

Because `RoomGraphGeometry` spaces rooms using `KIND_SPECS` while the scene builds the smaller box, adjacent rooms in those 7 themes never touch:

- Two `umbral_courtyard` rooms are placed 20 units apart (10 + 10) but their walls sit at +-8 in X and +-6 in Z, leaving a 4-unit gap east-west and an 8-unit gap north-south.
- `DungeonBuilder._build_doorway_bridges()` (`dungeon_builder.gd:228-232`) sizes the bridge at `span * 0.35`, so an 8-unit gap gets a 2.8-unit slab centerd in it.
- East-west neighbors get no bridge and no nav link at all, because those scenes have no `Socket_E`/`Socket_W` and `socket_toward()` returns `null` (`dungeon_builder.gd:217`, `:359`).

In `castle`, `crystal`, and `swamp` the sockets sit exactly on the wall face, so `span` is 0 and the `span < 0.5` guard (`dungeon_builder.gd:226`) skips bridge creation — the rooms abut correctly with no bridge needed.

`DungeonBuilder._sync_blockout_doors_from_edges()` (`:173`) does open the required local door on every non-`one_way` edge, so the wall opening exists even in the mismatched themes; the missing floor is what blocks the player.

### C# mirror

`packages/procedural/Biome/RoomTemplateCatalog.cs` enumerates all 90 template ids explicitly with per-id width/depth/door masks matching `KIND_SPECS`. The CLI output confirms it: in `seed99999.json:1` `entrance` sits at z 0 and `stairs` at z 14 (6 + 8), and consecutive `castle_courtyard` rooms are 20 apart.

## Contracts

Node-name contracts every room scene must satisfy, because `RoomTemplate`, `DungeonBuilder`, and the room-content layer hard-code them:

| Path | Required by |
|------|-------------|
| `CastleBlockout` | `room_template.gd:67`, `dungeon_builder.gd:164`, `floor_shell_builder.gd:138` |
| `CastleBlockout/NavigationRegion3D` | `room_template.gd:10` (created by `castle_blockout.gd:202`) |
| `DoorwaySockets/*` (`DoorwaySocket`) | `room_template.gd:15` |
| `SpawnPoints/PlayerSpawn` | `room_template.gd:9`, `dungeon_builder.gd:688` |
| `SpawnPoints/LeverSpawn` | `dungeon_builder.gd:655` — present only in `castle_stairs.tscn` |
| `Props` | `dungeon_builder.gd:317,596,642`, `room_content_base.gd:12`, `stair_collision_builder.gd:10` — present in 18 of 90 scenes |
| `Props/BossSpawn` | `dungeon_builder.gd:552` — present in 3 of 10 `_boss` scenes |
| `Props/ExitPortalMarker` | `dungeon_builder.gd:585` — present in 3 of 10 `_boss` scenes |
| `Props/StairRamp` | `stair_collision_builder.gd:15` — present in 3 of 10 `_stairs` scenes |

Template ids must be registered in `BiomeRegistry.get_room_scenes()` or `DungeonBuilder._build_rooms()` skips the room with `push_warning("DungeonBuilder: unknown template %s")` (`dungeon_builder.gd:152`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| `KIND_SPECS` dimension/door table | IMPLEMENTED | `room_template_catalog.gd:6-21` |
| Authored room layouts | PLACEHOLDER | 6 of 90 scenes contain a mesh; the other 84 are `CastleBlockout` boxes |
| Boss arena | PLACEHOLDER | `castle_boss.tscn` is a bare 28 x 28 box with no props |
| `castle` / `crystal` / `swamp` kit geometry | IMPLEMENTED | all 9 kinds match `KIND_SPECS` |
| `frozen` / `cathedral` / `vault` / `prism` / `mire` / `hollow` / `umbral` kits | BROKEN | 8 of 9 kinds are 16 x 12 with no doors, so rooms are spaced apart and never connect (`umbral_courtyard.tscn:16-19`, `frozen_puzzle.tscn:16-19`) |
| Doorway bridge sizing | BROKEN | `span * 0.35` cannot span the gap it exists to cover (`dungeon_builder.gd:229-231`) |
| `socket_toward()` on rotated rooms | BROKEN | world-space direction matched against local-space socket enum (`room_template.gd:31-52`); returns `null` for a rotated `boss` room |
| Template substitution silently changing room role | BROKEN | a substituted stairs slot loses its lever (`room_template_catalog.gd:155`, `dungeon_builder.gd:615`) |
| `corridor` kind | ABSENT | in `KIND_SPECS` (`:9`) but no `<theme>_corridor.tscn` and no biome `roomTemplateIds` entry |
| `_yaw_to_align` | STUB | duplicate of `yaw_to_align_doors`, no call sites (`room_template_catalog.gd:139`) |
| `DoorwaySocket.is_secret` | PARTIAL | set on `castle_courtyard.tscn:50` and its crystal/swamp twins; no reader — searched all of `apps/game/client/scripts` |
| `RoomTemplate.contains_world_point` | PARTIAL | works only when a `CastleBlockout` exists; no caller in `scripts/dungeon` |
| C# catalog parity | IMPLEMENTED but unasserted | `packages/procedural/Biome/RoomTemplateCatalog.cs`; no test compares it to `KIND_SPECS` (see [`room-graph-procgen.md`](room-graph-procgen.md)) |

## Related

- Improvement plan: [`../actual_improvements/room-templates.md`](../actual_improvements/room-templates.md)
- [`room-graph-procgen.md`](room-graph-procgen.md) — who calls `pick_template_for_doors` and `get_spec`
- [`dungeon-builder.md`](dungeon-builder.md) — instantiation, doorway bridges, nav links
- [`floor-shell.md`](floor-shell.md) — `CastleBlockout` and `CastleRoomScene`
- [`biome-registry.md`](biome-registry.md) — template id to scene mapping
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — prop dressing applied on top
- [`stair-lever.md`](stair-lever.md) — the `_stairs` suffix contract
