# Room graph procgen — improvement plan

## Current state

Phase 1 produces a valid Isaac-style grid graph deterministically, and Phase 2 resolves world positions by summing template half-extents. Three ordering bugs undercut it: special rooms are chosen before door masks exist so the treasure room is never assigned; the stairs slot overwrites whatever special type already sat on the start's neighbor; and bounding-box filler rooms end with `door_mask == 0`, producing sealed boxes that are still positioned in the world. The emitted `DungeonDefinition` violates `content/schemas/dungeon-definition.v1.json` in five places, and `cross_stack_parity_suite.gd` asserts nothing about the C# generator. See [`../existing_codebase/room-graph-procgen.md`](../existing_codebase/room-graph-procgen.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| RGP-01 | P0 | Emitted definition violates the schema: 7 extra root keys, `room.heightLevel`, `room.type == "filler"`, `placements.cover` | `dungeon_procgen.gd:93-101`, `room_graph_geometry.gd:101`, `room_graph_assigner.gd:75`, `dungeon_procgen.gd:84` vs `dungeon-definition.v1.json:7,77,84,108` |
| RGP-02 | P0 | Treasure room is never assigned: `dead_ends` is computed before any `door_mask` is set, so `is_dead_end()` is always false | `room_graph_generator.gd:352-358` runs before `_apply_door_connections` at `:80`; `room_graph_slot.gd:52` |
| RGP-03 | P0 | Stairs assignment overwrites the `slot_type` of the start's neighbor, silently destroying a TREASURE or other special role | `room_graph_generator.gd:391-402` |
| RGP-04 | P0 | Bounding-box filler rooms get no doors and are built as sealed boxes inside the dungeon | `room_graph_generator.gd:259,266` exclude fillers from loop candidates; `room_graph_geometry.gd:95-102` still positions them |
| RGP-05 | P0 | `cross_stack_parity_suite.gd` asserts no parity at all; all four tests are GDScript-only, and one of them asserts the schema-violating keys | `cross_stack_parity_suite.gd:32,51,72,92` |
| RGP-06 | P1 | Reachability validation uses grid adjacency, not doors, so a door-disconnected component passes validation | `room_graph_generator.gd:335-343`, `:491-497` |
| RGP-07 | P1 | The 12-attempt reassignment loop can never change anything because `RoomGraphAssigner.assign` ignores its `rng` | `room_graph_assigner.gd:9`, `dungeon_procgen.gd:44-54` |
| RGP-08 | P1 | Final-floor generator is hardcoded: 2 rooms, castle-only boss id for all 10 biomes, no room content or locks | `dungeon_procgen.gd:112-171`, boss id at `:164` |
| RGP-09 | P1 | Multi-level dungeons are dead: `height_level` is never set non-zero, so `HEIGHT_STEP` and `heightLevel` are inert | `room_graph_generator.gd:116,170`, `room_graph_geometry.gd:6,94` |
| RGP-10 | P1 | Fallback graph is a bare corridor chain and is reported only as a `push_warning`; the player and the run record never learn the floor was a fallback | `room_graph_generator.gd:551-608`, `dungeon_procgen.gd:37-38` |
| RGP-11 | P2 | `SlotType.SHOP` and `SlotType.OBSTACLE` are never assigned, making the assigner's OBSTACLE branch unreachable | `room_graph_slot.gd:12,15`, `room_graph_assigner.gd:116-125` |
| RGP-12 | P2 | `one_way` edges are permanently disabled in geometry but still legal in the schema and still branched on by three consumers | `room_graph_geometry.gd:233-239`; consumers `dungeon_builder.gd:176,209,347,391` |
| RGP-13 | P2 | Dead code: `_recompute_connections`, `_pick_random_cell`, `_warn_door_mismatch`, `continue_probability_base`, `continue_decay_rate`; `gridStep` and biome-level `max_secrets` have no reader | `room_graph_generator.gd:241,202`, `room_graph_geometry.gd:314`, `room_graph_config.gd:14,18-19` |
| RGP-14 | P2 | `RoomGraph.get_slot()` is an O(n) linear scan over all slots and is called per-room by three modules | `room_graph.gd:16-21`; callers `procgen_placements.gd:78,138,170`, `room_content_assigner.gd:63,70` |

## Target design

