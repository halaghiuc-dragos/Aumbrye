# Procgen placements

The pass that fills a laid-out floor with enemies, chests, traps, cover pillars, the boss, and the secret-room markers. It runs after `RoomGraphAssigner` and before the definition is assembled. Placement positions are a fixed table of hardcoded local offsets, and the loot tables are hardcoded GDScript `match` statements rather than content data.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/procgen/procgen_placements.gd` | Enemies, loot, traps, secrets, cover, boss, exit, entrance |
| `apps/game/client/scripts/dungeon/procgen/procgen_loot_tables.gd` | Per-theme item and trap tables |
| `apps/game/client/scripts/dungeon/procgen/procgen_biome_loader.gd` | One-line biome JSON loader |

## How it works

`DungeonProcgen` calls `ProcgenPlacements.place(biome, assignment, run_seed, tier, player_level, assign_rng, graph)` (`dungeon_procgen.gd:60-62`) with the same `assign_rng` that `RoomGraphAssigner` just used and that `RoomContentAssigner` will use next. `place()` (`procgen_placements.gd:23`) runs three sub-passes and returns a flat dictionary.

Rooms are selected by the `type` field `RoomGraphAssigner` wrote (`room_graph_assigner.gd:75-153`): `filler`, `hub`, `boss`, `treasure`, `corridor`, `obstacle`, `secret`, `combat`.

### Enemies

`_place_enemies()` (`:50`):

- Threat budget = `budgets.baseEnemyThreat` (default 200) + `budgets.threatPerTier` (default 35) x `(tier - 1)` + `player_level` x 5 (`:59-63`).
- Candidate rooms are `type == "combat"` only, sorted by `semantic_id` as a **string** (`:70-72`), so `room_10` sorts before `room_2`.
- Per room, `max_per_room = rng.randi_range(1, mini(3, 1 + int(depth / 3.0)))` where `depth` is `slot.graph_distance` (`:76-81`). Because `graph_distance` is grid-adjacency BFS rather than door-based (see [`room-graph-procgen.md`](room-graph-procgen.md)), the depth scaling understates real walking distance.
- Each slot picks by `_pick_weighted(biome.enemyPool, rng)` (`:282`), retrying up to 4 times to skip reserved boss enemies (`:89-90`), and stops the room when the next enemy would exceed the budget (`:92-93`).
- Position is `SPAWN_OFFSETS[(placements.size() + i) % 6]` (`:94`) from the 6-entry table at `:6-13`. Since `placements.size()` also grows, the index advances by 2 per placement, so a room reliably gets every other entry of the table and the sequence is shared across all rooms.
- `sampleNavmesh: true` on every entry, so `DungeonBuilder` snaps the point to the navmesh at build time.

`:74-75` (`if room.get("type") == "filler": continue`) is dead — `combat_rooms` only holds `combat`. `:104-105` (`if not placed: continue`) is a no-op at the end of the loop body.

`_enemy_threat_cost()` (`:297`) reads `content/enemies/<id>.json` (then `content/bosses/<id>.json`) from disk on every call, with no cache, and defaults to 20 (bosses 50).

### Loot, traps, secrets, boss

`_place_loot()` (`:109`) ignores its `_tier`, `_player_level`, `_rng`, and `_enemies` parameters and instead creates three fresh `RandomNumberGenerator`s seeded from `run_seed`:

| Purpose | Seed | Line |
|---------|------|------|
| side chest room | `run_seed ^ 0x51DE` | `:165-167` |
| falling trap room | `run_seed ^ 0x7A2B` | `:201-203` |
| boss selection | `run_seed ^ 0xB055` | `:210-211` |

Chests placed:

| Chest id | Room | Offset | Items |
|----------|------|--------|-------|
| `treasure_main` | first `treasure` room | `(0,0,0)` | `ProcgenLootTables.treasure_loot` |
| `secret_vault_<n>` | each `secret` room | `(0,0,0)` | `secret_loot` |
| `<room>_side` | random `combat` room | `(7,0,6)` | `side_loot`, or `treasure_loot` at depth >= 4, or `armory_loot` at depth >= 6 (`:174-177`) |
| `<room>_armory` | `combat_rooms[1]` | `(-4,0,4)` | `armory_loot` |

Traps placed:

| Trap | Room | Offset |
|------|------|--------|
| `ProcgenLootTables.corridor_trap(biome)` | first `corridor` room, which is the stairs slot | `(0,0,4)` |
| `falling_trap` | random `combat` room | `(-2,3,-5)` |

Secrets emit `{roomId, mechanism, parentRoomId}` per `secret` room (`:146-150`), resolving `mechanism` and the parent's semantic id from the graph slot.

The boss is picked **uniformly** from `biome.bossPool` (`:213`) — `bossPool` entries have no `weight` field in any biome JSON, so this is consistent with the data, but unlike `enemyPool` it is not weight-aware. `exit` is the boss room's semantic id and `entrance` is the first `hub` room.

If either the boss or hub room is missing, `:216-226` pushes an error and returns `boss: null`, `exit: null`, `entrance: "entrance"`. `DungeonBuilder._setup_boss()` returns early on a null boss placement (`dungeon_builder.gd:534-536`), so the floor ships with no boss rather than failing generation.

### Cover

`_place_cover()` (`:238`) adds `rng.randi_range(2, 3)` entries per `combat` room from the 4-entry `COVER_OFFSETS` table (`:15-20`), each `1.2 x 2.4 x 1.2`, alternating `kind` between `pillar` and `chokepoint`. `DungeonBuilder._place_cover()` (`dungeon_builder.gd:292-308`) forwards each to `CastleBlockout.add_cover_obstacle()` with the biome wall material. The `kind` field is never read.

### Budgets reported

`threat_used` is the summed threat cost. `loot_value` is `_estimate_loot_value()` (`:311`): `quantity x 10` per item, ignoring `ItemCatalog.get_loot_value()` (`item_catalog.gd:30`). Both land in `definition.budgets` (`dungeon_procgen.gd:89-92`).

`budgets.baseLootValue` (80) and `budgets.lootPerTier` (14) exist in every `content/biomes/*.json` and are read by nothing in GDScript — grep for both names finds only the biome files, the schema, the fixtures, and the C# side.

### Loot tables

`ProcgenLootTables` is five `match biome_id` functions plus `corridor_trap`, with theme groups pairing each original biome with its expansion clone:

| Group | Biomes |
|-------|--------|
| crystal | `crystal_caverns`, `prism_depths` |
| swamp | `poison_swamp`, `venom_mire` |
| frost | `frozen_fortress`, `glacial_hollow` |
| shadow | `dark_cathedral`, `umbral_chapel` |
| vault | `iron_vault` |
| default | `forgotten_castle` |

All 10 biomes are covered. Every table is a fixed 1-2 item list with fixed quantities — there is no rarity roll, no tier scaling, and no randomization, so the same biome always yields the same items from the same chest slot regardless of seed, tier, or player level.

`corridor_trap` returns `frost_trap` and `shadow_trap` for the frost and shadow groups, but only three trap scenes exist (`scenes/traps/spike_trap.tscn`, `poison_pool.tscn`, `falling_trap.tscn`). `DungeonBuilder._trap_scene_for_id()` (`dungeon_builder.gd:503-512`) maps `frost_trap` to the poison pool and `shadow_trap` to spikes, so those two ids render as the wrong hazard.

### Biome loading

`ProcgenBiomeLoader.load(biome_id)` (`procgen_biome_loader.gd:5`) is a single `ContentLoader.load_json("content/biomes/<id>.json")` call. No schema validation, no cache, and a missing file yields `{}`, which `DungeonProcgen` turns into `{"ok": false, "error": "Unknown biome"}` (`dungeon_procgen.gd:29-31`). The static method name shadows the GDScript global `load()` inside this class.

## Contracts

- `placements.enemies[]`: `{roomId, enemyId, offset: {x,y,z}, sampleNavmesh}` — read by `dungeon_builder.gd:440`.
- `placements.loot[]`: `{roomId, chestId, offset: {x,y,z}, items: [{itemId, quantity}]}` — read by `dungeon_builder.gd:485-500`, forwarded whole into `LootChest.configure()`.
- `placements.traps[]`: `{roomId, trapId, offset, sampleNavmesh}` — read by `dungeon_builder.gd:520-530`.
- `placements.secrets[]`: `{roomId, mechanism, parentRoomId}` — read by `dungeon_builder.gd:311-341`. An entry with an empty `parentRoomId` is skipped, which is why `content/fixtures/forgotten_castle_slice.json` produces no secret mechanism.
- `placements.cover[]`: `{roomId, offset, size, kind}` — read by `dungeon_builder.gd:292-308`. Not declared in `content/schemas/dungeon-definition.v1.json`, and absent from the C# `DungeonPlacements` record.
- `placements.boss`: `{roomId, enemyId}` or `null`.
- `placements.exit`, `placements.entrance`: semantic room ids.
- `placements.puzzles`: always `[]` (`:38`).
- Biome inputs consumed: `id`, `budgets.baseEnemyThreat`, `budgets.threatPerTier`, `enemyPool[].enemyId`, `enemyPool[].weight`, `bossPool[].enemyId`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Enemy budget and weighted pool | IMPLEMENTED | `procgen_placements.gd:59-63,282-294` |
| Secret markers | IMPLEMENTED | `procgen_placements.gd:132-156` |
| Cover pillars | IMPLEMENTED | `procgen_placements.gd:238-252`, `dungeon_builder.gd:292` |
| Spawn positions | PLACEHOLDER | 6 hardcoded offsets reaching `x = ±5`, `z = ±4` (`:6-13`), applied to rooms as narrow as 8 units |
| Cover positions | PLACEHOLDER | 4 hardcoded offsets (`:15-20`) |
| Chest positions | PLACEHOLDER | `(7,0,6)` and `(-4,0,4)` (`:181,189`) — outside the walls of the 8-wide and 10-wide kinds |
| Loot tables | PLACEHOLDER | fixed 1-2 item lists in GDScript, no rarity, no tier scaling (`procgen_loot_tables.gd:7-68`) |
| `treasure_main` chest | ABSENT in practice | requires a `treasure` room, and `graph.treasure_id` is always empty on the primary path (see [`room-graph-procgen.md`](room-graph-procgen.md)) |
| `placements.puzzles` | ABSENT | hardcoded `[]` (`:38`) |
| `budgets.baseLootValue`, `budgets.lootPerTier` | STUB | present in all 10 biome files, read nowhere in GDScript |
| `loot_value` reporting | PARTIAL | `quantity x 10` heuristic ignores `ItemCatalog.get_loot_value` (`:311-316`, `item_catalog.gd:30`) |
| `cover` in the schema | ABSENT | not in `content/schemas/dungeon-definition.v1.json`, which sets `additionalProperties: false` on `placements` |
| `frost_trap`, `shadow_trap` scenes | ABSENT | only 3 trap scenes exist; builder substitutes (`dungeon_builder.gd:503-512`) |
| Missing boss/hub handling | PARTIAL | pushes an error and returns a null boss, floor still builds (`:216-226`, `dungeon_builder.gd:534`) |
| Threat cost lookup | PARTIAL | uncached disk read per candidate pick (`:297-308`) |
| Boss pool weighting | PARTIAL | uniform pick, ignores any `weight` (`:213`) |
| Room ordering | PARTIAL | `combat_rooms` sorted as strings, so `room_10 < room_2` (`:70-72`) |
| Biome JSON validation on load | ABSENT | `procgen_biome_loader.gd:5` has no schema check |
| Enemy count scaling by tier | ABSENT | only the threat budget scales; `max_per_room` depends on depth alone (`:81`) |

## Related

- Improvement plan: [`../actual_improvements/procgen-placements.md`](../actual_improvements/procgen-placements.md)
- [`room-graph-procgen.md`](room-graph-procgen.md) — the assignment this pass consumes
- [`room-content.md`](room-content.md) — the parallel content-tagging pass
- [`dungeon-builder.md`](dungeon-builder.md) — consumes every placement array
- [`biome-registry.md`](biome-registry.md) — biome JSON and schema
- [`dungeon-traps.md`](dungeon-traps.md) — the three trap scenes
- [`loot-and-equipment.md`](loot-and-equipment.md) — `LootChest`, `ItemCatalog`
- [`enemies.md`](enemies.md) — `threat_cost` on enemy JSON
- [`bosses.md`](bosses.md) — boss pool
