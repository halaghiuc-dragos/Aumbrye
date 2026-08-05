# Dungeon builder

`DungeonBuilder` turns a `DungeonDefinition` dictionary into a live scene: instantiates room templates at their transforms, opens blockout doors along edges, builds the floor shell, spawns enemies, chests, traps, cover, room content, the boss, the boss door, the exit portal, and the stair lever, and owns the enemy/chest snapshot round-trip. It is the last stage of generation and the only consumer of most placement arrays.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/dungeon_builder.gd` | 940-line builder, snapshot capture/apply, floor definition cache |
| `apps/game/client/scripts/dungeon/stair_collision_builder.gd` | Collision body for stair ramps |
| `apps/game/client/scripts/dungeon/doorway_socket.gd` | `Marker3D` subclass marking a doorway attachment point |

## How it works

### Entry points

| Function | Line | Use |
|----------|------|-----|
| `build(parent, player, fixture_path)` | `:67` | loads a fixture JSON, defaults to `content/fixtures/forgotten_castle_slice.json` (`:6`) |
| `build_from_definition(parent, player, def)` | `:71` | the procgen path |
| `build_from_source(...)` | `:75` | the shared implementation |

`build_from_source` resolves the biome via `BiomeRegistry.resolve_biome_id(definition)` (`:89`), sets `_is_final_floor` from `definition.isFinalFloor` **or** `RunFlow.is_final_floor()` outside endless mode (`:90-92`), and errors out on an empty definition or an empty `rooms` array (`:86-97`).

The build order is fixed (`:98-117`):

1. `_build_rooms` — instantiate templates
2. `_sync_blockout_doors_from_edges` — open door cutouts
3. `_build_doorway_bridges` — floor slabs across doorway gaps
4. `_build_height_transitions` — **no-op**
5. `_build_floor_shell` — `FloorShellBuilder.build`
6. `_build_landmarks` — skyline boxes
7. `_place_cover` — pillars into blockouts
8. `_place_secret_mechanisms` — illusory walls and hidden levers
9. `_build_nav_links`
10. `_spawn_player`
11. `_place_enemies`, `_place_loot`, `_place_traps`, `_place_room_content`
12. `_setup_boss`, then `_setup_exit_portal` when final
13. `_setup_stair_levers`, `_setup_boss_door`

### Rooms

`_build_rooms` (`:145`) skips any `templateId` not in `BiomeRegistry.get_room_scenes(biome_id)` with a warning (`:151-153`), so a definition referencing an unknown template silently loses rooms. It applies `transform.x/y/z` and `deg_to_rad(transform.yaw)` (`:156-159`), copies `id`, `templateId`, and `type` onto the `RoomTemplate`, forces `blockout.skip_floor = false` (`:166`), and calls `StairCollisionBuilder.ensure_stair_collision` when the template id ends with `_stairs` (`:169-170`).

`content/fixtures/dungeon_definition_v1_minimal.json` references `castle_hall_a` and `castle_hall_b`, which are not in `BiomeRegistry`, so building it produces zero rooms and the `push_error` at `:96`.

### Doors, bridges, nav

`_sync_blockout_doors_from_edges` (`:173`) skips `one_way` edges and calls `_open_blockout_door_toward` in both directions. `_open_blockout_door_toward` (`:186`) uses `RoomTemplate.door_mask_toward()` — a **world-space** delta (`room_template.gd:31-35`) — and assigns the result to a **local** blockout flag (`:191-199`). For a room with a non-zero yaw the wrong wall opens.

`_build_doorway_bridges` (`:202`) resolves `socket_toward()` on both rooms, skips the edge if either socket is missing (`:217-218`), and skips when the socket-to-socket span is under 0.5 (`:226`). The bridge box is `span * 0.35` along the travel axis and `DOOR_WIDTH` across (`:228-232`), so it covers roughly a third of the gap it is meant to span. Bridges live under a `DoorwayBridges` node parented to the run scene, not to any room.

`_build_nav_links` (`:344`) computes both sockets, converts each to its own room's local space, and calls:

```gdscript
from_blockout.add_door_nav_link(from_local, from_local + Vector3(0.0, 0.1, 0.0))
to_blockout.add_door_nav_link(to_socket_local, to_socket_local + Vector3(0.0, 0.1, 0.0))
```

Both links are degenerate — start and end are the same point 0.1 apart vertically, inside the same room. No link connects room A's navmesh to room B's, so there is no cross-room navigation path. Each `CastleBlockout` bakes its own flat rectangle navmesh (`castle_blockout.gd:200-233`) and no code assigns a custom navigation map, so all regions share the world default map.

`_sample_placement_offset` (`:371`) calls `blockout.sample_random_nav_point()` for any placement with `sampleNavmesh: true`. That helper calls `NavigationServer3D.map_get_random_point` on the blockout's navigation map (`castle_blockout.gd:242-249`), which is the shared world map, so the sampled point can be anywhere on the floor. It is then converted with `to_local` and used as the enemy's or trap's position relative to its own room.

### Placement

| Pass | Line | Notes |
|------|------|-------|
| `_place_cover` | `:292` | forwards `offset` and `size` to `CastleBlockout.add_cover_obstacle` with the biome wall material; `kind` unread |
| `_place_secret_mechanisms` | `:311` | requires a non-empty `parentRoomId` and a `Props` node; builds a `0.3 x 0.6 x 0.3` box for `hidden_lever` or a `0.2 x 2.4 x 2.0` box for `illusory_wall` at a hardcoded local position. Both are `MeshInstance3D` only — no `Area3D`, no collision, no interaction, no removal path. The illusory wall carries a `secret_room_id` meta that nothing reads. |
| `_spawn_player` | `:436` | teleports to the entrance room's `SpawnPoints/PlayerSpawn`, then `CharacterFloorSnap.snap_feet_to_floor` |
| `_place_enemies` / `_spawn_enemy` | `:452`, `:458` | resolves the scene via `EnemyCatalog.get_scene` then a 4-entry preload fallback (`:887-894`); sets `position`, snaps feet, **then** `room.add_child` (`:470-475`), so the snap runs while the node is still unparented and its global transform is not yet the room's |
| `_place_loot` | `:483` | uses `_placement_offset` only, never navmesh sampling, so a chest offset outside the room's walls stays there; forwards the whole placement dictionary into `LootChest.configure` |
| `_place_traps` | `:520` | `_trap_scene_for_id` (`:503`) maps `falling_trap`, `poison_pool`/`frost_trap`, `shadow_trap`, and everything else onto the three existing trap scenes |
| `_place_room_content` | `:515` | `RoomContentSpawner.spawn_all` + `spawn_locks` |

`_placement_offset` (`:447`) accepts either `offset` or `position`, which is what makes the C# CLI output (serialized as `position`) loadable.

### Boss, portal, doors, levers

`_setup_boss` (`:533`) returns early when `placements.boss` is null (`:534-536`). On the final floor of the castle biome it overrides the enemy id to `final_boss_forgotten_castle` (`:541-542`) and falls back to `FINAL_BOSS_SCENE` when the catalog lookup fails (`:544-545`). It positions the boss at `Props/BossSpawn` if present, else the room origin (`:552-556`).

`_setup_exit_portal` (`:567`) only runs when `_is_final_floor`. `_create_exit_portal` (`:577`) builds an `Area3D` with `EXIT_PORTAL_SCRIPT`, `monitoring = false`, `visible = false`, a `3 x 3 x 1` box, and a diorama skin, positioned at `Props/ExitPortalMarker` or the hardcoded `(0, 1.5, 12)` (`:585-589`). It is added under the room's `Props` node — if the room has no `Props` child the portal is created, skinned, and then dropped on the floor unparented (`:596-599`).

`open_exit_portal()` (`:132`) sets `monitoring` and `visible` directly instead of calling `ExitPortal.activate()`. It is called from `_on_boss_defeated` (`:602-604`) and `apply_snapshot` (`:852-854`).

`_setup_stair_levers` (`:610`) creates a lever in **every** room whose `template_id` ends with `_stairs` but stores only the last one in `_stair_lever` (`:651`), so `get_stair_lever()`, `_unlock_stair_lever()`, and everything downstream only ever see one. `_place_stair_lever_on_wall` (`:654`) prefers `SpawnPoints/LeverSpawn` and otherwise guesses a west-wall position from the blockout dimensions (`:660-668`). `configure(can_ascend, can_descend)` is called with two arguments here (`:650`) and three in `_unlock_stair_lever` (`:676`).

`_setup_boss_door` (`:696`) looks up the room with the hardcoded id `"boss"` and builds a barrier, interact area, and label from scratch on every floor, whether or not a boss was placed. It positions the door at `_boss_approach_socket()` (`:771`) plus a quarter unit along the socket facing, else a guess from room depth (`:757-759`), and registers it with the run scene via `register_boss_door` (`:763-764`).

`get_boss_door_outside_spawn()` (`:796`) falls back to `get_room("arena")` — an id procgen never produces (semantic ids are `entrance`, `room_<n>`, `boss`, `treasure`, `secret_<n>`).

### Snapshots and cache

`capture_enemy_states` (`:811`), `capture_loot_states` (`:830`), and `apply_snapshot` (`:839`) key off `_enemy_placement_id` (`roomId:index`) and `_loot_placement_id` (`chestId`, else `roomId:index`). `snapshot_dirty` fires on enemy death and chest open. `apply_snapshot` re-opens the exit portal or unlocks the stair lever when `bossDefeated` is set.

Static `_floor_definition_cache` (`:49`) stores deep copies per floor index via `store_floor_cache` / `get_floor_cache` / `clear_floor_cache` (`:52-64`), paired with `RunFlow.floor_definitions`.

`unload_from_parent` (`:897`) frees the rooms, `_entities`, the `Rooms` root, and the two shortcut nodes. It does **not** free `DoorwayBridges`, `Landmarks`, or the `FloorShell` node that `FloorShellBuilder` adds (`floor_shell_builder.gd:17-19`), so those accumulate on every floor transition.

`_apply_floor_scaling` (`:921`) scales health and damage by `EndlessDifficulty` in endless mode and `CastleTierDifficulty` in castle mode, and does nothing in waves mode.

### Dead and disabled code

- `_build_height_transitions()` (`:256-258`) is an explicit `pass` with the comment "Height transitions disabled until direction-aware stair placement exists", and it is called at `:101`. `CastleBlockout.add_height_stairs()` (`castle_blockout.gd:276`) is the machinery it would use and has no call sites anywhere.
- `_build_shortcut_corridors(parent)` (`:388`) is fully implemented — it builds two hardcoded blockout corridors at `(0, 0, 31)` and `(9, 0, 43)` — but has no call site. It also early-returns unless the definition contains a `one_way` edge, which the GDScript generator never emits, so it would be a no-op for procgen floors even if wired up. `_create_shortcut_blockout` (`:409`) exists only to serve it, and `FloorShellBuilder._compute_bounds` still scans for `Shortcut*` children (`floor_shell_builder.gd:121-127`).

### `StairCollisionBuilder`

`ensure_stair_collision(room)` (`stair_collision_builder.gd:7`) needs a `Props` child, returns if `StairCollision` already exists, and copies the size and transform of `Props/StairRamp` when it is a `MeshInstance3D` with a `BoxMesh`. Otherwise it falls back to a `4 x 0.4 x 12` box at `(0, 1.2, 0)` (`:26-27`).

In practice the fallback never runs. The only `_stairs` scenes with a `Props` node are `castle_stairs`, `crystal_stairs`, and `swamp_stairs`, and all three also have `Props/StairRamp`. The other seven themes have no `Props` node, so `ensure_stair_collision` returns at `:11-12` and those stair rooms get **no** ramp collision at all. The same missing `Props` node makes `_place_secret_mechanisms` (`dungeon_builder.gd:317-319`) and the exit portal's parent lookup (`:596-598`) no-ops in those themes, and `Props/BossSpawn` is absent so the boss spawns at the room origin (`:552-556`). See [`room-templates.md`](room-templates.md) for the full marker coverage table.

### `DoorwaySocket`

A `Marker3D` with `direction` (the `CastleRoomConstants.Direction` enum), `socket_id`, and `is_secret` (`doorway_socket.gd:7-9`). `get_world_facing()` (`:18-28`) correctly returns a world-space vector by combining the local direction with the node's global basis. `is_secret` is authored on three scenes and read nowhere.

## Contracts

- Definition keys read: `rooms[]` (`id`, `templateId`, `type`, `transform.{x,y,z,yaw}`), `edges[]` (`from`, `to`, `kind`), `placements.{enemies,loot,traps,secrets,cover,boss,exit,entrance}`, `landmarks[]`, `roomContent[]`, `locks[]`, `isFinalFloor`, plus whatever `BiomeRegistry.resolve_biome_id` reads.
- Node-name contract on room scenes: `CastleBlockout`, `DoorwaySockets/*`, `Props`, `Props/BossSpawn`, `Props/ExitPortalMarker`, `Props/StairRamp`, `SpawnPoints/PlayerSpawn`, `SpawnPoints/LeverSpawn`.
- Nodes created under the run scene: `Entities`, `Rooms`, `DoorwayBridges`, `Landmarks`, `FloorShell`.
- Signals out: `build_complete`, `boss_defeated`, `snapshot_dirty`.
- Autoload dependencies at build time: `RunFlow` (final-floor and mode checks), `BiomeRegistry`, `EnemyCatalog`, `ContentLoader`.
- Run-scene contract: optional `register_boss_door(door)` on the parent.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Room instantiation and transforms | IMPLEMENTED | `dungeon_builder.gd:145-170` |
| Snapshot capture/apply | IMPLEMENTED | `:811-857` |
| Floor definition cache | IMPLEMENTED | `:49-64` |
| Cover, landmarks, traps, chests, enemies | IMPLEMENTED | `:292`, `:261`, `:520`, `:483`, `:452` |
| Cross-room navigation | BROKEN | `_build_nav_links` creates degenerate same-room links (`:363-364`) |
| Navmesh point sampling | BROKEN | samples the shared world map, so points come from arbitrary rooms (`:377`, `castle_blockout.gd:242-249`) |
| Door opening on rotated rooms | BROKEN | world-space mask assigned to a local flag (`:190-199`, `room_template.gd:31-35`) |
| Enemy floor snapping | BROKEN | `snap_feet_to_floor` runs before `add_child` (`:470-475`) |
| Secret mechanisms | STUB | mesh only, no `Area3D`, no collision, no reveal logic (`:311-341`) |
| `_build_height_transitions()` | STUB | explicit `pass`, called at `:101` (`:256-258`) |
| `_build_shortcut_corridors()` | STUB | implemented, no call site (`:388`) |
| `CastleBlockout.add_height_stairs()` | STUB | no call sites |
| Multiple stair rooms | PARTIAL | every `_stairs` room gets a lever, only the last is tracked (`:610-651`) |
| Boss door | PARTIAL | hardcoded room id `"boss"`, built even with no boss (`:696-697`) |
| Exit portal | PARTIAL | bypasses `ExitPortal.activate()` (`:132-142`); orphaned when the room has no `Props` (`:596-599`) |
| Node cleanup on unload | PARTIAL | `DoorwayBridges`, `Landmarks`, `FloorShell` leak (`:897-918`) |
| Doorway bridges | PLACEHOLDER | `span * 0.35` boxes that under-cover the gap (`:228-232`) |
| Waves-mode difficulty scaling | ABSENT | `_apply_floor_scaling` handles endless and castle only (`:921-939`) |
| `get_boss_door_outside_spawn` arena fallback | ABSENT | `get_room("arena")` never resolves for procgen ids (`:800`) |
| `DoorwaySocket.is_secret` | STUB | authored on 3 scenes, read nowhere |
| Stair ramp collision | BROKEN | the 7 clone themes have no `Props` node, so `ensure_stair_collision` returns early and the ramp has no collider (`stair_collision_builder.gd:10-12`) |
| Unknown template handling | PARTIAL | warning and skip, which turns a bad definition into a partial floor (`:151-153`) |

`docs/ARCHITECTURE.md:119-120` and `docs/existing_codebase/00-PLACEHOLDER-INVENTORY.md:49-50` both state the height-transition and shortcut-corridor status correctly; this doc confirms them and adds the unreferenced `add_height_stairs` helper.

## Related

- Improvement plan: [`../actual_improvements/dungeon-builder.md`](../actual_improvements/dungeon-builder.md)
- [`procgen-placements.md`](procgen-placements.md) — the arrays this consumes
- [`room-content.md`](room-content.md) — `RoomContentSpawner`
- [`room-templates.md`](room-templates.md) — node-name contract, sockets
- [`floor-shell.md`](floor-shell.md) — `FloorShellBuilder`, `CastleBlockout`
- [`boss-door-exit-portal.md`](boss-door-exit-portal.md) — the scripts attached here
- [`stair-lever.md`](stair-lever.md) — lever creation and configuration
- [`biome-registry.md`](biome-registry.md) — room scene and material lookup
- [`run-flow.md`](run-flow.md) — floor cache pairing, snapshots
- [`castle-run.md`](castle-run.md) — the run scene that owns the builder
