# Room graph procgen — improvement plan

## Current state

Phase 1 now generates door-mask-aware graphs with a non-overlapping special-room reservation pass, filler connectivity, and door-based validation. Phase 2 emits `dungeon-definition.v2.json` definitions with schema v2, RNG-driven template substitution, shop/obstacle roles, and height levels behind `maxHeightLevel`. Fallback corridor generation is removed; total failure returns `{ok: false, reason}`. See [`../existing_codebase/room-graph-procgen.md`](../existing_codebase/room-graph-procgen.md).

## Gaps

| ID | Sev | Gap | Status | Evidence |
|----|-----|-----|--------|----------|
| RGP-01 | P0 | Emitted definition violates the schema | **FINISHED** | `content/schemas/dungeon-definition.v2.json`, `dungeon_procgen.gd:73` `schemaVersion: 2`, `content/fixtures/dungeon_definition_v2_gdscript.json` validates in `validate.mjs` |
| RGP-02 | P0 | Treasure room is never assigned | **FINISHED** | `_assign_special_rooms` runs after `_apply_door_connections`; `room_graph_suite.gd` `test_treasure_always_present` |
| RGP-03 | P0 | Stairs assignment overwrites another special role | **FINISHED** | Reservation pass `room_graph_generator.gd` `_assign_special_rooms`; `test_special_roles_distinct` |
| RGP-04 | P0 | Bounding-box filler rooms get no doors | **FINISHED** | `_connect_fillers` + sealed-room validation; `test_no_sealed_rooms` |
| RGP-05 | P0 | `cross_stack_parity_suite.gd` asserts no real parity | **FINISHED** | `cross_stack_parity_suite.gd` reads `mix_seed_parity.json` and `room_kit_specs.json`; affix tests moved to `affix_suite.gd` |
| RGP-06 | P1 | Reachability validation uses grid adjacency | **FINISHED** | `RoomGraphPaths.connected_component`, `test_door_reachability`, `test_graph_distance_is_door_distance` |
| RGP-07 | P1 | Assigner ignores `rng` | **FINISHED** | `room_template_catalog.gd` `pick_template_for_doors(..., rng)`; `test_assigner_varies_with_rng` |
| RGP-08 | P1 | Final-floor generator hardcoded | **FINISHED** | `dungeon_procgen.gd` `_generate_final_floor` reads `finalFloor.bossId`; `procgen_suite.gd` `test_final_floor_boss_matches_biome` |
| RGP-09 | P1 | `height_level` never set non-zero | **FINISHED** | `_grow_critical_path` height stepping when `max_height_level > 0`; `test_height_levels_step_by_one` |
| RGP-10 | P1 | Fallback graph on failure | **FINISHED** | `room_graph_generator.gd:44` returns `{ok: false, reason}`; `_build_fallback_graph` deleted; `test_no_fallback_needed` |
| RGP-11 | P2 | `SHOP` / `OBSTACLE` never assigned | **FINISHED** | Reservation pass assigns shop (35%) and obstacle; assigner `SHOP` branch; merchant content in `room_content_assigner.gd` |
| RGP-12 | P2 | `one_way` edges still legal | **FINISHED** | `dungeon-definition.v2.json` edge enum omits `one_way`; `test_shortcut_edge_emission` asserts no `one_way` |
| RGP-13 | P2 | Dead code and unused config | **FINISHED** | Removed `_recompute_connections`, `_pick_random_cell`, `_warn_door_mismatch`, `continue_probability_*`; `gridStep` optional in biome schema |
| RGP-14 | P2 | `get_slot()` O(n) scan | **FINISHED** | `room_graph.gd` `_index` + `add_slot`/`remove_slot`; `test_room_bounds_do_not_overlap` |

## Target design

(Unchanged — implemented as specified in the original plan.)

## Work plan

All steps landed in this change set.

## Data and schema changes

- `content/schemas/dungeon-definition.v2.json` (new)
- `content/schemas/biome-definition.v1.json` — `finalFloor`, `maxSecrets`, `maxHeightLevel`; `gridStep` no longer required
- `content/fixtures/dungeon_definition_v2_gdscript.json`, `mix_seed_parity.json`, `room_kit_specs.json`
- `scripts/validate-content/validate.mjs` routes v2 fixture to v2 schema

## Acceptance criteria

- [x] Every generated definition validates against `dungeon-definition.v2.json` for all 10 biomes across 200 seeds (RGP-01).
- [x] Every generated non-final floor contains exactly one room with `type == "treasure"` (RGP-02).
- [x] The `boss`, `stairs`, and `treasure` roles are always three distinct `slot_id`s (RGP-03).
- [x] No slot in a returned graph has `door_mask == 0` (RGP-04).
- [x] Every room is door-reachable from start except secrets over secret edges (RGP-06).
- [x] `cross_stack_parity_suite.gd` reads C#/fixture artifacts; no illegal-key assertions (RGP-05).
- [x] Assigner varies with different RNG seeds (RGP-07).
- [x] Final-floor `bossId` from biome JSON (RGP-08).
- [x] Height levels step by at most one between door-connected rooms when enabled (RGP-09).
- [x] `generate()` returns `{ok: false, reason}` on total failure (RGP-10).
- [x] `SHOP` and `OBSTACLE` appear in generated floors (RGP-11).
- [x] No `one_way` edges producible (RGP-12).
- [x] Dead-code grep clean under `procgen/` (RGP-13).
- [x] `get_slot()` uses `_index` O(1) lookup (RGP-14).

## Status: FINISHED

## Validation

- `room_graph_suite.gd` — 16/16 tests pass (Godot headless, `--suite=room_graph_suite`)
- `cross_stack_parity_suite.gd` — 3/3 parity tests pass
- `procgen_suite.gd` — v2 schema + final-floor boss tests added
- `validate.mjs` — `dungeon_definition_v2_gdscript.json` OK

## Related

- [`../existing_codebase/room-graph-procgen.md`](../existing_codebase/room-graph-procgen.md)
- [`local-procgen.md`](local-procgen.md)
- [`room-templates.md`](room-templates.md)
- [`room-content.md`](room-content.md)
- [`dungeon-builder.md`](dungeon-builder.md)
- [`biome-registry.md`](biome-registry.md)
- [`validation-suites.md`](validation-suites.md)