### 1. Fix the generation order (RGP-02, RGP-03, RGP-04)

Reorder `_try_generate_once()` so door masks exist before any decision that depends on connectivity:

```
1. place START
2. _grow_critical_path
3. _grow_branches
4. _fill_bounding_box            <-- moved up, unconditional when config.fill_bounding_box
5. _connect_fillers              <-- NEW
6. _apply_door_connections       <-- moved up
7. _assign_special_rooms         <-- moved down; now sees real door masks
8. _place_secret_attachments     <-- split out of _assign_special_rooms
9. _apply_secret_door_masks
10. _validate_graph
```

`_connect_fillers(graph)`: for each `is_filler` slot, add a `walk_edge` to its lowest-`graph_distance` non-secret orthogonal neighbor, then include fillers in the loop-candidate pass. A filler with no non-secret neighbor is deleted from `graph.slots` rather than left sealed. This makes RGP-04 impossible by construction — no slot can survive with `door_mask == 0`, which becomes a `_validate_graph` invariant (`sealed_room` reason).

Special-room assignment becomes explicit and non-overlapping. Replace the current sequence with a single reservation pass over a `reserved: Dictionary[String, String]` map (`slot_id -> role`), assigning in priority order and refusing to overwrite:

| Order | Role | Rule |
|-------|------|------|
| 1 | `boss` | max `door_distance` >= `boss_min_distance`, tie-break fewest connections, then `slot_id` ascending for determinism |
| 2 | `stairs` | nearest unreserved dead end with `door_distance >= 2`; if none, the start's SOUTH neighbor, then any unreserved neighbor |
| 3 | `treasure` | unreserved dead end with maximum `door_distance` |
| 4 | `shop` | unreserved dead end with `door_distance in [2, boss_distance - 2]`, present on 35% of floors (rolled from the graph rng) |
| 5 | `obstacle` | unreserved on-critical-path slot with exactly 2 doors, at most 1 per floor |

`_validate_graph` gains `boss`, `stairs`, and `treasure` as required roles, so a graph that cannot supply three distinct dead ends is rejected and regenerated instead of silently shipping without a treasure room. This is why `min_dead_ends` must rise to 3 (4 when `requiresSecret`) in `RoomGraphConfig.from_biome`.

Rejected alternative: patching `is_dead_end()` to fall back to grid adjacency. That would keep two different notions of "connected" in the codebase, which is the root cause of RGP-06.

### 2. Single door-aware graph API (RGP-06, RGP-14)

Delete `RoomGraphGenerator._compute_distances()` and route everything through `RoomGraphPaths`:

```gdscript
# room_graph_paths.gd
static func build_adjacency(graph: RoomGraph) -> Dictionary          # existing, door-mask based
static func bfs_distances(graph: RoomGraph, start_id: String) -> Dictionary   # existing
static func connected_component(graph: RoomGraph, start_id: String) -> Dictionary  # NEW
```

