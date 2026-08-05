# Procgen placements — improvement plan

## Current state

Enemy budgeting works. Everything about *where* things go and *what* is in them is a hardcoded constant: 6 spawn offsets, 4 cover offsets, two magic chest offsets, and five `match biome_id` functions returning fixed 1-2 item lists with no rarity roll and no tier scaling. Several offsets land outside the walls of the narrower room kinds, the treasure chest never places because the graph never assigns a treasure slot, and `budgets.baseLootValue` / `lootPerTier` exist in all 10 biome files and are read by nothing. See [`../existing_codebase/procgen-placements.md`](../existing_codebase/procgen-placements.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PLC-01 | P0 | Loot tables are hardcoded per-biome GDScript with fixed items and quantities — no rarity, no tier scaling, no seed variation, so every run of a biome yields identical loot | `procgen_loot_tables.gd:7-68` |
| PLC-02 | P0 | Placement offsets are hardcoded and room-size blind: `(7,0,6)` and `x = ±5` land outside the walls of the 8-wide `stairs`/`corridor` and 10-wide `treasure` kinds | `procgen_placements.gd:6-20,181,189` vs `room_template_catalog.gd:8-9,16` |
| PLC-03 | P0 | `budgets.baseLootValue` and `budgets.lootPerTier` are authored in all 10 biomes and read nowhere, so loot does not scale with tier at all | `content/biomes/forgotten_castle.json:33,35`; no GDScript reader |
| PLC-04 | P1 | `treasure_main` never places because `graph.treasure_id` is never assigned, so the dedicated treasure room reward is dead | `procgen_placements.gd:124-131`, `room_graph_generator.gd` special-room ordering |
| PLC-05 | P1 | Three fresh RNGs seeded from `run_seed ^ <const>` bypass the passed-in stream, so side chest, falling trap, and boss choice are all independent of tier, floor, and every earlier draw | `procgen_placements.gd:165-167,201-203,210-211` |
| PLC-06 | P1 | `frost_trap` and `shadow_trap` have no scene; the builder silently substitutes a poison pool and spikes | `procgen_loot_tables.gd:76,78`, `dungeon_builder.gd:507-510`, only 3 files in `scenes/traps/` |
| PLC-07 | P1 | `placements.cover` is produced but is not in the schema, and `additionalProperties: false` on `placements` means any generated definition fails content validation | `procgen_placements.gd:41`, `content/schemas/dungeon-definition.v1.json` |
| PLC-08 | P1 | `_enemy_threat_cost` does an uncached `FileAccess` + JSON parse per candidate pick, up to 4 per enemy slot | `procgen_placements.gd:297-308` |
| PLC-09 | P1 | A missing boss or hub room downgrades to a null boss placement and the floor still builds, so a broken floor is shippable | `procgen_placements.gd:216-226`, `dungeon_builder.gd:534-536` |
| PLC-10 | P2 | `combat_rooms` is sorted by `semantic_id` as a string, so `room_10` precedes `room_2` and the `combat_rooms[1]` armory pick is effectively arbitrary | `procgen_placements.gd:70-72,184-185` |
| PLC-11 | P2 | Boss is picked uniformly, ignoring any pool weighting | `procgen_placements.gd:213` |
| PLC-12 | P2 | `loot_value` is a `quantity x 10` heuristic while `ItemCatalog.get_loot_value` exists | `procgen_placements.gd:311-316`, `item_catalog.gd:30` |
| PLC-13 | P2 | Dead code: the `filler` skip inside `combat_rooms`, and the trailing `if not placed: continue` | `procgen_placements.gd:74-75,104-105` |
| PLC-14 | P2 | `cover[].kind` is emitted and never read | `procgen_placements.gd:250`, `dungeon_builder.gd:292-308` |
| PLC-15 | P2 | `ProcgenBiomeLoader` performs no schema validation and no caching, and its static `load` shadows the GDScript global | `procgen_biome_loader.gd:5` |
| PLC-16 | P2 | Enemy count per room scales only with `graph_distance`, which is grid-adjacency BFS rather than real walking distance | `procgen_placements.gd:76-81` |

## Target design

Two structural changes carry most of the value: placement positions come from authored anchors in the room scenes, and loot comes from data-driven biome loot tables with a real rarity roll.

### 1. Anchored placement (PLC-02, PLC-14, PLC-16)

Generation runs headless and must not instantiate scenes, so anchors have to be declared as data. Extend `RoomTemplateCatalog.KIND_SPECS` with an `anchors` block per kind, authored to match the `Props/PropAnchor_<n>` markers in the scenes (see [`room-templates.md`](room-templates.md) RTP-07):

```gdscript
"courtyard": {
    "width": 20.0, "depth": 20.0, "doors": ...,
    "anchors": {
        "enemy": [Vector3(6,0,4), Vector3(-6,0,-5), Vector3(0,0,0), Vector3(7,0,-4), Vector3(-5,0,6), Vector3(4,0,-3)],
        "cover": [Vector3(-4,0,-3), Vector3(4,0,3), Vector3(0,0,-6), Vector3(-3,0,5)],
        "chest": [Vector3(8,0,7), Vector3(-8,0,7)],
        "trap":  [Vector3(0,0,5)],
    },
},
```

Every anchor is inside the walls with at least a 1.5 unit margin for its kind, so a `stairs` room's anchors never exceed `x = ±2.5`, `z = ±6.5`. A `@tool` check in `CastleBlockout` warns when a `PropAnchor` marker in the scene disagrees with the catalog entry, and the validation suite asserts both directions.

Placement then reads `RoomTemplateCatalog.anchors_for(template_id, "enemy")` and indexes per room (`anchor[i % anchors.size()]`) rather than sharing one global counter, so a room's spawns are stable regardless of what happened in other rooms.

Enemy count per room switches to `RoomGraphPaths.bfs_distances(graph)` (door-based) once [`room-graph-procgen.md`](room-graph-procgen.md) RGP-04 lands, and the formula becomes `clampi(1 + int(door_distance / 3.0) + int((tier - 1) / 2), 1, 4)` so tier raises density as well as budget.

`cover[].kind` becomes meaningful: `pillar` uses the biome wall material and full height, `chokepoint` uses a `1.2 x 1.2 x 3.6` slab rotated to face the nearest doorway. `DungeonBuilder._place_cover` branches on it.

### 2. Data-driven loot tables (PLC-01, PLC-03, PLC-12)

Delete `procgen_loot_tables.gd` and move the tables into the biome kit as `content/biomes/<id>.json`:

```json
"lootTables": {
  "treasure": [
    { "itemId": "health_potion", "quantity": [1, 3], "weight": 6 },
    { "itemId": "bloodlust_charm", "quantity": [1, 1], "weight": 3, "minTier": 1 },
    { "itemId": "knight_relic", "quantity": [1, 1], "weight": 1, "minTier": 3 }
  ],
  "secret":  [ ... ],
  "side":    [ ... ],
  "armory":  [ ... ]
},
"trapPool": [
  { "trapId": "spike_trap", "weight": 3 },
  { "trapId": "falling_trap", "weight": 1 }
]
```

Chest contents are rolled by a new `ProcgenLootRoller`:

1. Loot budget = `budgets.baseLootValue + budgets.lootPerTier * (tier - 1)` (PLC-03).
2. Each chest gets a share of the budget by role: `treasure` 0.35, `secret` 0.25, `armory` 0.25, `side` 0.15.
3. Within a chest, repeatedly weight-pick from the table (excluding entries whose `minTier` exceeds the current tier), roll `quantity` in its range, and subtract `ItemCatalog.get_loot_value(itemId) * quantity` from the share. Stop when the share is exhausted or after 4 items. Guarantee at least one item.
4. All draws use a single named RNG stream (below), so the same seed and tier yield the same chest.

`_estimate_loot_value` then reports the real summed `ItemCatalog.get_loot_value` (PLC-12), which makes `definition.budgets.lootValue` assertable against the biome budget.

Rejected alternative: reusing `AffixRoller` / `GlobalDropService` directly. Those roll at pickup time, which would make chest contents non-deterministic from the definition and break the snapshot round-trip in `dungeon_suite.gd`. Loot must be resolved at generation time.

### 3. Named deterministic RNG streams (PLC-05)

Sharing one `assign_rng` across the assigner, placements, and the content assigner means adding a draw anywhere shifts everything downstream. Replace it with derived streams:

```gdscript
static func stream(run_seed: int, name: String) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    rng.seed = _hash64(run_seed, name)   # not run_seed ^ constant
    return rng
```

Streams: `"graph"`, `"assign"`, `"enemies"`, `"loot"`, `"traps"`, `"cover"`, `"boss"`, `"content"`. `_hash64` mixes the seed and the name with the same 64-bit mixer used for floor seeds in [`local-procgen.md`](local-procgen.md) LPG-05, so streams are independent and adding a draw in one does not perturb another. The three ad-hoc `run_seed ^ 0x51DE`-style RNGs are deleted.

The `boss` stream additionally mixes `tier` and `floor_index`, so consecutive floors of the same run do not repeat the same boss.

### 4. Trap scenes and pools (PLC-06)

Author `scenes/traps/frost_trap.tscn` and `scenes/traps/shadow_trap.tscn` (owned by [`dungeon-traps.md`](dungeon-traps.md); this plan only requires that `_trap_scene_for_id` stops substituting). `DungeonBuilder._trap_scene_for_id` becomes a data lookup against a `content/traps/<id>.json` `scene` field, and an unknown id is a `push_error` rather than a silent spike trap. Trap selection moves to `biome.trapPool` weighted picks instead of the fixed `corridor_trap` + `falling_trap` pair, with count `clampi(1 + int(tier / 2), 1, 4)` and rooms chosen off the critical path.

### 5. Fail loudly (PLC-09, PLC-15)

- A missing boss or hub room returns `{"ok": false, "error": ...}` up through `DungeonProcgen` so the retry loop or the caller handles it. No floor without a boss ever reaches `DungeonBuilder`.
- `ProcgenBiomeLoader` validates the loaded dictionary against `content/schemas/biome-definition.v1.json` (see [`biome-registry.md`](biome-registry.md) BIO-02), caches per biome id, and is renamed `fetch()` so it no longer shadows the global `load()`.

### 6. Correctness cleanup (PLC-07, PLC-08, PLC-10, PLC-11, PLC-13)

- `cover` is declared in `content/schemas/dungeon-definition.v1.json` (PLC-07).
- `_enemy_threat_cost` reads from a static `Dictionary` cache keyed by enemy id, populated once per process (PLC-08).
- Room ordering uses a natural sort that compares the numeric suffix of `semantic_id`, and the armory room is picked from the `loot` stream rather than a fixed index (PLC-10).
- Boss selection uses `_pick_weighted` so `bossPool` entries can carry a `weight` (PLC-11).
- Delete the two dead branches (PLC-13).

## Work plan

1. **Named RNG streams** — `ProcgenRng` helper, thread it through `DungeonProcgen`, `RoomGraphAssigner`, `ProcgenPlacements`, `RoomContentAssigner`. Expect every layout snapshot to change once; regenerate `content/fixtures/` afterward (PLC-05).
2. **Anchors in `KIND_SPECS`** — add the `anchors` block for all 10 kinds, `anchors_for()` accessor, `@tool` cross-check (PLC-02, part 1).
3. **Placement reads anchors** — replace `SPAWN_OFFSETS`/`COVER_OFFSETS` and the magic chest offsets; per-room anchor indexing (PLC-02, part 2).
4. **Schema: `cover`, `lootTables`, `trapPool`** — `dungeon-definition.v1.json` and `biome-definition.v1.json` (PLC-07 and the prerequisite for step 5).
5. **Loot tables to data** — author `lootTables` in all 10 biome files, write `ProcgenLootRoller`, delete `procgen_loot_tables.gd`, use `baseLootValue`/`lootPerTier` (PLC-01, PLC-03, PLC-12).
6. **Trap pools** — `biome.trapPool`, off-path trap rooms, `content/traps/<id>.json` scene lookup, error on unknown id (PLC-06).
7. **Fail loudly** — boss/hub error propagation; validated and cached biome loader (PLC-09, PLC-15).
8. **Cleanup** — threat cost cache, natural sort, weighted boss, `cover[].kind` behavior, dead-code removal (PLC-08, PLC-10, PLC-11, PLC-13, PLC-14).
9. **Treasure room** — depends on [`room-graph-procgen.md`](room-graph-procgen.md) RGP-02; once `treasure_id` is assigned, assert `treasure_main` places on every floor that has a treasure slot (PLC-04).
10. **Depth-based density** — depends on RGP-04 door-based distances (PLC-16).

## Data and schema changes

- `content/schemas/biome-definition.v1.json`
  - `lootTables`: object with required keys `treasure`, `secret`, `side`, `armory`, each an array of `{itemId: string, quantity: [integer, integer], weight: integer >= 1, minTier?: integer >= 1}`.
  - `trapPool`: array of `{trapId: string, weight: integer >= 1}`.
  - `bossPool[]` gains an optional `weight: integer >= 1` (default 1).
- `content/schemas/dungeon-definition.v1.json`
  - `placements.cover`: array of `{roomId, offset: {x,y,z}, size: {x,y,z}, kind: "pillar" | "chokepoint"}`.
- All 10 `content/biomes/*.json` gain `lootTables` and `trapPool`, transcribing the current `procgen_loot_tables.gd` values as the starting point so the change is behavior-preserving before tuning.
- `content/fixtures/forgotten_castle_slice.json` and `dungeon_definition_v1_minimal.json` regenerate from the new generator output so they stay loadable (they currently reference template ids that no longer exist — see [`dungeon-builder.md`](dungeon-builder.md)).
- No save-format change: placements live only inside the in-memory definition and the floor cache.

## Acceptance criteria

- [ ] Every placement position from every kind's anchor set is inside that kind's blockout, inset by 1.5 (PLC-02).
- [ ] No `Vector3` literal remains in `procgen_placements.gd` (PLC-02).
- [ ] `procgen_loot_tables.gd` no longer exists; all loot comes from `biome.lootTables` (PLC-01).
- [ ] For tiers 1 and 5 of the same biome and seed, the summed `ItemCatalog.get_loot_value` of all chests differs by approximately `budgets.lootPerTier * 4`, within 20 percent (PLC-03).
- [ ] Two runs with the same seed, biome, tier, and floor produce byte-identical `placements`; changing only the tier changes loot but not enemy positions (PLC-05).
- [ ] Adding a `rng.randf()` call inside `RoomGraphAssigner` does not change any `placements` array (PLC-05, stream independence).
- [ ] Every `trapId` in `placements.traps` resolves to an existing scene; `_trap_scene_for_id` has no fallback branch (PLC-06).
- [ ] A generated definition passes `node scripts/validate-content/validate.mjs` against `dungeon-definition.v1.json` (PLC-07).
- [ ] A biome with no boss room causes `DungeonProcgen.generate` to return `ok: false`; no built floor has a null boss (PLC-09).
- [ ] `_enemy_threat_cost` performs at most one `FileAccess.file_exists` call per distinct enemy id per process (PLC-08).
- [ ] Every generated floor with a `treasure` room has a `treasure_main` chest (PLC-04).

## Validation

New suite `apps/game/client/scripts/validation/suites/placements_suite.gd`:

- `test_anchors_inside_room` — for all 10 kinds and all four anchor roles, assert every anchor is within the kind's half-extents minus 1.5.
- `test_anchors_match_scenes` — instantiate each of the 100 room scenes and assert its `Props/PropAnchor_<n>` positions equal the catalog anchors.
- `test_loot_from_biome_data` — for all 10 biomes, assert every chest item id appears in that biome's `lootTables` and resolves in `ItemCatalog`.
- `test_loot_scales_with_tier` — tiers 1 through 5, same seed; assert summed loot value is monotonically non-decreasing and matches `baseLootValue + lootPerTier * (tier - 1)` within 20 percent.
- `test_stream_independence` — generate with a patched `RoomGraphAssigner` that burns 7 extra `randf()` calls; assert `placements.enemies` and `placements.loot` are unchanged.
- `test_placement_determinism` — same seed twice, in-process and after a `ProcgenRng` cache clear; assert `JSON.stringify(placements)` is identical.
- `test_boss_variety` — 200 seeds against `forgotten_castle`; assert both `bossPool` entries appear, and that consecutive floors of one run do not always repeat the same boss.
- `test_trap_ids_resolvable` — every `trapId` across 200 seeds x 10 biomes resolves through the `content/traps/` lookup.
- `test_missing_boss_fails` — hand-build an assignment with no `boss` room; assert `place()` returns an error and `DungeonProcgen.generate` returns `ok: false`.
- `test_threat_budget_respected` — assert `budgets.enemyThreat <= baseEnemyThreat + threatPerTier * (tier - 1) + player_level * 5` for 200 seeds.

Extend `apps/game/client/scripts/validation/suites/dungeon_suite.gd`:

- `test_placed_nodes_inside_rooms` — build a floor per biome; assert every spawned enemy, chest, trap, and cover body's global position is inside its room's blockout AABB inset by 1.0.
- `test_cover_kind_geometry` — assert `chokepoint` cover bodies are taller than `pillar` ones.

## Related

- [`../existing_codebase/procgen-placements.md`](../existing_codebase/procgen-placements.md)
- [`local-procgen.md`](local-procgen.md) — LPG-05 seed mixing, the hash used by the RNG streams
- [`room-graph-procgen.md`](room-graph-procgen.md) — RGP-02 treasure slot, RGP-04 door distances, RGP-05 schema
- [`room-templates.md`](room-templates.md) — RTP-07 anchors and markers
- [`room-content.md`](room-content.md) — RMC-02 reward chests reuse the loot roller
- [`dungeon-builder.md`](dungeon-builder.md) — consumes every placement array
- [`biome-registry.md`](biome-registry.md) — BIO-01 biome kits, BIO-02 schema validation
- [`dungeon-traps.md`](dungeon-traps.md) — the missing frost and shadow trap scenes
- [`loot-and-equipment.md`](loot-and-equipment.md) — `ItemCatalog.get_loot_value`
- [`bosses.md`](bosses.md) — boss pools and weights
