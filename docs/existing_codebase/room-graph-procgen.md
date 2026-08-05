# Room graph procgen

The two-phase GDScript dungeon generator. Phase 1 builds an abstract grid room graph (`RoomGraphGenerator`); Phase 2 assigns semantic ids and templates (`RoomGraphAssigner`) and resolves world positions by summing template half-extents (`RoomGraphGeometry`). `DungeonProcgen.generate()` orchestrates both and emits the `DungeonDefinition`. This is the live generator for every castle and endless floor.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/procgen/dungeon_procgen.gd` | Orchestrator; builds the `DungeonDefinition` dictionary |
| `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd` | Phase 1: critical path, branches, special rooms, secrets, bbox fill, validation, fallback |
| `apps/game/client/scripts/dungeon/procgen/room_graph.gd` | Graph container (`slots`, `walk_edges`, `start_id`, `boss_id`, `treasure_id`, `stairs_id`, `secret_ids`) |
| `apps/game/client/scripts/dungeon/procgen/room_graph_slot.gd` | One grid cell: `slot_type`, `door_mask`, `graph_distance`, `is_filler`, `height_level` |
| `apps/game/client/scripts/dungeon/procgen/room_graph_config.gd` | Tunables derived from the biome JSON |
| `apps/game/client/scripts/dungeon/procgen/room_graph_assigner.gd` | Phase 2a: slot -> `semantic_id` + `template_id` + `type` |
| `apps/game/client/scripts/dungeon/procgen/room_graph_geometry.gd` | Phase 2b: world positions, yaws, edges, door-topology check |
| `apps/game/client/scripts/dungeon/procgen/room_graph_paths.gd` | Door-mask adjacency, BFS, critical path (used by room content) |
| `apps/game/client/scripts/dungeon/procgen/room_graph_debug.gd` | ASCII dump when `config.debug_ascii` |

## How it works

### Config from biome

`RoomGraphConfig.from_biome()` (`room_graph_config.gd:25`) reads only `roomCount.min/max` and `requiresSecret`:

| Field | Formula | Value for `forgotten_castle` (min 18 / max 22) |
|-------|---------|-----------------------------------------------|
| `min_rooms` / `max_rooms` | `roomCount.min` / `roomCount.max` | 18 / 22 |
| `grid_width` = `grid_height` | `maxi(13, ceil(sqrt(max_rooms)) + 6)` | 13 |
| `boss_min_distance` | `clampi(min_rooms / 4, 4, 6)` | 4 |
| `min_dead_ends` | 2 if `requiresSecret` else 1 | 2 |
| `branch_max_depth` | 8 if `min_rooms >= 16` else 4 | 8 |
| `max_neighbor_count` | 4 if `min_rooms >= 16` else 3 | 4 |
| `loop_budget` | 4 if `min_rooms >= 16` else 2 | 4 |
| `allow_2x2_blocks` | true if `min_rooms >= 16` | true |
| `max_generation_attempts` | 256 if `min_rooms >= 16` else 100 | 256 |

`max_secrets` is always 2 (`room_graph_config.gd:14`), never read from the biome. `gridStep` in every biome JSON is read by no GDScript file. `continue_probability_base` (`:18`) and `continue_decay_rate` (`:19`) are declared and never read.

### Phase 1 — `RoomGraphGenerator.generate()`

`generate(config, run_seed)` (`room_graph_generator.gd:34`) loops `config.max_generation_attempts` times calling `_try_generate_once()`, reseeding `run_seed + (attempt + 1) * 1_000_003` after each failure (`:43`). If every attempt fails it returns a fallback graph seeded `run_seed ^ 0xFA11BAC` with `used_fallback: true` (`:44-49`) — `generate()` never returns `ok: false`.

`_try_generate_once()` (`:52`) in order:

1. `target_rooms = rng.randi_range(min_rooms, max_rooms)`; START slot at `config.grid_center()` = `(6, 6)` for a 13x13 grid.
2. `_grow_critical_path()` (`:86`) — self-avoiding walk with direction persistence toward `path_target = maxi(boss_min_distance, target_rooms / 3)`. On a blocked step it shuffles the other three directions; after 12 consecutive stalls it jumps the cursor to a random already-placed path cell (`:131`) and gives up after the 13th (`:129`).
3. `_grow_branches()` (`:136`) — BFS frontier from random path cells until `graph.slots.size() >= target_rooms` or `max_walk_attempts` (8192) is exhausted; depth capped at `branch_max_depth`.
4. `_can_place_room()` (`:182`) rejects out-of-bounds, occupied, `>= max_neighbor_count` occupied neighbors, and (when `allow_2x2_blocks` is false) any placement forming a 2x2 block of non-filler non-secret cells.
5. `_assign_special_rooms()` (`:347`) — BFS `graph_distance` for every slot, boss selection, treasure selection, stairs selection, then `_place_secret_attachments()`.
6. `_fill_bounding_box()` (`:454`) — only when `fill_bounding_box` and the main-slot count is still below `min_rooms`; fills every empty cell in the occupied bounding box with `is_filler = true` NORMAL slots.
7. `_apply_door_connections()` (`:245`) — clears all `door_mask`s, sets doors for every `walk_edge`, then adds up to `loop_budget` extra doors between adjacent non-secret non-filler cells that have no walk edge, then `_apply_secret_door_masks()`.
8. `_validate_graph()` (`:479`) — room count, grid reachability, boss assigned, boss distance, dead-end count, 2x2 blocks. Failure reason is stored in the static `_last_validate_reason` (`:31`).

Special-room selection detail (`:347-403`):

- Boss: highest `graph_distance` at or above `boss_min_distance`, tie-broken by fewest connections (`:370-378`).
- Treasure: a random entry of `remaining_dead_ends` (`:389`).
- Stairs: the START slot's SOUTH neighbor, else the first occupied neighbor in `[N, E, S, W]` order (`:391-402`). This assignment overwrites whatever `slot_type` that cell already had.
- Secrets: up to `max_secrets` empty cells with `>= 2` occupied neighbors; each gets `secret_parent_id` and `secret_mechanism` of `"hidden_lever"` or `"illusory_wall"` at 50/50 (`:435`).

`_compute_distances()` (`:325`) walks **grid adjacency**, not door masks — so `graph_distance` and the `_validate_graph` reachability check both ignore whether a door actually exists. `RoomGraphPaths.build_adjacency()` (`room_graph_paths.gd:7`) is the door-mask-aware version and is used only by the room-content layer.

`_recompute_connections()` (`:241`) and `_pick_random_cell()` (`:202`) have no call sites.

### Phase 2a — `RoomGraphAssigner.assign()`

`assign(biome, graph, _rng)` (`room_graph_assigner.gd:9`) iterates `graph.occupied_cells()` in `(x, y)` order and maps each slot:

| Slot type | `semantic_id` | Preferred template | `type` | `tags` |
|-----------|---------------|--------------------|--------|--------|
| `is_filler` | `filler_<n>` | `<prefix>_hall` | `filler` | `["filler"]` |
| START | `entrance` | `<prefix>_entrance` | `hub` | `["spawn"]` |
| BOSS | `boss` | `<prefix>_boss` (no substitution) | `boss` | `["exit_portal"]` |
| TREASURE | `treasure` | `<prefix>_treasure` | `treasure` | `[]` |
| STAIRS | `stairs` | `<prefix>_stairs` | `corridor` | `[]` |
| OBSTACLE | `obstacle` | `<prefix>_puzzle` | `obstacle` | `["traversal"]` |
| SECRET | `secret` or `secret_<n>` | `<prefix>_secret` | `secret` | `["secret_room"]` |
| NORMAL | `courtyard`, `hall`, `arena`, then `combat_<n>` | matching kind, else `<prefix>_courtyard` | `combat` | `[]` |

Every case except BOSS routes through `RoomTemplateCatalog.pick_template_for_doors(preferred, required_doors, biome.roomTemplateIds)`, which substitutes a different kit piece when the preferred kind's door mask does not cover the slot's `door_mask` (see [`room-templates.md`](room-templates.md)).

The `rng` parameter is unused (`_rng`, `room_graph_assigner.gd:9`), so `assign()` is a pure function of `(biome, graph)`. `DungeonProcgen`'s 12-attempt reassignment loop (`dungeon_procgen.gd:44-54`) therefore recomputes an identical assignment every attempt.

### Phase 2b — `RoomGraphGeometry`

`build_rooms()` (`room_graph_geometry.gd:9`) places the entrance at `(0, 0)`, then BFS over door-masked neighbors. Each step offsets by `half_extent_z(parent) + half_extent_z(child)` (or `_x`), where the half-extents come from `RoomTemplateCatalog.get_spec()` rotated by the room yaw. Yaw is non-zero only for single-door templates — `yaw_rad_for_incoming_door()` returns 0 unless `primary_door_mask(doors) != 0` (`room_template_catalog.gd:91-98`), which is true only for `entrance` (S), `treasure` (N), `secret` (E), and `boss` (N).

Secrets are placed afterwards by `_place_secret_rooms()` (`:242`) relative to their parent. Rooms with no computed position are dropped with `push_error("Room '%s' has no world position")` (`:87`). The result array is sorted by room id (`:103`).

`build_edges()` (`:109`) emits one edge per door-connected non-secret pair with `kind = "corridor"` when either endpoint's `type` is `corridor`, otherwise `"door"`, plus one `kind = "secret"` edge per secret-parent pair. `_append_shortcut_edges()` (`:233`) is `pass` with the comment "Disabled: one-way shortcut edges created phantom nav links without geometry bridges" — no `one_way` edge is ever emitted.

`validate_door_topology()` (`:156`) duplicates the `build_rooms` walk and returns the first door mismatch. `_door_satisfied()` (`:330`) accepts a template either if its spec contains the door outright, or if it is a single-door template whose rotation aligns. `_warn_door_mismatch()` (`:314`) has no call sites.

`HEIGHT_STEP := 3.0` (`:6`) multiplies `slot.height_level` into `transform.y`. `height_level` is only ever copied from a parent slot (`room_graph_generator.gd:116`, `:170`) and never assigned a non-zero value, so `transform.y` is always `0.0` and `heightLevel` is always `0`.

### DungeonDefinition assembly

`DungeonProcgen.generate()` (`dungeon_procgen.gd:18`):

- `is_final_floor` short-circuits to `_generate_final_floor()` (`:27`).
- `assign_rng.seed = run_seed ^ 0x5EED + attempt * 1_000_003` (`:45`). GDScript binds `+` tighter than `^`, so this is `run_seed ^ (0x5EED + attempt * 1_000_003)`.
- The same `assign_rng` instance is passed to `ProcgenPlacements.place()` (`:60`) and then `RoomContentAssigner.assign()` (`:63`), so content assignment consumes RNG state left by placements.
- `run_id = _deterministic_run_id(run_seed, biome_id, floor_index)` (`:180`) = `"%08x-0000-4000-8000-%012x"` over `run_seed ^ (biome_id.hash() & 0x7FFFFFFF) ^ (floor_index * 7919)`.
- `_build_landmark_hints()` (`:186`) emits `boss_spire` and `boss_silhouette` box hints at the boss room, plus `orientation_spire` near the entrance.

Emitted root keys (`:69-102`): `schemaVersion`, `runId`, `seed`, `biomeId`, `tier`, `playerLevelSnapshot`, `rooms`, `edges`, `placements`, `budgets`, `floorIndex`, `isFinalFloor`, `roomContent`, `locks`, `puzzles`, `branchPreviews`, `landmarks`.

`_generate_final_floor()` (`:112`) is fully hardcoded: two rooms (`<prefix>_entrance` at z 0, `<prefix>_boss` at z 20), one `door` edge, two chests with `health_potion` and `elixir_might`, and `boss.enemyId = "final_boss_forgotten_castle"` for every biome (`:164`). It emits no `roomContent`, `locks`, `branchPreviews`, or `landmarks`.

### Schema conformance

`content/schemas/dungeon-definition.v1.json` declares `additionalProperties: false` at the root (`:7`), on `room` (`:77`), and on `placements` (`:108`). The GDScript definition violates it in five ways:

| Violation | Emitted at | Schema |
|-----------|-----------|--------|
| root `floorIndex`, `isFinalFloor`, `roomContent`, `locks`, `puzzles`, `branchPreviews`, `landmarks` | `dungeon_procgen.gd:93-101` | allowed root keys are only the 10 required plus `checksum` (`:20-61`) |
| `room.heightLevel` | `room_graph_geometry.gd:101` | `room` allows `id`, `templateId`, `type`, `transform`, `tags` (`:79-90`) |
| `room.type == "filler"` | `room_graph_assigner.gd:75` | enum lacks `filler` and `obstacle` (`:84`) |
| `placements.cover` | `dungeon_procgen.gd:84` | `placements` has no `cover` property (`:119-128`) |
| no `checksum` | never emitted | optional, so not a violation, but the C# path always emits one |

The C# CLI output (`seed99999.json:1`) contains only schema-legal keys, so the fallback generator is schema-conformant and the primary one is not. `scripts/validate-content/validate.mjs` validates only files under `content/fixtures/`, so neither path is checked in CI.

### What cross-stack parity actually asserts

`apps/game/client/scripts/validation/suites/cross_stack_parity_suite.gd` has four tests and **none of them runs or compares the C# generator**:

| Test | Line | What it asserts |
|------|------|-----------------|
| `_test_biome_prefix_parity` | `:32` | `kind_from_template_id("<prefix>_entrance") == "entrance"` for all 10 biomes — GDScript only |
| `_test_gdscript_generation_schema` | `:51` | the GDScript definition **has** `roomContent`, `locks`, `puzzles` and `floorIndex == 1` — i.e. it asserts the keys that violate the JSON schema |
| `_test_affix_determinism` | `:72` | `AffixRoller.roll_identical` is stable — unrelated to procgen |
| `_test_affix_content_single_source` | `:92` | `content/affixes/*.json` have the expected top-level keys |

Comparing GDScript and C# layouts, checksums, or seed math: ABSENT. Searched `cross_stack_parity_suite.gd`, `procgen_suite.gd`, `room_graph_suite.gd`, and `dungeon_suite.gd`.

## Contracts

- `DungeonProcgen.generate()` returns `{ok, definition, generation_seed, run_id, used_fallback}`; consumed by `LocalProcgen` (`local_procgen.gd:35`).
- `RoomGraphPaths.critical_path_ids()` and `bfs_distances()` are the door-aware graph API consumed by `RoomContentAssigner` (`room_content_assigner.gd:15`, `:22`) and `RoomContentValidator`.
- `RoomGraphSlot.DOOR_NORTH/EAST/SOUTH/WEST` (`1/2/4/8`) are referenced outside procgen by `dungeon_builder.gd:192-199`, `room_template.gd:34`, and `room_locked_door_content.gd:81`.
- `graph.secret_ids`, `graph.stairs_id`, `graph.boss_id`, `graph.treasure_id` are read by the assigner and by `ProcgenPlacements`.
- `assignment` dictionary shape: `{rooms: [{layout_id, semantic_id, template_id, type, tags}], entrance_layout_id, boss_layout_id, secret_layout_ids, treasure_layout_id, stairs_layout_id}`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Grid graph generation with branches and loops | IMPLEMENTED | `room_graph_generator.gd:52-83` |
| Deterministic same-seed layout | IMPLEMENTED | all RNG derived from `run_seed`; asserted by `room_graph_suite.gd` |
| Treasure room selection | BROKEN | `dead_ends` is computed at `room_graph_generator.gd:352-358` before `_apply_door_connections()` (`:80`) sets any `door_mask`, so `is_dead_end()` (`room_graph_slot.gd:52`, requires `connection_count() == 1`) is false for every slot; `remaining_dead_ends` is always empty and `graph.treasure_id` is never set on the primary path |
| Stairs assignment overwriting another special room | BROKEN | `room_graph_generator.gd:391-402` reassigns the START neighbor's `slot_type` unconditionally |
| `SlotType.SHOP` | ABSENT | declared at `room_graph_slot.gd:12`, never assigned; searched all of `procgen/` |
| `SlotType.OBSTACLE` | STUB | declared at `room_graph_slot.gd:15`, never assigned, so the assigner's OBSTACLE branch (`room_graph_assigner.gd:116-125`) is unreachable |
| Filler rooms | BROKEN | `_apply_door_connections` excludes fillers from loop candidates (`:259`, `:266`) and they have no walk edges, so a filler ends with `door_mask == 0`: a sealed room that `build_rooms` still positions |
| Real (door-aware) reachability validation | ABSENT | `_compute_distances` uses grid adjacency (`room_graph_generator.gd:335-343`); no validator uses `RoomGraphPaths.build_adjacency` |
| Multi-level dungeons | STUB | `height_level` never set non-zero (`room_graph_generator.gd:116`, `:170`); `HEIGHT_STEP` therefore unused |
| One-way / shortcut edges | STUB | `_append_shortcut_edges` is `pass` (`room_graph_geometry.gd:233-239`) while the schema enum still allows `one_way` (`dungeon-definition.v1.json:102`) |
| Assignment retry loop | STUB | `RoomGraphAssigner.assign` ignores its `rng` (`room_graph_assigner.gd:9`), so all 12 attempts in `dungeon_procgen.gd:44` are identical |
| Fallback layout | PARTIAL | always succeeds but is a single corridor chain (`room_graph_generator.gd:551-608`); only `push_warning` marks it (`dungeon_procgen.gd:38`) |
| `_recompute_connections`, `_pick_random_cell`, `_warn_door_mismatch` | STUB | no call sites (`room_graph_generator.gd:241`, `:202`; `room_graph_geometry.gd:314`) |
| Schema conformance of the emitted definition | BROKEN | five `additionalProperties`/enum violations, listed above |
| Final floor | PLACEHOLDER | two hardcoded rooms and a castle-only boss id for all 10 biomes (`dungeon_procgen.gd:112-171`) |
| Cross-stack parity assertions | ABSENT | `cross_stack_parity_suite.gd` never invokes `packages/procedural` or `tools/procgen-cli` |
| `gridStep`, `max_secrets` from biome, `continue_probability_base`, `continue_decay_rate` | STUB | `room_graph_config.gd:14`, `:18-19`; `gridStep` has no GDScript reader |

## Related

- Improvement plan: [`../actual_improvements/room-graph-procgen.md`](../actual_improvements/room-graph-procgen.md)
- [`local-procgen.md`](local-procgen.md) — caller and seed derivation
- [`room-templates.md`](room-templates.md) — `RoomTemplateCatalog` specs and the room kits
- [`room-content.md`](room-content.md) — post-layout content and locks
- [`procgen-placements.md`](procgen-placements.md) — enemies, loot, traps
- [`dungeon-builder.md`](dungeon-builder.md) — consumer of the definition
- [`biome-registry.md`](biome-registry.md) — biome JSON and room scene tables
