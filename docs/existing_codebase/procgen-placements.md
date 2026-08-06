# Procgen placements

The pass that fills a laid-out floor with enemies, chests, traps, cover pillars, the boss, and secret-room markers. It runs after `RoomGraphAssigner` and before `RoomContentAssigner`. Placement positions come from `RoomTemplateCatalog.KIND_SPECS` anchor data; loot is rolled from `biome.lootTables` via `ProcgenLootRoller`.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/procgen/procgen_placements.gd` | Enemies, loot, traps, secrets, cover, boss, exit, entrance |
| `apps/game/client/scripts/dungeon/procgen/procgen_loot_roller.gd` | Tier-budgeted chest loot rolls from biome data |
| `apps/game/client/scripts/dungeon/procgen/procgen_rng.gd` | Named deterministic RNG streams |
| `apps/game/client/scripts/dungeon/procgen/procgen_biome_loader.gd` | Validated, cached biome JSON `fetch()` |
| `apps/game/client/scripts/dungeon/procgen/room_template_catalog.gd` | Per-kind anchor positions (`anchors_for`, `anchor_inside_kind`) |
| `apps/game/client/scripts/content/trap_catalog.gd` | Trap id â†’ scene path via `content/traps/<id>.json` |
| `content/traps/*.json` | Trap scene paths for builder resolution |

## How it works

`DungeonProcgen.generate` calls `ProcgenPlacements.place(biome, assignment, run_seed, tier, player_level, floor_index, graph)` (`dungeon_procgen.gd:63-65`) after geometry build. Named streams isolate draws: `graph`, `assign`, `enemies`, `loot`, `traps`, `cover`, `boss`, `content` (`procgen_rng.gd:8-16`, `dungeon_procgen.gd:34-72`).

`place()` (`procgen_placements.gd:9`) returns `ok: false` when boss or hub room is missing (`procgen_placements.gd:268-279`); `DungeonProcgen` propagates the error (`dungeon_procgen.gd:66-70`).

### Enemies

`_place_enemies()` (`procgen_placements.gd:55`):

- Threat budget = `budgets.baseEnemyThreat` + `budgets.threatPerTier` Ã— `(tier - 1)` + `player_level` Ã— 5 (`:64-68`).
- Combat rooms sorted by numeric suffix of `semantic_id` (`:318-333`).
- Per room, `max_per_room = clampi(1 + int(door_distance / 3) + int((tier - 1) / 2), 1, 4)` using `RoomGraphPaths.bfs_distances` (`:72-82`).
- Position from `RoomTemplateCatalog.anchors_for(template_id, "enemy")[i % n]` per room (`:86-99`).
- `_enemy_threat_cost` cached in `_threat_cost_cache` (`:358-373`).

### Loot, traps, secrets, boss

`_place_loot()` (`procgen_placements.gd:117`):

- Chest contents from `ProcgenLootRoller.roll_chest(biome, role, tier, loot_rng)` with budget `baseLootValue + lootPerTier Ã— (tier - 1)` (`procgen_loot_roller.gd:20-25`).
- Roles: `treasure_main` (treasure room), `secret_vault_<n>` (secret rooms), `<room>_side` (random combat, depth-scaled role), `<room>_armory` (loot-stream random combat room).
- Chest offsets from `anchors_for(..., "chest")`; trap offsets from `"trap"` anchors.
- Trap ids from weighted `biome.trapPool`; count `clampi(1 + int(tier / 2), 1, 4)` on off-critical-path combat rooms plus one corridor/stairs trap (`:228-265`).
- Boss from weighted `bossPool` via `ProcgenRng.stream_with_mix(run_seed, "boss", tier, floor)` (`:256-261`).

### Cover

`_place_cover()` (`procgen_placements.gd:295`) places 2â€“3 cover bodies per combat room from `"cover"` anchors. `kind` alternates `pillar` (height 2.4) and `chokepoint` (height 3.6). `DungeonBuilder._place_cover` reads `size.y` from placement (`dungeon_builder.gd:420-444`).

### Budgets reported

`threat_used` summed from cached threat costs. `loot_value` from `ProcgenLootRoller.estimate_loot_value` using `ItemCatalog.get_loot_value` (`procgen_loot_roller.gd:29-36`).

## Contracts

- `placements.enemies[]`: `{roomId, enemyId, offset, sampleNavmesh}` â€” `dungeon_builder.gd`
- `placements.loot[]`: `{roomId, chestId, offset, items: [{itemId, quantity}]}` â€” `dungeon_builder.gd`
- `placements.traps[]`: `{roomId, trapId, offset, sampleNavmesh}` â€” resolved via `TrapCatalog`
- `placements.secrets[]`: `{roomId, mechanism, parentRoomId, wallDirection}`
- `placements.cover[]`: `{roomId, offset, size, kind}` â€” schema in `dungeon-definition.v1.json`
- `placements.boss`: `{roomId, enemyId}` or generation fails
- Biome inputs: `lootTables`, `trapPool`, `enemyPool`, `bossPool`, `budgets`

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Enemy budget and weighted pool | IMPLEMENTED | `procgen_placements.gd:64-68,347-359` |
| Anchored spawn/chest/trap positions | IMPLEMENTED | `room_template_catalog.gd:13-228`, `procgen_placements.gd:86-99` |
| Data-driven loot with tier budget | IMPLEMENTED | `procgen_loot_roller.gd:14-26` |
| Named RNG streams | IMPLEMENTED | `procgen_rng.gd:8-21` |
| Trap scene resolution | IMPLEMENTED | `trap_catalog.gd:8-16`, `dungeon_builder.gd:677-682` |
| `frost_trap` / `shadow_trap` scenes | IMPLEMENTED | `scenes/traps/frost_trap.tscn`, `shadow_trap.tscn` |
| `treasure_main` on treasure floors | IMPLEMENTED | `procgen_placements.gd:134-145` |
| Fail-loud missing boss/hub | IMPLEMENTED | `procgen_placements.gd:268-279`, `dungeon_procgen.gd:66-70` |
| Threat cost cache | IMPLEMENTED | `procgen_placements.gd:358-373` |
| Weighted boss selection | IMPLEMENTED | `procgen_placements.gd:256-261` |
| Natural room ordering | IMPLEMENTED | `procgen_placements.gd:318-333` |
| Door-distance enemy density | IMPLEMENTED | `procgen_placements.gd:72-82` |
| `cover` in schema | IMPLEMENTED | `content/schemas/dungeon-definition.v1.json` |
| `cover[].kind` geometry | IMPLEMENTED | `procgen_placements.gd:307-314` |
| `placements.puzzles` | ABSENT | hardcoded `[]` (`procgen_placements.gd:43`) |
| Scene `PropAnchor` cross-check | ABSENT | RTP-07 markers not in room scenes yet; catalog anchors only |

## Related

- Improvement plan: [`../actual_improvements/procgen-placements.md`](../actual_improvements/procgen-placements.md) - **FINISHED**
- [`room-graph-procgen.md`](room-graph-procgen.md) â€” assignment consumed by this pass
- [`room-content.md`](room-content.md) â€” parallel content tagging; reward chests use `ProcgenLootRoller`
- [`dungeon-builder.md`](dungeon-builder.md) â€” consumes every placement array
- [`biome-registry.md`](biome-registry.md) â€” biome JSON source
- [`dungeon-traps.md`](dungeon-traps.md) â€” trap scenes
- [`loot-and-equipment.md`](loot-and-equipment.md) â€” `ItemCatalog`, `LootChest`
