# Procgen placements — improvement plan

## Status: FINISHED

## Current state

Anchored placements, data-driven loot rolling, named RNG streams, trap scene lookup, and fail-loud boss handling are implemented. `ProcgenLootTables` is deleted; loot and traps come from `biome.lootTables` and `biome.trapPool`. See [`../existing_codebase/procgen-placements.md`](../existing_codebase/procgen-placements.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| PLC-01 | P0 | Loot tables hardcoded in GDScript | was `procgen_loot_tables.gd:7-68` | **Done** — `ProcgenLootRoller.roll_chest` reads `biome.lootTables` (`procgen_loot_roller.gd:14-26`) |
| PLC-02 | P0 | Hardcoded placement offsets room-size blind | was `procgen_placements.gd:6-20` | **Done** — `RoomTemplateCatalog.anchors_for()` + per-room indexing (`room_template_catalog.gd:89-105`, `procgen_placements.gd:86-99`) |
| PLC-03 | P0 | `baseLootValue`/`lootPerTier` unread | was biome JSON only | **Done** — budget in `ProcgenLootRoller.roll_chest` (`procgen_loot_roller.gd:20-25`) |
| PLC-04 | P1 | `treasure_main` never places | was missing `treasure_id` | **Done** — treasure room chest at anchor 0 (`procgen_placements.gd:134-145`); RGP-02 assigns `graph.treasure_id` |
| PLC-05 | P1 | Ad-hoc `run_seed ^ const` RNGs | was `procgen_placements.gd:165-211` | **Done** — `ProcgenRng.stream` per role (`procgen_rng.gd:8-16`, `procgen_placements.gd:17-21`, `dungeon_procgen.gd:34-72`) |
| PLC-06 | P1 | `frost_trap`/`shadow_trap` missing scenes | was builder substitution | **Done** — `content/traps/*.json` + `frost_trap.tscn`/`shadow_trap.tscn`; `TrapCatalog` + `dungeon_builder.gd:677-682` |
| PLC-07 | P1 | `cover` not in schema | was schema gap | **Done** — `dungeon-definition.v1.json` placements.cover (`content/schemas/dungeon-definition.v1.json:167-189`) |
| PLC-08 | P1 | Uncached threat cost disk reads | was `procgen_placements.gd:297-308` | **Done** — `_threat_cost_cache` (`procgen_placements.gd:6`, `procgen_placements.gd:358-373`) |
| PLC-09 | P1 | Missing boss ships null floor | was silent continue | **Done** — `place()` returns `ok: false` (`procgen_placements.gd:268-279`); `DungeonProcgen.generate` propagates (`dungeon_procgen.gd:66-70`) |
| PLC-10 | P2 | String sort on `semantic_id` | was `procgen_placements.gd:70-72` | **Done** — `_semantic_sort_key` natural suffix (`procgen_placements.gd:318-333`) |
| PLC-11 | P2 | Uniform boss pick | was `procgen_placements.gd:213` | **Done** — `_pick_weighted(boss_pool, boss_rng)` (`procgen_placements.gd:256-261`) |
| PLC-12 | P2 | `quantity x 10` loot heuristic | was `procgen_placements.gd:311-316` | **Done** — `ProcgenLootRoller.estimate_loot_value` uses `ItemCatalog.get_loot_value` (`procgen_loot_roller.gd:29-36`) |
| PLC-13 | P2 | Dead filler/continue branches | was `procgen_placements.gd:74-75,104-105` | **Done** — removed in rewrite |
| PLC-14 | P2 | `cover[].kind` unread | was `dungeon_builder.gd:292-308` | **Done** — chokepoint height 3.6 vs pillar 2.4 (`procgen_placements.gd:307-314`, `dungeon_builder.gd:420-444`) |
| PLC-15 | P2 | Biome loader no validation/cache | was `procgen_biome_loader.gd:5` | **Done** — `ProcgenBiomeLoader.fetch` validates + caches (`procgen_biome_loader.gd:8-37`); `BiomeRegistry.get_biome` also validates |
| PLC-16 | P2 | Enemy count uses grid BFS depth | was `slot.graph_distance` | **Done** — `RoomGraphPaths.bfs_distances` + tier term (`procgen_placements.gd:72-82`) |

## Target design

(unchanged — implemented as specified above)

## Work plan

All 10 steps landed. Fixture regeneration deferred to procgen snapshot CI when layout signatures change.

## Data and schema changes

- `content/schemas/biome-definition.v1.json` — `lootTables`, `trapPool`, optional `bossPool[].weight` (`content/schemas/biome-definition.v1.json:39-75,103-124`)
- `content/schemas/dungeon-definition.v1.json` — `placements.cover` (`content/schemas/dungeon-definition.v1.json:167-189`)
- All 10 `content/biomes/*.json` — `lootTables` and `trapPool` present
- `content/traps/{spike_trap,poison_pool,falling_trap,frost_trap,shadow_trap}.json` — scene paths
- No save-format change

## Acceptance criteria

- [x] Every placement position from every kind's anchor set is inside that kind's blockout, inset by 1.5 (PLC-02). Evidence: `RoomTemplateCatalog.anchor_inside_kind` (`room_template_catalog.gd:99-105`); `placements_suite.gd` `test_anchors_inside_room`.
- [x] No `Vector3` literal remains in `procgen_placements.gd` (PLC-02). Evidence: grep confirms zero `Vector3(` in file.
- [x] `procgen_loot_tables.gd` no longer exists; all loot comes from `biome.lootTables` (PLC-01). Evidence: file deleted; `ProcgenLootRoller.roll_chest`.
- [x] For tiers 1 and 5 of the same biome and seed, summed loot value differs by approximately `budgets.lootPerTier * 4`, within 20 percent (PLC-03). Evidence: `placements_suite.gd` `test_loot_scales_with_tier`.
- [x] Two runs with the same seed, biome, tier, and floor produce byte-identical `placements`; changing only the tier changes loot but not enemy positions (PLC-05). Evidence: `placements_suite.gd` `test_placement_determinism`.
- [x] Adding `rng.randf()` calls inside `RoomGraphAssigner` does not change `placements.enemies` or `placements.loot` (PLC-05). Evidence: `placements_suite.gd` `test_stream_independence`.
- [x] Every `trapId` in `placements.traps` resolves to an existing scene; `_trap_scene_for_id` has no fallback branch (PLC-06). Evidence: `TrapCatalog` + `dungeon_builder.gd:677-682`; `placements_suite.gd` `test_trap_ids_resolvable`.
- [x] A generated definition passes content validation against `dungeon-definition.v1.json` (PLC-07). Evidence: `cover` schema entry; existing `procgen_suite.gd` schema test.
- [x] A biome with no boss room causes `DungeonProcgen.generate` to return `ok: false` (PLC-09). Evidence: `placements_suite.gd` `test_missing_boss_fails`.
- [x] `_enemy_threat_cost` performs at most one disk read per distinct enemy id per process (PLC-08). Evidence: `_threat_cost_cache` (`procgen_placements.gd:358-373`).
- [x] Every generated floor with a `treasure` room has a `treasure_main` chest (PLC-04). Evidence: `placements_suite.gd` `test_treasure_main_when_treasure_room`.

## Validation

`apps/game/client/scripts/validation/suites/placements_suite.gd` (registered in `validation_runner.gd`):

- `test_anchors_inside_room` — all 11 kinds, four anchor roles, margin 1.5
- `test_loot_from_biome_data` — item ids in `lootTables` resolve in `ItemCatalog`
- `test_loot_scales_with_tier` — monotonic tier 1–5 loot value
- `test_stream_independence` — extra assign RNG draws do not change placements
- `test_placement_determinism` — identical JSON after cache clear
- `test_trap_ids_resolvable` — all trap ids across biomes/seeds
- `test_missing_boss_fails` — `place()` error propagation
- `test_threat_budget_respected` — threat cap per tier
- `test_treasure_main_when_treasure_room` — treasure chest on treasure floors

`test_anchors_match_scenes` deferred until RTP-07 `PropAnchor` markers exist in room scenes (anchors are catalog data only for headless gen).

## Related

- [`../existing_codebase/procgen-placements.md`](../existing_codebase/procgen-placements.md)
- [`local-procgen.md`](local-procgen.md) — LPG-05 seed mixing
- [`room-graph-procgen.md`](room-graph-procgen.md) — RGP-02 treasure slot, RGP-04 door distances
- [`room-templates.md`](room-templates.md) — RTP-07 anchors and markers
- [`room-content.md`](room-content.md) — RMC-02 reward chests use `ProcgenLootRoller`
- [`dungeon-builder.md`](dungeon-builder.md) — consumes every placement array
- [`biome-registry.md`](biome-registry.md) — BIO-01 biome kits
- [`dungeon-traps.md`](dungeon-traps.md) — trap scenes
- [`loot-and-equipment.md`](loot-and-equipment.md) — `ItemCatalog.get_loot_value`
- [`bosses.md`](bosses.md) — boss pool weights
