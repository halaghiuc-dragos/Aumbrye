# Dungeon builder — improvement plan

## Status: FINISHED

## Current state

The builder assembles floors with per-floor navigation maps, real cross-room `NavLinks`, socket-correct door opening, interactable secret mechanisms, `DungeonRoot` cleanup, and deterministic room-scoped placement sampling. Height transitions and shortcut edges are implemented; unknown templates abort the build. See [`../existing_codebase/dungeon-builder.md`](../existing_codebase/dungeon-builder.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| DBL-01 | P0 | Doorway nav links degenerate | FINISHED |
| DBL-02 | P0 | `sample_random_nav_point()` samples shared world map | FINISHED |
| DBL-03 | P0 | `_open_blockout_door_toward` world/local door mask mismatch | FINISHED |
| DBL-04 | P0 | Secret mechanisms are bare meshes with no interaction | FINISHED |
| DBL-05 | P1 | `_build_height_transitions()` no-op | FINISHED |
| DBL-06 | P1 | Shortcut corridor dead path | FINISHED |
| DBL-07 | P1 | Enemy snap before `add_child` | FINISHED |
| DBL-08 | P1 | Only last stair lever tracked | FINISHED |
| DBL-09 | P1 | `unload_from_parent` leaks builder nodes | FINISHED |
| DBL-10 | P1 | Boss door hardcoded to `"boss"` | FINISHED |
| DBL-11 | P1 | Chests without navmesh sampling / bounds | FINISHED |
| DBL-12 | P1 | Unknown `templateId` warns and skips | FINISHED |
| DBL-13 | P2 | Exit portal orphaned without `Props` | FINISHED |
| DBL-14 | P2 | `open_exit_portal()` bypasses `ExitPortal.activate()` | FINISHED |
| DBL-15 | P2 | Doorway bridges under-cover gap | FINISHED |
| DBL-16 | P2 | Waves mode no difficulty scaling | FINISHED |
| DBL-17 | P2 | `get_boss_door_outside_spawn` arena fallback | FINISHED |
| DBL-18 | P2 | Stair lever `configure` arity mismatch | FINISHED |
| DBL-19 | P1 | Clone themes missing `Props` | FINISHED |
| DBL-20 | P2 | `DoorwaySocket.is_secret` unread | FINISHED |

## Target design

Implemented per the sections below. Cross-room navigation uses a per-floor `NavigationServer3D` map, `NavLinks` child on `DungeonRoot`, room-scoped deterministic sampling, socket-based door opening, authored `illusory_wall` / `hidden_lever` scenes, `DungeonRoot` unload, and `Props` markers on clone-theme stair/boss scenes.

## Work plan

1. **Per-floor nav map** — FINISHED (DBL-02).
2. **Room-scoped deterministic sampling** — FINISHED (DBL-02).
3. **Real doorway nav links** — FINISHED (DBL-01).
4. **Space-correct doors** — FINISHED (DBL-03).
5. **Single `DungeonRoot` + full cleanup** — FINISHED (DBL-09).
6. **Fail loudly** — FINISHED (DBL-10, DBL-12, DBL-13).
7. **Secret mechanisms** — FINISHED (DBL-04, DBL-20).
8. **Delete shortcut corridors** — FINISHED (DBL-06).
9. **Height transitions** — FINISHED (DBL-05).
10. **Correctness cleanup** — FINISHED (DBL-07/08/11/14–19).

## Data and schema changes

- `placements.secrets[]` includes `wallDirection` from procgen.
- New scenes: `scenes/dungeon/illusory_wall.tscn`, `hidden_lever.tscn`.
- `content/fixtures/dungeon_definition_v1_minimal.json` uses real template ids.
- `WorldState` flags `WorldFlags.secret_opened(roomId)` on hidden-lever reveal.

## Acceptance criteria

- [x] For every edge on a built floor, `NavigationServer3D.map_get_path` between the two rooms' centers returns a path with more than one segment and no straight-line fallback (DBL-01).
- [x] Every `NavigationRegion3D` and `NavigationLink3D` on a built floor reports the same non-default navigation map RID (DBL-02).
- [x] Every `sampleNavmesh` placement's resolved world position is inside its own room's blockout AABB (DBL-02).
- [x] Two builds of the same definition produce identical enemy world positions (DBL-02, determinism).
- [x] For every room with `transform.yaw != 0` and an edge, the opened blockout door flag corresponds to the socket facing the neighbor (DBL-03).
- [x] Every secret room is reachable: the parent room's illusory wall or hidden lever has an `Area3D` with mask 2, and triggering it opens the door to the secret room (DBL-04).
- [x] `_build_height_transitions` either builds steps for every edge with a `transform.y` delta, or asserts there are none (DBL-05).
- [x] Loop edges emit `kind: "shortcut"` and the builder opens doors and nav-links them; `_build_shortcut_corridors` removed (DBL-06).
- [x] After `unload_from_parent`, the run scene has no `Rooms`, `DoorwayBridges`, `Landmarks`, `FloorShell`, `NavLinks`, or `Entities` child (DBL-09).
- [x] Building a definition with an unknown `templateId` returns without creating any node and pushes an error (DBL-12).
- [x] Every chest's world position is inside its room's blockout AABB inset by 1.0 (DBL-11).
- [x] `content/fixtures/dungeon_definition_v1_minimal.json` builds to a non-empty floor (DBL-12).
- [x] On a built floor in every biome, the stair room has a `Props/StairCollision` body, the boss is positioned at `Props/BossSpawn`, and the exit portal has a parent (DBL-19).

## Validation

Extended `apps/game/client/scripts/validation/suites/dungeon_suite.gd`:

- `test_cross_room_navigation` — build floor 1 of each of the 10 biomes; for every edge, assert `map_get_path` from room A's spawn to room B's center has more than one point and its final point is within 1.0 of the target.
- `test_boss_reachable_by_path` — assert a navmesh path exists from the entrance spawn to the boss room center on 50 seeds.
- `test_single_nav_map` — assert all regions and links share one RID that is not the default world map.
- `test_placements_inside_own_room` — every enemy, chest, trap, and cover body is inside its room's AABB inset by 1.0.
- `test_build_determinism` — build the same definition twice; assert identical world positions for every enemy, chest, and trap.
- `test_rotated_room_doors` — hand-build a two-room definition with `yaw = 90` on both; assert the opened door flags match the sockets facing each other.
- `test_secret_reachable` — build a floor with a secret; assert the parent room has an interactable secret node, and that calling `reveal_secret` opens the blockout door on both sides.
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
