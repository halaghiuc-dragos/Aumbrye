# Dungeon builder — improvement plan

## Current state

The builder assembles a floor correctly at the structural level and its snapshot round-trip works. Three defects break gameplay: doorway nav links are degenerate so nothing can path between rooms, `sample_random_nav_point` samples the shared world navigation map so enemies and traps get positions taken from other rooms, and `_open_blockout_door_toward` mixes world and local space so rotated rooms open the wrong wall. Height transitions are a called `pass`, shortcut corridors are implemented with no call site, and secret mechanisms are meshes with no interaction. See [`../existing_codebase/dungeon-builder.md`](../existing_codebase/dungeon-builder.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DBL-01 | P0 | Doorway nav links are degenerate: both ends are the same point 0.1 apart in the same room, so no navmesh path crosses a doorway | `dungeon_builder.gd:363-364` |
| DBL-02 | P0 | `sample_random_nav_point()` samples the shared world navigation map, so `sampleNavmesh` placements can be positioned from another room entirely | `dungeon_builder.gd:377`, `castle_blockout.gd:242-249`; no `set_navigation_map` call in the repo |
| DBL-03 | P0 | `_open_blockout_door_toward` assigns a world-space door mask to a local blockout flag, so any yaw-rotated room opens the wrong wall | `dungeon_builder.gd:190-199`, `room_template.gd:31-35` |
| DBL-04 | P0 | Secret mechanisms are bare `MeshInstance3D`s with no `Area3D`, no collision, and no reveal logic, so secret rooms cannot be entered | `dungeon_builder.gd:311-341` |
| DBL-05 | P1 | `_build_height_transitions()` is an explicit `pass` while being called; `CastleBlockout.add_height_stairs()` has no call sites | `dungeon_builder.gd:101,256-258`, `castle_blockout.gd:276` |
| DBL-06 | P1 | `_build_shortcut_corridors()` is implemented but has no call site and would no-op anyway because GDScript never emits a `one_way` edge | `dungeon_builder.gd:388-394` |
| DBL-07 | P1 | Enemies are floor-snapped before being added to the room, so the snap runs against a stale global transform | `dungeon_builder.gd:470-475` |
| DBL-08 | P1 | Only the last `_stairs` room's lever is tracked, so a floor with two stair rooms has an unlockable lever the boss-death handler cannot reach | `dungeon_builder.gd:610-651,671-677` |
| DBL-09 | P1 | `unload_from_parent` leaks `DoorwayBridges`, `Landmarks`, and `FloorShell` on every floor transition | `dungeon_builder.gd:897-918` vs `:206,267`, `floor_shell_builder.gd:17-19` |
| DBL-10 | P1 | The boss door is built on every floor from the hardcoded room id `"boss"`, even when no boss was placed | `dungeon_builder.gd:696-697,533-536` |
| DBL-11 | P1 | Chests are placed without navmesh sampling or bounds checking, so an out-of-room offset stays out of the room | `dungeon_builder.gd:492` |
| DBL-12 | P1 | An unknown `templateId` produces a warning and a missing room rather than a failed build | `dungeon_builder.gd:151-153`; `content/fixtures/dungeon_definition_v1_minimal.json` references `castle_hall_a`/`castle_hall_b` |
| DBL-13 | P2 | The exit portal is created and skinned before checking for a `Props` parent, so it is orphaned when `Props` is missing | `dungeon_builder.gd:577-599` |
| DBL-14 | P2 | `open_exit_portal()` sets `monitoring`/`visible` directly instead of calling `ExitPortal.activate()` | `dungeon_builder.gd:132-142` |
| DBL-15 | P2 | Doorway bridges are `span * 0.35` long, covering roughly a third of the gap | `dungeon_builder.gd:228-232` |
| DBL-16 | P2 | Waves mode gets no enemy difficulty scaling | `dungeon_builder.gd:921-939` |
| DBL-17 | P2 | `get_boss_door_outside_spawn` falls back to `get_room("arena")`, an id procgen never produces | `dungeon_builder.gd:800` |
| DBL-18 | P2 | `configure` is called on the stair lever with 2 arguments in one place and 3 in another | `dungeon_builder.gd:650` vs `:676` |
| DBL-19 | P1 | The 7 clone themes have no `Props` node, so `ensure_stair_collision` returns early and their stair rooms get no ramp collider, `_place_secret_mechanisms` is a no-op, the exit portal is orphaned, and the boss spawns at the room origin | `stair_collision_builder.gd:10-12`, `dungeon_builder.gd:317-319,552,596-598`, `umbral_boss.tscn:9-42` |
| DBL-20 | P2 | `DoorwaySocket.is_secret` is authored and never read | `doorway_socket.gd:9` |

## Target design

### 1. Real cross-room navigation (DBL-01, DBL-02)

Two independent problems: links and maps.

**Per-floor navigation map.** Create one `RID` per built floor via `NavigationServer3D.map_create()`, set its cell size and height to match the baked meshes (0.25/0.25), activate it, and assign every room's `NavigationRegion3D` and every `NavigationLink3D` to it. `CastleBlockout` gains `set_navigation_map(map: RID)` which forwards to the region and to any existing links. Enemy `NavigationAgent3D`s are pointed at the same map. This removes the accidental global-map coupling and makes `map_get_random_point` meaningful.

**Room-scoped sampling.** `sample_random_nav_point()` stops using `map_get_random_point` and instead rejection-samples inside the room's own rectangle: draw a local point in `[-(w/2 - 1), (w/2 - 1)] x [-(d/2 - 1), (d/2 - 1)]`, project it with `NavigationServer3D.map_get_closest_point`, and accept it if it is still inside the room's AABB; up to 8 attempts, then fall back to the room center. The RNG is passed in from the caller so sampling is deterministic (see [`procgen-placements.md`](procgen-placements.md) section 3) — today it is a live server call and therefore not reproducible.

**Real doorway links.** Replace the two degenerate links with one bidirectional link per edge, owned by a new `NavLinks` child of the run scene rather than by either blockout:

```gdscript
var link := NavigationLink3D.new()
link.start_position = from_socket.global_position + from_socket.get_world_facing() * -0.5
link.end_position = to_socket.global_position + to_socket.get_world_facing() * -0.5
link.bidirectional = true
link.travel_cost = 1.0
link.navigation_map = floor_nav_map
```

Both endpoints are pushed 0.5 units back **into** their respective rooms so they land on baked navmesh. Once room footprints abut correctly (see [`room-templates.md`](room-templates.md) RTP-01) the two sockets are coincident and the link is short.

`CastleBlockout.add_door_nav_link` keeps working for the debug arenas but is no longer used by the builder.

### 2. Space-correct door opening (DBL-03)

Derive the flag from the resolved socket rather than from a world delta:

```gdscript
func _open_blockout_door_toward(from_room: RoomTemplate, to_room: RoomTemplate) -> void:
    var blockout := from_room.get_blockout()
    if blockout == null:
        return
    var socket := from_room.socket_toward(to_room)   # world-space, per RTP-03
    if socket == null:
        push_error("No socket from %s toward %s" % [from_room.room_id, to_room.room_id])
        return
    match socket.direction:
        CastleRoomConstants.Direction.NORTH: blockout.door_north = true
        CastleRoomConstants.Direction.EAST:  blockout.door_east = true
        CastleRoomConstants.Direction.SOUTH: blockout.door_south = true
        CastleRoomConstants.Direction.WEST:  blockout.door_west = true
```

This depends on the `socket_toward()` rewrite in [`room-templates.md`](room-templates.md) RTP-03 and on all four sockets existing per room (RTP-06). Land those first.

### 3. Secret mechanisms that work (DBL-04, DBL-20)

A secret needs three things the current code lacks: a position derived from the actual wall between parent and secret room, a trigger, and a removal path.

`ProcgenPlacements` starts emitting the wall direction on each secret entry (`wallDirection: "north" | "east" | "south" | "west"`, derived from the grid delta between the secret slot and its parent). The builder then:

- Resolves the parent room's `DoorwaySocket` for that direction, preferring one with `is_secret = true` (DBL-20 gives the flag a reader).
- For `illusory_wall`: instantiates a new `scenes/dungeon/illusory_wall.tscn` at the socket — an authored wall panel with a `StaticBody3D` on layer 1 and an `Area3D` on mask 2. Entering the area and pressing `interact` (or attacking it, matching the Zelda idiom) plays a dissolve via [`material-dissolve.md`](material-dissolve.md), disables the collider, and opens the blockout door on both sides.
- For `hidden_lever`: instantiates `scenes/dungeon/hidden_lever.tscn` with an interact area; pulling it opens the same door and sets a `WorldState` flag keyed by the secret room id so it stays open after a snapshot reload.

Both paths route through a shared `_reveal_secret(secret_room_id)` so `apply_snapshot` can replay a previously revealed secret.

### 4. Height transitions, for real or not at all (DBL-05)

`RoomGraphGeometry` already writes `transform.y` per room, and `CastleBlockout.add_height_stairs(step_count, direction, step_height)` already builds a ramp of steps toward one of four directions. Implement `_build_height_transitions()` as:

For every edge whose two rooms differ in `transform.y`, take the lower room, compute the grid direction toward the higher room from the resolved socket's `direction`, and call `add_height_stairs(ceili(abs(dy) / step_height), dir, 0.5)` on the lower room's blockout, with `step_height = 0.5` so a one-level (2.0 unit) difference is 4 steps. Then extend the nav link for that edge to span the height change; `NavigationLink3D` handles vertical offsets natively, so no extra work is needed beyond using the real socket positions from section 1.

Gate the whole feature behind `RoomGraphConfig.max_height_level`, which stays at 0 until this lands (see [`room-graph-procgen.md`](room-graph-procgen.md)). Until then, `_build_height_transitions` asserts that all rooms share the same `transform.y` rather than silently doing nothing.

### 5. Delete the shortcut-corridor path (DBL-06)

`_build_shortcut_corridors`, `_create_shortcut_blockout`, the `Shortcut*` branch of `FloorShellBuilder._compute_bounds`, and the `Shortcut*` cleanup in `unload_from_parent` all exist to serve a hand-authored M2 fixture with a `one_way` edge. Shortcuts belong in the graph, not in the builder: `RoomGraphGeometry` should emit a `kind: "shortcut"` edge between two already-adjacent cells (see [`room-graph-procgen.md`](room-graph-procgen.md) RGP-11), which the normal door and nav-link paths then handle. Delete the four builder pieces.

### 6. Fail loudly and clean up properly (DBL-09, DBL-10, DBL-12, DBL-13)

- `_build_rooms` collects unknown template ids and, if any, `push_error`s and aborts the build instead of shipping a partial floor. `content/fixtures/dungeon_definition_v1_minimal.json` is regenerated with real template ids so it stays usable as a fixture.
- `_setup_boss_door` uses `definition.placements.exit` (the boss room's id) rather than the literal `"boss"`, and returns early when there is no boss placement.
- `_create_exit_portal` resolves the `Props` parent **first** and errors out if it is missing, before building anything.
- `unload_from_parent` frees `DoorwayBridges`, `Landmarks`, `FloorShell`, and `NavLinks`. Better: parent all builder-created nodes under a single `DungeonRoot` node and free that one node, so a new node type can never be forgotten again.

### 7. Correctness cleanup (DBL-07, DBL-08, DBL-11, DBL-14 through DBL-19)

- Move `snap_feet_to_floor` after `room.add_child(enemy)` (DBL-07).
- `_stair_lever` becomes `_stair_levers: Array[Node3D]`; `_unlock_stair_lever` iterates; `get_stair_lever()` keeps returning the first for compatibility and gains `get_stair_levers()`. Combined with the single-stairs-room assertion from [`room-templates.md`](room-templates.md) RTP-02, the array will normally hold one element (DBL-08).
- Chests use `_sample_placement_offset` with a bounds assertion, so an out-of-room offset is caught by the suite rather than shipped (DBL-11).
- `open_exit_portal()` calls `ExitPortal.activate()`; the `visible`/`monitoring` fiddling moves into that method (DBL-14; see [`boss-door-exit-portal.md`](boss-door-exit-portal.md)).
- Doorway bridges become an error path, per [`room-templates.md`](room-templates.md) RTP-05 (DBL-15).
- `_apply_floor_scaling` handles `waves` mode using the wave index from [`waves-run.md`](waves-run.md) (DBL-16).
- `get_boss_door_outside_spawn` drops the `"arena"` lookup and uses `definition.placements.exit`'s adjacent room from the edge list (DBL-17).
- One `configure(can_ascend, can_descend, can_retreat)` signature at both call sites (DBL-18).
- Every room scene ships a `Props` node and every `_stairs` scene ships `Props/StairRamp` (scene work owned by [`room-templates.md`](room-templates.md) RTP-07). `ensure_stair_collision` then `push_error`s instead of returning silently when `Props` or `StairRamp` is missing, and `_place_secret_mechanisms` and `_create_exit_portal` do the same (DBL-19).

## Work plan

1. **Per-floor nav map** — `NavigationServer3D.map_create`, `CastleBlockout.set_navigation_map`, agent wiring (DBL-02, part 1).
2. **Room-scoped deterministic sampling** — rewrite `sample_random_nav_point` with a passed-in RNG (DBL-02, part 2).
3. **Real doorway nav links** — `NavLinks` node, one bidirectional link per edge (DBL-01).
4. **Space-correct doors** — after RTP-03 and RTP-06 land (DBL-03).
5. **Single `DungeonRoot` + full cleanup** — reparent every builder-created node, simplify `unload_from_parent` (DBL-09).
6. **Fail loudly** — unknown templates abort; boss door keyed on `placements.exit`; portal parent checked first (DBL-10, DBL-12, DBL-13).
7. **Secret mechanisms** — `wallDirection` in placements, two authored scenes, `_reveal_secret`, snapshot replay (DBL-04, DBL-20).
8. **Delete shortcut corridors** — builder, shell bounds, unload (DBL-06).
9. **Height transitions** — implement using `add_height_stairs`, keep gated at `max_height_level = 0` until the graph supports it (DBL-05).
10. **Correctness cleanup** — the DBL-07/08/11/14/15/16/17/18/19 list.

## Data and schema changes

- `content/schemas/dungeon-definition.v1.json`: `placements.secrets[]` gains a required `wallDirection` enum (`north`, `east`, `south`, `west`) and keeps `parentRoomId` required. Declare `placements.cover` (shared with [`procgen-placements.md`](procgen-placements.md) PLC-07).
- New scenes: `apps/game/client/scenes/dungeon/illusory_wall.tscn`, `hidden_lever.tscn`.
- `content/fixtures/dungeon_definition_v1_minimal.json` and `forgotten_castle_slice.json` regenerate from generator output: real template ids, `offset` rather than `position`, `parentRoomId` and `wallDirection` on secrets, no `one_way` edge.
- Save format: `WorldState` gains `secret_revealed_<roomId>` flags. Additive, so no migration is needed, but note it in [`save-migrator.md`](save-migrator.md).

## Acceptance criteria

- [ ] For every edge on a built floor, `NavigationServer3D.map_get_path` between the two rooms' centers returns a path with more than one segment and no straight-line fallback (DBL-01).
- [ ] Every `NavigationRegion3D` and `NavigationLink3D` on a built floor reports the same non-default navigation map RID (DBL-02).
- [ ] Every `sampleNavmesh` placement's resolved world position is inside its own room's blockout AABB (DBL-02).
- [ ] Two builds of the same definition produce identical enemy world positions (DBL-02, determinism).
- [ ] For every room with `transform.yaw != 0` and an edge, the opened blockout door flag corresponds to the socket facing the neighbor (DBL-03).
- [ ] Every secret room is reachable: the parent room's illusory wall or hidden lever has an `Area3D` with mask 2, and triggering it opens the door to the secret room (DBL-04).
- [ ] `_build_height_transitions` either builds steps for every edge with a `transform.y` delta, or asserts there are none (DBL-05).
- [ ] `_build_shortcut_corridors` and `_create_shortcut_blockout` no longer exist (DBL-06).
- [ ] After `unload_from_parent`, the run scene has no `Rooms`, `DoorwayBridges`, `Landmarks`, `FloorShell`, `NavLinks`, or `Entities` child (DBL-09).
- [ ] Building a definition with an unknown `templateId` returns without creating any node and pushes an error (DBL-12).
- [ ] Every chest's world position is inside its room's blockout AABB inset by 1.0 (DBL-11).
- [ ] `content/fixtures/dungeon_definition_v1_minimal.json` builds to a non-empty floor (DBL-12).
- [ ] On a built floor in every biome, the stair room has a `Props/StairCollision` body, the boss is positioned at `Props/BossSpawn`, and the exit portal has a parent (DBL-19).

## Validation

Extend `apps/game/client/scripts/validation/suites/dungeon_suite.gd`:

- `test_cross_room_navigation` — build floor 1 of each of the 10 biomes; for every edge, assert `map_get_path` from room A's spawn to room B's center has more than one point and its final point is within 1.0 of the target.
- `test_boss_reachable_by_path` — assert a navmesh path exists from the entrance spawn to the boss room center on 50 seeds.
- `test_single_nav_map` — assert all regions and links share one RID that is not `NavigationServer3D.map_get_default`.
- `test_placements_inside_own_room` — every enemy, chest, trap, and cover body is inside its room's AABB inset by 1.0.
- `test_build_determinism` — build the same definition twice; assert identical world positions for every enemy, chest, and trap.
- `test_rotated_room_doors` — hand-build a two-room definition with `yaw = 90` on both; assert the opened door flags match the sockets facing each other.
- `test_secret_reachable` — build a floor with a secret; assert the parent room has an interactable secret node, and that calling `_reveal_secret` opens the blockout door on both sides.
- `test_unload_leaves_nothing` — build, unload, assert the run scene has none of the six builder node names.
- `test_unknown_template_aborts` — assert a definition with a bogus `templateId` creates no `Rooms` node.
- `test_minimal_fixture_builds` — assert `content/fixtures/dungeon_definition_v1_minimal.json` yields at least 2 rooms.
- `test_stair_levers_all_tracked` — hand-build a definition with two `_stairs` rooms; assert `get_stair_levers().size() == 2` and that `_unlock_stair_lever` unlocks both.
- `test_no_height_delta_without_support` — assert every room's `transform.y` is equal while `max_height_level == 0`.

## Related

- [`../existing_codebase/dungeon-builder.md`](../existing_codebase/dungeon-builder.md)
- [`room-templates.md`](room-templates.md) — RTP-01 footprints, RTP-03 sockets, RTP-06 socket completeness
- [`floor-shell.md`](floor-shell.md) — `CastleBlockout` navmesh baking, `FloorShell` ownership
- [`procgen-placements.md`](procgen-placements.md) — PLC-02 anchors, `wallDirection` on secrets
- [`room-content.md`](room-content.md) — spawner contract
- [`room-graph-procgen.md`](room-graph-procgen.md) — RGP-11 shortcut edges, height levels
- [`boss-door-exit-portal.md`](boss-door-exit-portal.md) — DBL-10, DBL-13, DBL-14
- [`stair-lever.md`](stair-lever.md) — DBL-08, DBL-18
- [`material-dissolve.md`](material-dissolve.md) — illusory wall reveal
- [`run-flow.md`](run-flow.md), [`castle-run.md`](castle-run.md), [`waves-run.md`](waves-run.md) — callers
