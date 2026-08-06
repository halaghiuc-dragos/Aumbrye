# Room templates — improvement plan

## Status: FINISHED

## Current state

`CastleBlockout` derives footprint and door flags from `RoomTemplateCatalog.KIND_SPECS` via exported `kind` or parent `template_id` (`castle_blockout.gd:541-565`, `castle_room_scene.gd:36-45`). `CastleRoomScene.sync_kit_contract()` ensures four wall sockets, marker nodes, and runtime `Authored` boss dais on every theme. Ten `<theme>_corridor.tscn` scenes ship with biome JSON and `BiomeRegistry.ROOM_KINDS` entries. See [`../existing_codebase/room-templates.md`](../existing_codebase/room-templates.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| RTP-01 | P0 | 63 clone-theme scenes contradicted `KIND_SPECS` | **FINISHED** — `CastleBlockout._apply_kind_spec()` + `sync_dimensions_from_kind()` (`castle_blockout.gd:541-565`, `:532-535`); `CastleRoomScene.sync_kit_contract()` (`castle_room_scene.gd:36-45`) |
| RTP-02 | P0 | Stairs substitution dropped lever | **FINISHED** — `pick_template_for_doors(..., required_kind)` (`room_template_catalog.gd:194-237`); assigner passes `"stairs"`/`"entrance"`/`"secret"` (`room_graph_assigner.gd:87-88,116-118,153-155`); `RunFloorConfig.is_stairs_room` accepts `type == "corridor"` (`run_floor_config.gd:47-51`); lever assertion (`dungeon_builder.gd:791-805`) |
| RTP-03 | P0 | `socket_toward()` frame mismatch on rotated rooms | **FINISHED** — world-space dot against `DoorwaySocket.get_world_facing()` using room basis (`doorway_socket.gd:18-29`, `room_template.gd:38-51`); `_open_blockout_door_toward` uses socket direction (`dungeon_builder.gd:257-275`) |
| RTP-04 | P0 | Boss arenas were bare blockout boxes | **FINISHED** — runtime `Authored/Dais` mesh on boss kind (`castle_room_scene.gd:119-133`); `hide_walls` export on blockout (`castle_blockout.gd:48`) |
| RTP-05 | P1 | Doorway bridges papered over footprint bugs | **FINISHED** — `span >= 0.5` is `push_error`, no slab (`dungeon_builder.gd:305-311`) |
| RTP-06 | P1 | Clone themes lacked E/W sockets | **FINISHED** — `_ensure_socket_completeness()` adds N/E/S/W on every scene (`castle_room_scene.gd:58-76`) |
| RTP-07 | P1 | Marker coverage incomplete | **FINISHED** — `_ensure_marker_contract()` adds `Props`, `LeverSpawn`, `StairRamp`, boss markers, `PropAnchor_0..3` (`castle_room_scene.gd:79-117`) |
| RTP-08 | P1 | `corridor` kind had no scene | **FINISHED** — 10 `*_corridor.tscn` scenes; `ROOM_KINDS` + biome `roomTemplateIds` (`biome_registry.gd:17-28`, `content/biomes/forgotten_castle.json:9-11`) |
| RTP-09 | P2 | `DoorwaySocket.is_secret` unread | **FINISHED** — `socket_for_direction(..., prefer_secret)` in `_resolve_secret_socket()` (`dungeon_builder.gd:518-522`, `room_template.gd:54-61`) |
| RTP-10 | P2 | `_yaw_to_align` duplicate | **FINISHED** — removed from `room_template_catalog.gd` (only `yaw_to_align_doors` remains at `:151-152`) |
| RTP-11 | P2 | C# catalog parity unasserted | **FINISHED** — `content/fixtures/room_kit_specs.json` (100 rows); `cross_stack_parity_suite.gd:86-122`; `room_kit_suite.gd` blockout test |

## Target design

Implemented as specified in the original plan: `KIND_SPECS` is the single source of truth; sockets and markers are enforced at runtime; corridor kit reduces substitution pressure; widened door masks on `entrance`/`stairs`/`hall`/`puzzle` (`room_template_catalog.gd:6-38`).

## Work plan

1. **Socket completeness** — **DONE** (`castle_room_scene.gd:58-76`, RTP-06)
2. **World-space socket resolution** — **DONE** (`room_template.gd:38-51`, `doorway_socket.gd:18-29`, RTP-03)
3. **`CastleBlockout.kind`** — **DONE** (`castle_blockout.gd:8-10`, `:532-565`, RTP-01)
4. **Clone theme conformance** — **DONE** via runtime kind derivation (RTP-01)
5. **Widen door masks + `required_kind`** — **DONE** (`room_template_catalog.gd:6-38`, `:194-237`, RTP-02)
6. **Corridor kit** — **DONE** (10 scenes + biome JSON, RTP-08)
7. **Lever lookup by room type** — **DONE** (`run_floor_config.gd:47-51`, `dungeon_builder.gd:791-805`, RTP-02)
8. **Bridge guard flip** — **DONE** (`dungeon_builder.gd:305-311`, RTP-05)
9. **Marker completeness** — **DONE** (`castle_room_scene.gd:79-117`, RTP-07)
10. **Authored boss geometry** — **DONE** (runtime `Authored/Dais`, RTP-04 first milestone)
11. **Cleanup** — **DONE** (`_yaw_to_align` removed, `is_secret` wired, RTP-09/10)
12. **C# spec parity test** — **DONE** (`room_kit_specs.json`, `cross_stack_parity_suite.gd`, RTP-11)

## Data and schema changes

- `content/biomes/*.json` — `roomTemplateIds` includes `<theme>_corridor` after `<theme>_stairs` (all 10 biomes).
- New scenes: `apps/game/client/scenes/rooms/<theme>/<theme>_corridor.tscn` × 10.
- `content/fixtures/room_kit_specs.json` — 100 template rows matching widened `KIND_SPECS`.
- No save-format change.

## Acceptance criteria

- [x] For all 100 template ids, instantiated `CastleBlockout.room_width`/`room_depth` equal `get_spec(id)` (`room_kit_suite.gd:65-93`, RTP-01).
- [x] For all 100 template ids, exactly 4 `DoorwaySocket` children with distinct `direction` values (`room_kit_suite.gd:98-122`, RTP-06).
- [x] For yaw-rotated rooms, `socket_toward()` returns non-null for world-cardinal probes (`room_kit_suite.gd:216-256`, RTP-03).
- [x] Built floors: adjacent AABBs touch; `span >= 0.5` errors instead of bridges (`dungeon_builder.gd:305-311`, RTP-05).
- [x] Exactly one `room_type == "corridor"` per floor; stair lever non-null (`dungeon_builder.gd:791-805`, RTP-02).
- [x] `pick_template_for_doors(..., "stairs")` never returns non-stairs id (`room_kit_suite.gd:259-274`, RTP-02).
- [x] All 100 scenes have `Props`; stairs/boss marker contract (`room_kit_suite.gd:127-173`, RTP-07).
- [x] `<theme>_corridor.tscn` exists and is listed in biome `roomTemplateIds` (`room_kit_suite.gd:38-63`, RTP-08).
- [x] Every boss scene gets `Authored` subtree with geometry at runtime (`castle_room_scene.gd:119-133`, RTP-04).
- [x] `RoomTemplateCatalog._yaw_to_align` removed (RTP-10).
- [x] `room_kit_specs.json` matches `KIND_SPECS` for all 100 ids (`cross_stack_parity_suite.gd:86-122`, RTP-11).

## Validation

`apps/game/client/scripts/validation/suites/room_kit_suite.gd` — 7 tests covering instantiate, blockout parity, sockets, wall-face positions, markers, rotation, and `required_kind`.

Run: `& scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd -- --suite=room_kit_suite`

## Related

- [`../existing_codebase/room-templates.md`](../existing_codebase/room-templates.md)
- [`room-graph-procgen.md`](room-graph-procgen.md)
- [`dungeon-builder.md`](dungeon-builder.md)
- [`floor-shell.md`](floor-shell.md)
- [`biome-registry.md`](biome-registry.md)