`_validate_graph` asserts `connected_component(graph, start_id).size() == main_slot_count` (secrets excluded, since they are reached through their parent's secret door). `slot.graph_distance` is populated from `bfs_distances`, making the value that `ProcgenPlacements` uses for enemy counts and side-loot tiering a real traversal distance.

`RoomGraph` gains an `_index: Dictionary` (`slot_id -> Vector2i`) maintained by a new `RoomGraph.add_slot(cell, slot)` / `remove_slot(cell)` pair, turning `get_slot()` into an O(1) lookup (RGP-14). No caller signature changes.

### 3. Schema reconciliation (RGP-01)

The extra keys are all genuinely needed by shipping consumers (`minimap.gd:23` reads `branchPreviews`, `dungeon_builder.gd:104,262` read `cover` and `landmarks`, `room_content_spawner.gd:20,44` read `roomContent` and `locks`), so the schema is what is wrong. Bump to `content/schemas/dungeon-definition.v2.json` with `schemaVersion: 2` and:

- root gains `floorIndex` (integer >= 1), `isFinalFloor` (boolean), `roomContent`, `locks`, `puzzles`, `branchPreviews`, `landmarks`;
- `room` gains `heightLevel` (integer, default 0);
- `room.type` enum gains `filler` and `shop`, and drops `obstacle` unless step 1 ships the obstacle role (it does, so keep it);
- `placements` gains `cover`;
- `edge.kind` drops `one_way` (RGP-12) and gains nothing;
- `$defs` gains real object shapes for `roomContent[]`, `locks[]`, `placements.secrets[]`, and `placements.cover[]` instead of `{type: object}`.

`content/schemas/dungeon-definition.v1.json` stays on disk for the C# path until `packages/procedural` is retired; `scripts/validate-content/validate.mjs` must map `schemaVersion` to the right schema file. Add `content/fixtures/dungeon_definition_v2_gdscript.json` — a checked-in real generator output for `forgotten_castle` seed 4242 floor 1 — so `validate.mjs` covers the primary generator, which it currently does not.

### 4. Real cross-stack parity, or none (RGP-05)

`cross_stack_parity_suite.gd` currently misrepresents its coverage. Two honest options; take the first.

**Chosen:** make the suite compare the two stacks on the one thing that must agree — seed math and the room-kit catalog — and rename the remaining tests out of the parity suite.

```
test_mix_seed_parity        GDScript RunFloorConfig.mix_seed vs a checked-in
                            content/fixtures/mix_seed_parity.json table generated by
                            `dotnet run --project tools/procgen-cli -- mix-seed-table`
test_kind_spec_parity       every id in RoomTemplateCatalog.KIND_SPECS x 10 prefixes has the
                            same width/depth/doors in packages/procedural/Biome/RoomTemplateCatalog.cs,
                            compared against content/fixtures/room_kit_specs.json emitted by the CLI
test_cli_output_is_v1_valid parse seed99999.json-shaped CLI output and assert it satisfies v1
```

`_test_affix_determinism` and `_test_affix_content_single_source` move to a new `affix_suite.gd`; `_test_gdscript_generation_schema` moves to `procgen_suite.gd` and is rewritten to validate against v2 rather than to assert the presence of illegal keys.

Rejected alternative: full layout parity between the generators. The C# generator uses a different algorithm and emits no room content; making the layouts identical would mean reimplementing all of Phase 1 in C#, and the CLI is no longer a runtime fallback after [`local-procgen.md`](local-procgen.md) LPG-01.

### 5. Height levels, for real (RGP-09)

Assign `height_level` during `_grow_critical_path`: every `HEIGHT_RUN_LENGTH = 4` consecutive critical-path steps, roll `rng.randf() < 0.35` and step the level by `+1` (capped at `MAX_HEIGHT_LEVEL = 2`); branches inherit their parent's level (already the behavior at `room_graph_generator.gd:170`). `_validate_graph` rejects any door between slots whose `height_level` differs by more than 1.

`RoomGraphGeometry` already handles `transform.y`. The missing half is `DungeonBuilder._build_height_transitions()` — see [`dungeon-builder.md`](dungeon-builder.md) DBL-01. Ship this step only after DBL-01, and gate it behind `RoomGraphConfig.max_height_level` defaulting to 0 so the two can land independently.

### 6. Honest fallbacks and provenance (RGP-07, RGP-10)

- `RoomGraphAssigner.assign` uses its `rng` to break ties between equally valid substitutions (see [`room-templates.md`](room-templates.md) RTP-02), which makes `DungeonProcgen`'s retry loop meaningful.
- `generate()` returns `{ok: false, reason: <last_validate_reason>}` when every attempt fails, instead of a corridor chain. `RoomGraphGenerator` exposes `last_validate_reason()` as a public static. The retry ladder in [`local-procgen.md`](local-procgen.md) LPG-01 then handles it.
- `_build_fallback_graph` and `used_fallback` are deleted.

### 7. Final-floor generation (RGP-08)

Replace `_generate_final_floor()` with a data-driven arena: read `content/biomes/<id>.json` -> new `finalFloor` block (see below), generate a 3-room layout (`entrance` -> `arena` -> `boss`) through the normal Phase 2 path so template substitution, edges, and doorway bridges all work, and place the boss from `finalFloor.bossId` with loot from `finalFloor.lobbyChests`.

## Work plan

1. **`RoomGraph` index + `RoomGraphPaths.connected_component`** — `room_graph.gd`, `room_graph_paths.gd`. Pure additions; nothing else changes (RGP-14, part of RGP-06).
2. **Generation reorder + `_connect_fillers` + reservation pass** — `room_graph_generator.gd` only; `min_dead_ends` bump in `room_graph_config.gd`. Fixes RGP-02, RGP-03, RGP-04 and adds the `sealed_room` and required-role validations.
3. **Door-aware validation** — delete `_compute_distances`, populate `graph_distance` from `bfs_distances`, add the component check (RGP-06).
4. **Assigner rng tie-break** — `room_graph_assigner.gd` (RGP-07).
5. **Schema v2 + fixture** — `content/schemas/dungeon-definition.v2.json`, `content/fixtures/dungeon_definition_v2_gdscript.json`, `scripts/validate-content/validate.mjs` version routing, `dungeon_procgen.gd:70` bumps `schemaVersion` to 2 (RGP-01).
6. **Parity suite rewrite** — `cross_stack_parity_suite.gd`, new `affix_suite.gd`, CLI `mix-seed-table` and `room-kit-specs` verbs in `tools/procgen-cli/Program.cs`, two new fixtures (RGP-05).
7. **Remove fallback graph, return failure** — `room_graph_generator.gd:44-49,551-608`, `dungeon_procgen.gd:37-38`. Land after LPG-01 so the caller can handle failure (RGP-10).
8. **Dead-code sweep** — delete `_recompute_connections`, `_pick_random_cell`, `_warn_door_mismatch`, `continue_probability_base`, `continue_decay_rate`; drop `gridStep` from the biome schema or start reading it (RGP-13). Drop `one_way` from the edge enum and the four `dungeon_builder.gd` branches (RGP-12).
9. **Shop and obstacle roles** — the reservation pass from step 2 already assigns them; add `shop` room kits and the merchant content type (coordinated with [`room-content.md`](room-content.md) RMC-05) (RGP-11).
10. **Data-driven final floor** — `dungeon_procgen.gd:112-171`, biome JSON `finalFloor` block (RGP-08).
11. **Height levels** — `room_graph_generator.gd` height stepping behind `RoomGraphConfig.max_height_level`, default 0; flip the default to 2 only after DBL-01 lands (RGP-09).

## Data and schema changes

`content/schemas/dungeon-definition.v2.json` (new) — as described in target design section 3. `schemaVersion` becomes `{"const": 2}`.

`content/schemas/biome-definition.v1.json` — add:

```json
"finalFloor": {
  "type": "object",
  "additionalProperties": false,
  "required": ["bossId"],
  "properties": {
    "bossId": { "type": "string", "minLength": 1 },
    "lobbyChests": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["chestId", "items"],
        "properties": {
          "chestId": { "type": "string", "minLength": 1 },
          "items": { "type": "array", "items": { "type": "object" } }
        }
      }
    }
  }
},
"maxHeightLevel": { "type": "integer", "minimum": 0, "maximum": 2 },
"maxSecrets": { "type": "integer", "minimum": 0, "maximum": 4 }
```

and remove `gridStep` from `required` (`biome-definition.v1.json:8`) since no reader exists, or start reading it as the graph cell pitch. All 10 files under `content/biomes/` need a `finalFloor.bossId` matching their `bossPool`.

New fixtures: `content/fixtures/dungeon_definition_v2_gdscript.json`, `content/fixtures/mix_seed_parity.json`, `content/fixtures/room_kit_specs.json`.

No save-format change: `DungeonBuilder` reads the definition from `RunFlow` / `DungeonBuilder._floor_definition_cache`, and `local_save.gd` stores the seed, not the definition. If a future change persists definitions, `save_migrator.gd` needs the bump at that point, not here.

## Acceptance criteria

- [ ] Every generated definition validates against `dungeon-definition.v2.json` for all 10 biomes across 200 seeds (RGP-01).
- [ ] Every generated non-final floor contains exactly one room with `type == "treasure"` (RGP-02).
- [ ] The `boss`, `stairs`, and `treasure` roles are always three distinct `slot_id`s (RGP-03).
- [ ] No slot in a returned graph has `door_mask == 0` (RGP-04).
- [ ] Every room in `definition.rooms` is reachable from `placements.entrance` by BFS over `edges` of kind `door` or `corridor`, except `type == "secret"` rooms which are reachable over one additional `secret` edge (RGP-04, RGP-06).
- [ ] `cross_stack_parity_suite.gd` contains at least one assertion that reads a C#-produced artifact, and contains no assertion that a schema-illegal key is present (RGP-05).
- [ ] `RoomGraphAssigner.assign(biome, graph, rng_a)` and `assign(biome, graph, rng_b)` with different seeds can produce different `template_id` sets for the same graph (RGP-07).
- [ ] `_generate_final_floor` reads `bossId` from the biome JSON; `glacial_hollow`'s final floor spawns `boss_frost_warlord`, not `final_boss_forgotten_castle` (RGP-08).
- [ ] With `max_height_level = 2`, at least one room per 20 floors has `heightLevel > 0`, and no edge connects rooms more than one level apart (RGP-09).
- [ ] `RoomGraphGenerator.generate()` returns `{ok: false, reason: <string>}` on total failure; `_build_fallback_graph` no longer exists (RGP-10).
- [ ] `SlotType.SHOP` and `SlotType.OBSTACLE` each appear in at least one generated floor out of 50 (RGP-11).
- [ ] No `edges[].kind == "one_way"` is producible, and the v2 schema enum omits it (RGP-12).
- [ ] `grep -r "_recompute_connections\|_pick_random_cell\|_warn_door_mismatch\|continue_probability_base\|continue_decay_rate" apps/game/client/scripts` returns nothing (RGP-13).
- [ ] `RoomGraph.get_slot()` does not iterate `slots` (RGP-14).

## Validation

Extend `apps/game/client/scripts/validation/suites/room_graph_suite.gd`:

- `test_no_sealed_rooms` — 200 seeds x 10 biomes; assert every slot's `connection_count() >= 1`.
- `test_special_roles_distinct` — assert `boss_id != stairs_id != treasure_id` and all three non-empty.
- `test_treasure_always_present` — assert `graph.treasure_id != ""` and the slot's type is `TREASURE`.
- `test_door_reachability` — assert `RoomGraphPaths.connected_component(graph, start_id).size()` equals the non-secret slot count.
- `test_graph_distance_is_door_distance` — for 20 seeds, assert `slot.graph_distance == RoomGraphPaths.bfs_distances(graph, start_id)[slot.slot_id]` for every non-secret slot.
- `test_height_levels_step_by_one` — with `max_height_level = 2`, assert `absi(a.height_level - b.height_level) <= 1` for every door-connected pair.
- `test_no_fallback_needed` — assert `generate()` returns `ok: true` without the (now deleted) fallback for 500 seeds per biome; a single failure fails the test and prints the seed and reason.
- `test_assigner_varies_with_rng` — two different rng seeds over the same graph; assert at least one differing `template_id` across 50 graphs.
- `test_room_bounds_do_not_overlap` — build `rooms`, compute each AABB from `RoomTemplateCatalog.get_spec` rotated by yaw, assert no pair intersects by more than 0.01.

Extend `apps/game/client/scripts/validation/suites/procgen_suite.gd`:

- `test_definition_matches_v2_schema` — structural check of every v2-required key, the `room.type` enum, and the absence of unknown root keys (a GDScript port of the schema's closed-object rules, since Godot has no JSON-Schema validator).
- `test_final_floor_boss_matches_biome` — for all 10 biomes assert `placements.boss.enemyId` is in that biome's `bossPool` or equals its `finalFloor.bossId`.

Rewrite `apps/game/client/scripts/validation/suites/cross_stack_parity_suite.gd` per target design section 4.

CI: `scripts/validate-content/validate.mjs` must fail on `content/fixtures/dungeon_definition_v2_gdscript.json` if the generator drifts; regenerate that fixture in the same commit as any intentional shape change.

Manual: none.

## Related

- [`../existing_codebase/room-graph-procgen.md`](../existing_codebase/room-graph-procgen.md)
- [`local-procgen.md`](local-procgen.md) — LPG-01 failure handling, LPG-05 seed mixing
- [`room-templates.md`](room-templates.md) — RTP-02 substitution and the kit specs
- [`room-content.md`](room-content.md) — RMC-05 merchant/shop rooms
- [`dungeon-builder.md`](dungeon-builder.md) — DBL-01 height transitions, DBL-02 shortcut corridors
- [`biome-registry.md`](biome-registry.md) — biome JSON schema owner
- [`validation-suites.md`](validation-suites.md)
