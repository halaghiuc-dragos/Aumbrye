# Room graph procgen

The two-phase GDScript dungeon generator. Phase 1 builds an abstract grid room graph (`RoomGraphGenerator`); Phase 2 assigns semantic ids and templates (`RoomGraphAssigner`) and resolves world positions by summing template half-extents (`RoomGraphGeometry`). `DungeonProcgen.generate()` orchestrates both and emits `dungeon-definition.v2.json` definitions. This is the live generator for every castle and endless floor.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/procgen/dungeon_procgen.gd` | Orchestrator; builds the `DungeonDefinition` dictionary (`schemaVersion: 2`) |
| `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd` | Phase 1: critical path, branches, bbox fill, filler connect, doors, reservation pass, validation |
| `apps/game/client/scripts/dungeon/procgen/room_graph.gd` | Graph container with O(1) `_index` lookup |
| `apps/game/client/scripts/dungeon/procgen/room_graph_slot.gd` | One grid cell: `slot_type`, `door_mask`, `graph_distance`, `is_filler`, `height_level` |
| `apps/game/client/scripts/dungeon/procgen/room_graph_config.gd` | Tunables derived from the biome JSON |
| `apps/game/client/scripts/dungeon/procgen/room_graph_assigner.gd` | Phase 2a: slot â†’ `semantic_id` + `template_id` + `type` (RNG tie-break) |
| `apps/game/client/scripts/dungeon/procgen/room_graph_geometry.gd` | Phase 2b: world positions, yaws, edges, door-topology check |
| `apps/game/client/scripts/dungeon/procgen/room_graph_paths.gd` | Door-mask adjacency, BFS, `connected_component` |
| `apps/game/client/scripts/dungeon/procgen/room_graph_debug.gd` | ASCII dump when `config.debug_ascii` |
| `content/schemas/dungeon-definition.v2.json` | Schema for GDScript generator output |

## How it works

### Config from biome

`RoomGraphConfig.from_biome()` (`room_graph_config.gd:26`) reads `roomCount`, `requiresSecret`, `maxHeightLevel`, and `maxSecrets`:

| Field | Formula | Value for `forgotten_castle` (min 18 / max 22) |
|-------|---------|-----------------------------------------------|
| `min_rooms` / `max_rooms` | `roomCount.min` / `roomCount.max` | 18 / 22 |
| `grid_width` = `grid_height` | `maxi(13, ceil(sqrt(max_rooms)) + 6)` | 13 |
| `boss_min_distance` | `clampi(min_rooms / 4, 4, 6)` | 4 |
| `min_dead_ends` | 4 if `requiresSecret` else 3 when `min_rooms >= 12`, scaled down for small biomes | 4 |
| `max_secrets` | `biome.maxSecrets` (default 2) | 2 |
| `max_height_level` | `biome.maxHeightLevel` (default 0) | 0 |

### Phase 1 â€” `RoomGraphGenerator.generate()`

`generate(config, run_seed)` (`room_graph_generator.gd:35`) loops `config.max_generation_attempts` times. On total failure returns `{ok: false, reason}` (`:44`); no fallback graph.

`_try_generate_once()` order (`:52`):

1. START slot via `graph.add_slot`
2. `_grow_critical_path` â€” optional `height_level` step every 4 path cells when `max_height_level > 0`
3. `_grow_branches`
4. `_fill_bounding_box` when below `min_rooms`
5. `_connect_fillers` â€” walk edge to nearest grid neighbor; orphan fillers removed
6. `_apply_door_connections` â€” walk edges + loop budget (fillers included)
7. `_assign_special_rooms` â€” reservation pass: boss â†’ stairs â†’ treasure â†’ shop (35%) â†’ obstacle
8. `_place_secret_attachments`
9. `_apply_secret_door_masks`
10. `_validate_graph` â€” door-component reachability, required roles, sealed-room check, height gap â‰¤ 1

`graph_distance` is populated from `RoomGraphPaths.bfs_distances` during special-room assignment.

### Phase 2a â€” `RoomGraphAssigner.assign()`

`assign(biome, graph, rng)` (`room_graph_assigner.gd:9`) maps slots including `SHOP` â†’ `type: "shop"` and `OBSTACLE` â†’ `type: "obstacle"`. Template substitution uses `RoomTemplateCatalog.pick_template_for_doors(..., rng)` for RNG tie-break among valid kits.

### Phase 2b â€” `RoomGraphGeometry`

`build_edges()` emits `door`, `corridor`, `shortcut`, and `secret` kinds only â€” no `one_way`. `build_rooms()` writes `heightLevel` on each room from `slot.height_level`.

### DungeonDefinition assembly

`DungeonProcgen.generate()` emits `schemaVersion: 2` with `floorIndex`, `isFinalFloor`, `roomContent`, `locks`, `puzzles`, `branchPreviews`, `landmarks`, and `placements.cover`.

`_generate_final_floor()` reads `biome.finalFloor.bossId` and builds a three-room entranceâ†’arenaâ†’boss layout.

### Schema conformance

GDScript output validates against `content/schemas/dungeon-definition.v2.json`. Checked-in reference: `content/fixtures/dungeon_definition_v2_gdscript.json` (forgotten_castle seed 4242).

### Cross-stack parity

`cross_stack_parity_suite.gd` compares GDScript `FloorSeedMix` against `content/fixtures/mix_seed_parity.json` and `RoomTemplateCatalog.KIND_SPECS` against `content/fixtures/room_kit_specs.json` (from `tools/procgen-cli room-kit-specs`). Affix tests live in `affix_suite.gd`.

## Contracts

- `RoomGraphGenerator.generate()` returns `{ok, graph}` or `{ok: false, reason}`; `last_validate_reason()` exposes the last validation failure.
- `RoomGraph.add_slot` / `remove_slot` maintain `_index` for O(1) `get_slot(slot_id)`.
- `RoomGraphPaths.connected_component(graph, start_id)` is the door-aware reachability API used by validation and room content.
- `assignment` dictionary shape unchanged; `graph.shop_id` added for merchant rooms.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Grid graph generation with branches and loops | IMPLEMENTED | `room_graph_generator.gd` |
| Deterministic same-seed layout | IMPLEMENTED | `room_graph_suite.gd` `test_phase1_deterministic` |
| Treasure / stairs / boss reservation | IMPLEMENTED | `_assign_special_rooms` reservation pass |
| Filler connectivity | IMPLEMENTED | `_connect_fillers` |
| Door-aware reachability validation | IMPLEMENTED | `RoomGraphPaths.connected_component` |
| Schema v2 conformance | IMPLEMENTED | `dungeon-definition.v2.json`, `validate.mjs` |
| Assigner RNG tie-break | IMPLEMENTED | `pick_template_for_doors(..., rng)` |
| Shop / obstacle roles | IMPLEMENTED | reservation pass + assigner branches |
| Height levels | IMPLEMENTED | gated by `max_height_level` (default 0) |
| Fallback graph | ABSENT | deleted; failure returns `reason` |
| Cross-stack parity fixtures | IMPLEMENTED | `mix_seed_parity.json`, `room_kit_specs.json` |
| Final floor from biome | IMPLEMENTED | `finalFloor.bossId` in all 10 biome JSON files |

## Related

- Improvement plan: [`../actual_improvements/room-graph-procgen.md`](../actual_improvements/room-graph-procgen.md) - **FINISHED**
- [`local-procgen.md`](local-procgen.md)
- [`room-templates.md`](room-templates.md)
- [`room-content.md`](room-content.md)
- [`procgen-placements.md`](procgen-placements.md)
- [`dungeon-builder.md`](dungeon-builder.md)
- [`biome-registry.md`](biome-registry.md)
