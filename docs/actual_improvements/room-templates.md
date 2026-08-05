# Room templates — improvement plan

## Current state

`RoomTemplateCatalog.KIND_SPECS` is the single source of truth for room footprints, and the generator positions rooms by summing half-extents from it. Only `castle`, `crystal`, and `swamp` ship scenes that agree with it; the other seven themes ship every kind as a 16 x 12 box with no door openings, so their rooms are spaced for a footprint they do not have and end up with 4-8 unit floor gaps between them. Six of 90 scenes contain any authored mesh — the rest, including every boss arena, are runtime `CastleBlockout` boxes. See [`../existing_codebase/room-templates.md`](../existing_codebase/room-templates.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| RTP-01 | P0 | 63 scenes across 7 themes contradict `KIND_SPECS` (16 x 12, no doors), so rooms are positioned with 4-8 unit gaps and are impassable | `umbral_courtyard.tscn:16-19`, `frozen_puzzle.tscn:16-19`, `vault_stairs.tscn`, `umbral_boss.tscn` vs `room_template_catalog.gd:6-21` |
| RTP-02 | P0 | Template substitution can replace the stairs kit, and `DungeonBuilder` keys the stair lever on the `_stairs` suffix, so the floor becomes unexitable | `room_template_catalog.gd:155-176`, `dungeon_builder.gd:615`, vs the looser `run_floor_config.gd:47-53` |
| RTP-03 | P0 | `socket_toward()` matches a world-space direction against a local-space socket enum, so every yaw-rotated room (entrance, treasure, secret, boss) loses its doorway bridge and nav link | `room_template.gd:31-52`; `castle_boss.tscn:24` has only `Socket_N`; consumers `dungeon_builder.gd:215-218,357-360` |
| RTP-04 | P0 | 84 of 90 room scenes are procedural blockout with no authored layout; the boss arena is a bare box | `castle_boss.tscn:9-39`; only 6 scenes contain a `MeshInstance3D` |
| RTP-05 | P1 | Doorway bridges are sized `span * 0.35`, too small to cover the gap they exist for, and are skipped entirely when a socket is missing | `dungeon_builder.gd:226-232` |
| RTP-06 | P1 | The 7 clone themes ship only N/S sockets, so no east-west connection in those themes can ever produce a bridge or nav link | `umbral_courtyard.tscn:23-33` |
| RTP-07 | P1 | Marker coverage is 18 of 90 scenes for `Props`, 3 for `Props/StairRamp`, 3 for `Props/BossSpawn`/`ExitPortalMarker`, and 1 for `SpawnPoints/LeverSpawn`; the 7 clone themes have no `Props` at all, so stair collision, secret mechanisms, and the exit portal parent are all skipped | `castle_stairs.tscn:44,49`, `umbral_boss.tscn:9-42`; consumers `stair_collision_builder.gd:10-12`, `dungeon_builder.gd:317-319,552,585,596-598,655` |
| RTP-08 | P1 | `corridor` exists in `KIND_SPECS` with no scene and no biome reference, while the stairs kit doubles as the corridor | `room_template_catalog.gd:9`, `room_graph_assigner.gd:106-115` |
| RTP-09 | P2 | `DoorwaySocket.is_secret` is authored on 3 scenes and read by nothing | `castle_courtyard.tscn:50`; no reader in `apps/game/client/scripts` |
| RTP-10 | P2 | `RoomTemplateCatalog._yaw_to_align` duplicates `yaw_to_align_doors` with no call sites | `room_template_catalog.gd:139-140` |
| RTP-11 | P2 | The C# `RoomTemplateCatalog` duplicates all 90 specs with no test asserting it matches `KIND_SPECS` | `packages/procedural/Biome/RoomTemplateCatalog.cs` |

## Target design

The kit is the single largest quality lever in the dungeon: authored rooms with real silhouettes, correct footprints, and hand-placed props. Fix correctness first (RTP-01 through RTP-03 are all "the dungeon does not connect"), then replace blockout with authored content theme by theme.

### 1. One source of truth for footprints (RTP-01)

Rather than hand-editing 63 scenes and hoping they stay in sync, make `KIND_SPECS` the only place the numbers live and have the scene read them.

`CastleBlockout` gains an exported `kind: StringName` and, when it is set, derives `room_width`, `room_depth`, and the four `door_*` flags from `RoomTemplateCatalog.get_spec()` in `_ready()` before `_rebuild()`. `room_width`/`room_depth`/`door_*` remain exported for the debug arenas that build blockouts directly (`dungeon_builder.gd:409-433`), but every scene under `scenes/rooms/` sets `kind` instead of the raw numbers. A scene that sets both fails a validation assertion.

Sockets stay authored (they carry position and rotation), but their positions become derivable, so add a `@tool` verification: `CastleBlockout` in the editor pushes a warning when a `DoorwaySocket` sibling is more than 0.01 from the wall face implied by `kind`.

Rejected alternative: relaxing `RoomGraphGeometry` to read the instantiated blockout's real dimensions. Generation must run headless without instantiating scenes (`procgen_suite.gd` and the CLI both do), so geometry cannot depend on scene data.

### 2. Socket completeness and rotation correctness (RTP-03, RTP-06)

Every room scene ships all four sockets, regardless of which doors its kind opens. A socket for a wall with no door is still the correct attachment point once `_sync_blockout_doors_from_edges` opens it. This alone removes the `null` socket path in `DungeonBuilder`.

Then fix the frame mismatch. `RoomTemplate` gains a world-space lookup and the local-space one becomes private:

```gdscript
func socket_toward(other: RoomTemplate) -> DoorwaySocket:
    var want := (other.global_position - global_position)
    want.y = 0.0
    want = want.normalized()
    var best: DoorwaySocket = null
    var best_dot := 0.5          # reject anything not facing roughly the right way
    for socket in get_sockets():
        var dot := socket.get_world_facing().dot(want)
        if dot > best_dot:
            best_dot = dot
            best = socket
    return best
```

`DungeonBuilder._open_blockout_door_toward()` (`dungeon_builder.gd:186`) has the same bug in the other direction: it sets a *local* blockout flag from a *world* delta. Change it to derive the flag from the resolved socket's `direction`:

```gdscript
var socket := from_room.socket_toward(to_room)
if socket == null:
    push_error("No socket from %s toward %s" % [from_room.room_id, to_room.room_id])
    return
match socket.direction:
    CastleRoomConstants.Direction.NORTH: blockout.door_north = true
    ...
```

`RoomTemplate.door_mask_toward()` keeps its world-space contract and is only used for reporting; `room_locked_door_content.gd:78-95` has a private copy of the same bug and must switch to `socket_toward()`.

### 3. Substitution must preserve role (RTP-02, RTP-08)

Two changes:

- `RoomTemplateCatalog.pick_template_for_doors()` gains a `required_kind := ""` argument. When set, only ids of that kind are eligible; if none fits, the function returns `""` and the caller reports failure. `RoomGraphAssigner` passes `required_kind = "stairs"` for the STAIRS slot, `"boss"` for BOSS, `"entrance"` for START, and `"secret"` for SECRET. An empty return propagates as an assignment failure, which — combined with the [`room-graph-procgen.md`](room-graph-procgen.md) RGP-07 rng tie-break — makes `DungeonProcgen`'s retry loop able to find a graph whose stairs slot has a mask the stairs kit supports.
- Ship a real `<theme>_corridor.tscn` per theme (8 x 12, N|S, per `KIND_SPECS:9`) and add it to every biome's `roomTemplateIds`, so the assigner can hand a plain pass-through cell a corridor instead of a courtyard. This closes RTP-08 and reduces substitution pressure on the other kinds.

Additionally, widen the door masks of the kinds that are over-constrained today so substitution is rarely needed at all:

| Kind | Current doors | Target doors | Reason |
|------|---------------|--------------|--------|
| `stairs` | N, S | N, E, S, W | it is the start's neighbor and needs every mask |
| `hall` | E, S, W | N, E, S, W | a 4-way hall is a normal shape |
| `puzzle` | N, S | N, E, S, W | puzzle rooms sit anywhere off-path |
| `entrance` | S | N, E, S, W | the start cell can branch in any direction |
| `treasure`, `secret`, `boss` | single door | unchanged | single-door dead ends are the point, and the yaw math depends on it |

`DungeonBuilder` already closes unused doors implicitly (a door flag is only set for a real edge), so a 4-way spec costs nothing visually.

Finally, make the lever lookup match `RunFloorConfig`: `DungeonBuilder._setup_stair_levers()` selects rooms by `room_type == "corridor"` (which the assigner always sets for the stairs slot) instead of the `_stairs` filename suffix, and asserts exactly one such room exists.

### 4. Authored kits (RTP-04, RTP-05, RTP-07)

Target end state per theme, replacing blockout with authored geometry while keeping `CastleBlockout` as the collision and navmesh source:

- Each scene gets an `Authored` child `Node3D` holding the hand-placed meshes: wall pilasters, floor inlays, a raised dais in `boss`, alcoves in `treasure`, a broken-wall silhouette in `secret`. `CastleBlockout` gains `hide_walls: bool` so an authored scene can keep blockout collision and navmesh while suppressing the generated wall meshes.
- Each scene gets the full marker set: all four `DoorwaySockets`, `SpawnPoints/PlayerSpawn`, `SpawnPoints/LeverSpawn` (stairs), `Props/BossSpawn` and `Props/ExitPortalMarker` (boss), `Props/StairRamp` (stairs), and 2-4 `Props/PropAnchor_<n>` markers that [`diorama-room-dressing.md`](diorama-room-dressing.md) can populate deterministically instead of guessing positions.
- Prop and material variation stays data-driven via the biome kit (see [`biome-registry.md`](biome-registry.md) BIO-01), so a new theme is a JSON file plus a material set, not 9 more scenes.

Priority order: `boss` for all 10 themes first (it is where every floor ends), then `stairs` (it is where every floor is left), then `treasure`/`secret` (the reward beats), then `courtyard`/`hall`/`arena`, then `entrance`/`puzzle`/`corridor`.

Doorway bridges (RTP-05) become unnecessary once footprints match: sockets land on the wall face, `span` is 0, and the `span < 0.5` guard skips. Keep `_build_doorway_bridges` but change its behavior to `push_error` when `span >= 0.5`, because a non-zero span now means a footprint bug rather than something to paper over.

## Work plan

1. **Socket completeness** — add the missing `DoorwaySocket` children to all 90 scenes so every room has N/E/S/W. Landable alone; extra sockets are inert until an edge uses them (RTP-06).
2. **World-space socket resolution** — rewrite `RoomTemplate.socket_toward()`, fix `DungeonBuilder._open_blockout_door_toward()`, delete the private copy in `room_locked_door_content.gd:78-95` (RTP-03).
3. **`CastleBlockout.kind`** — add the exported `kind` and the `_ready()` derivation from `KIND_SPECS`; add the `@tool` socket-position warning (RTP-01, part 1).
4. **Convert the 7 clone themes** — replace the raw `room_width`/`room_depth`/`door_*` lines in 63 scenes with `kind = "<kind>"`, and move each socket to the wall face the spec implies (RTP-01, part 2). This is the single change that makes those seven biomes playable.
5. **Widen door masks + `required_kind`** — `room_template_catalog.gd:6-21` and `:155`; `room_graph_assigner.gd` passes `required_kind` for the four special roles (RTP-02).
6. **Corridor kit** — 10 new `<theme>_corridor.tscn`, `BiomeRegistry` entries, biome `roomTemplateIds` entries (RTP-08).
7. **Lever lookup by room type** — `dungeon_builder.gd:610-617` selects on `room_type == "corridor"`; add the single-room assertion (RTP-02).
8. **Bridge guard flip** — `dungeon_builder.gd:226` becomes an error path rather than a fallback (RTP-05).
9. **Marker completeness** — a `Props` node in all 100 scenes; `LeverSpawn` in all 10 `_stairs` scenes and `StairRamp` in the 7 missing ones; `BossSpawn` + `ExitPortalMarker` in the 7 `_boss` scenes lacking them; `PropAnchor_<n>` everywhere (RTP-07).
10. **Authored geometry, theme by theme** — `hide_walls` on `CastleBlockout`, then the `Authored` subtree per scene in the priority order above (RTP-04).
11. **Cleanup** — delete `_yaw_to_align` (RTP-10); either read `DoorwaySocket.is_secret` in `DungeonBuilder._place_secret_mechanisms()` to position the illusory wall (see [`dungeon-builder.md`](dungeon-builder.md) DBL-04) or delete the property (RTP-09).
12. **C# spec parity test** — CLI `room-kit-specs` verb and fixture, asserted by `cross_stack_parity_suite.gd` (RTP-11; the suite change is owned by [`room-graph-procgen.md`](room-graph-procgen.md) RGP-05).

## Data and schema changes

- `content/schemas/biome-definition.v1.json` — `roomTemplateIds` gains `<theme>_corridor` in all 10 `content/biomes/*.json` files. No schema edit is needed for that (the array is untyped strings), but the biome kit block from [`biome-registry.md`](biome-registry.md) BIO-01 is where `PropAnchor` prop sets are declared, so land step 9 after that block exists.
- New scene files: `apps/game/client/scenes/rooms/<theme>/<theme>_corridor.tscn` x 10.
- No save-format change: template ids are only stored inside the in-memory definition and the floor cache (`dungeon_builder.gd:49`), never in `local_save.gd`.

## Acceptance criteria

- [ ] For all 90 template ids, the instantiated scene's `CastleBlockout.room_width`/`room_depth` equal `RoomTemplateCatalog.get_spec(id).width`/`depth` (RTP-01).
- [ ] For all 90 template ids, the instantiated scene has exactly 4 `DoorwaySocket` children with distinct `direction` values (RTP-06).
- [ ] For every room in a built floor and every edge touching it, `socket_toward()` returns non-null (RTP-03).
- [ ] For every built floor, adjacent rooms' blockout AABBs touch within 0.01 and no `DoorwayBridges` child is created (RTP-01, RTP-05).
- [ ] Every generated floor has exactly one room with `room_type == "corridor"`, and `DungeonBuilder.get_stair_lever()` is non-null on every non-final floor of all 10 biomes (RTP-02).
- [ ] `pick_template_for_doors(preferred, doors, ids, "stairs")` never returns a non-`stairs` id (RTP-02).
- [ ] All 100 scenes have a `Props` node; every `<theme>_stairs.tscn` has `SpawnPoints/LeverSpawn` and `Props/StairRamp`; every `<theme>_boss.tscn` has `Props/BossSpawn` and `Props/ExitPortalMarker` (RTP-07).
- [ ] `<theme>_corridor.tscn` exists for all 10 themes and is listed in that biome's `roomTemplateIds` (RTP-08).
- [ ] Every `<theme>_boss.tscn` contains at least one node under an `Authored` subtree (RTP-04, first milestone).
- [ ] `RoomTemplateCatalog._yaw_to_align` no longer exists (RTP-10).
- [ ] A checked-in `content/fixtures/room_kit_specs.json` emitted by the C# catalog matches `KIND_SPECS` for all 90 ids (RTP-11).

## Validation

New suite `apps/game/client/scripts/validation/suites/room_kit_suite.gd`:

- `test_all_templates_instantiate` — for each of the 10 biomes, `BiomeRegistry.get_room_scenes()` has exactly 10 entries (9 kinds + corridor) and each `PackedScene.instantiate()` yields a `RoomTemplate`.
- `test_blockout_matches_kind_specs` — instantiate all 100 scenes; assert `room_width`, `room_depth`, and the four `door_*` flags equal `get_spec(template_id)`.
- `test_four_sockets_per_room` — assert 4 sockets with distinct `direction` per scene.
- `test_socket_on_wall_face` — assert each socket's local position is within 0.01 of the wall center implied by its direction and the spec.
- `test_required_markers_present` — the node-name contract table from [`../existing_codebase/room-templates.md`](../existing_codebase/room-templates.md), per kind.
- `test_socket_toward_after_rotation` — instantiate a `<theme>_boss`, set `rotation.y` to each of 0, PI/2, PI, -PI/2, and assert `socket_toward()` against a probe `RoomTemplate` placed in each of the four world directions returns the socket whose `get_world_facing()` points that way.
- `test_required_kind_substitution` — assert `pick_template_for_doors("castle_stairs", DOOR_NORTH | DOOR_EAST, ids, "stairs")` returns a `stairs` id or `""`, never `castle_courtyard`.

Extend `apps/game/client/scripts/validation/suites/dungeon_suite.gd`:

- `test_rooms_abut_without_bridges` — build a floor per biome; assert no `DoorwayBridges` child has children, and that for every edge the two rooms' AABBs touch within 0.01.
- `test_stair_lever_present_all_biomes` — build floor 1 of each of the 10 biomes for 20 seeds; assert `builder.get_stair_lever() != null`.

Manual checklist (art review only, not automatable): for each authored `boss` scene, confirm the dais reads correctly under the fixed diorama camera angle and the `ExitPortalMarker` is visible from `BossSpawn`.

## Related

- [`../existing_codebase/room-templates.md`](../existing_codebase/room-templates.md)
- [`room-graph-procgen.md`](room-graph-procgen.md) — RGP-07 assigner rng, RGP-05 parity suite
- [`dungeon-builder.md`](dungeon-builder.md) — DBL-04 secret mechanisms, doorway bridges, nav links
- [`floor-shell.md`](floor-shell.md) — `CastleBlockout` walls, navmesh, `hide_walls`
- [`biome-registry.md`](biome-registry.md) — BIO-01 data-driven biome kits
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — prop anchors
- [`stair-lever.md`](stair-lever.md) — lever placement markers
- [`pixel-style.md`](../existing_codebase/pixel-style.md) — art direction the authored kits must match
