# Dungeon catalog and tiers

Ten dungeons, each mapped 1:1 to a biome and to a progression tier. `DungeonCatalog` is the list, `DungeonTierService` is the autoload that tracks how far the player has unlocked, `CastleTierDifficulty` and `EndlessDifficulty` scale enemies, `RunFloorConfig` holds floor constants and seed mixing, and `SkipFloorService` lets a consumable start an endless run deep.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/dungeon_catalog.gd` | The 10-entry dungeon list and tier/index math |
| `apps/game/client/scripts/dungeon/dungeon_tier_service.gd` | Autoload: unlock state, hub label, unlock-on-clear |
| `apps/game/client/scripts/dungeon/castle_tier_difficulty.gd` | HP / damage / loot scaling by dungeon tier |
| `apps/game/client/scripts/dungeon/endless_difficulty.gd` | HP / damage / drop scaling by endless floor |
| `apps/game/client/scripts/dungeon/run_floor_config.gd` | Floor count constants, seed mixing, stair helpers |
| `apps/game/client/scripts/dungeon/skip_floor_service.gd` | Skip-floor consumables |

## How it works

### The catalog

`DungeonCatalog.ENTRIES` (`dungeon_catalog.gd:8-19`) is a hardcoded array of ten `{id, name, biomeId}` dictionaries. `id` and `biomeId` are identical for all ten, and `name` duplicates `BiomeRegistry.get_display_name()` (`biome_registry.gd:23-44`).

Tier is array position: `get_tier_for_dungeon(id)` returns `index + 1` (`:61`), `get_dungeon_for_tier(tier)` clamps `tier - 1` into range (`:66`), and `is_unlocked_at_tier(id, max_tier)` is `index < max_tier` (`:71`). So "tier" is not a difficulty setting within a dungeon — it is the dungeon's slot in the ladder. Tier 4 always means Frozen Fortress.

Every lookup is a linear scan of the ten entries (`:29`, `:36`, `:43`, `:54`).

### Unlock state

`DungeonTierService` is an autoload (`project.godot:47`). It stores one integer under the `CharacterService` flag `dungeon_max_tier`, clamped to 1..10 (`dungeon_tier_service.gd:5-6,16-17`), so unlocks are per character.

`on_dungeon_cleared(dungeon_id)` (`:50`) unlocks the next tier only when the cleared dungeon's tier is at or above the current maximum. Its only caller is `run_flow.gd:391`. `unlock_next_tier()` emits `tier_unlocked`, which `hub.gd:65` listens to in order to refresh the portal label (`hub.gd:260`).

Consumers of the unlock state:

| Caller | Line | Use |
|--------|------|-----|
| `castle_entry_menu.gd` | `:50-55` | title text and filtering the dungeon list |
| `run_flow.gd` | `:80-82` | refuses to start a locked dungeon |
| `run_flow.gd` | `:257,264` | refuses to resume a save above the unlock cap |
| `dungeon_seed_service.gd` | `:28,32` | gates seeded runs by tier |
| `game_facade.gd` | `:35` | exposed as `dungeon_tiers` |

### Difficulty scaling

`CastleTierDifficulty` (`castle_tier_difficulty.gd`) is linear in tier with no cap:

| Function | Formula | Tier 10 |
|----------|---------|---------|
| `hp_multiplier(tier)` | `1 + (tier - 1) * 0.15` | 2.35 |
| `damage_multiplier(tier)` | `1 + (tier - 1) * 0.08` | 1.72 |
| `loot_bonus(tier)` | `(tier - 1) * 0.05` | 0.45 |

`hp_multiplier` and `damage_multiplier` are applied by `DungeonBuilder._apply_floor_scaling` in castle mode (`dungeon_builder.gd:932-939`); `loot_bonus` is applied by `GlobalDropService` (`global_drop_service.gd:19`). Because the multipliers depend only on the dungeon tier, floor 1 and floor 10 of the same castle run have identical enemy stats — within a run, only the layout changes.

`EndlessDifficulty` (`endless_difficulty.gd`) works off `floor_tier(floor_index) = floor_index / 10` (integer division, `:13-14`):

| Function | Formula |
|----------|---------|
| `hp_multiplier(f)` | `1 + tier * 0.12`, plus `0.35 * (tier - 1)` when `f > 10` |
| `damage_multiplier(f)` | `1 + tier * 0.10`, plus `0.25 * (tier - 1)` when `f > 10` |
| `rare_drop_bonus(f)` | `min(tier * 0.02, 0.30)` — caps at tier 15, floor 150 |

The heavy bonus subtracts `floor_tier(10)` (which is 1), so it contributes nothing between floors 11 and 19 and then steps in at floor 20. With `ENDLESS_MAX_FLOORS = 999999` neither HP nor damage is capped: at floor 1000 the HP multiplier is roughly 46, and at the endless ceiling it is roughly 47000.

### Floor constants and seed mixing

`RunFloorConfig` (`run_floor_config.gd`):

| Symbol | Value | Reader |
|--------|-------|--------|
| `MAX_FLOORS` | 10 | `clamp_floor`, `is_final_floor`, `max_floors_for_mode` |
| `ENDLESS_MAX_FLOORS` | 999999 | `max_floors_for_mode` |
| `MAX_SECRETS_PER_FLOOR` | 2 | only `m7_suite.gd:245,273` — the generator uses its own `RoomGraphConfig.max_secrets`, also 2 (`room_graph_config.gd:14`) |
| `FLOOR_SEED_MULTIPLIER` | 7919 | `mix_seed` |
| `DROP_RATE_BONUS_PER_TIER` | 0.02 | `EndlessDifficulty.rare_drop_bonus` |
| `DROP_RATE_BONUS_CAP` | 0.30 | same |

`mix_seed(run_seed, floor_index)` (`:14`) returns `run_seed` unchanged for floor 1 and `run_seed + floor_index * 7919` otherwise. It is plain addition, not a hash, so consecutive floors get seeds a fixed 7919 apart. `DungeonSeedService.mix_floor_seed` delegates to it (`dungeon_seed_service.gd`), and the C# side computes the same value — see [`local-procgen.md`](local-procgen.md).

`is_final_floor(floor_index, run_mode)` (`:27`) returns false unconditionally in endless mode, which is what makes endless endless.

`find_stairs_room_id(definition)` (`:47`) accepts either a `templateId` ending in `_stairs` **or** `type == "corridor"`. `DungeonBuilder._setup_stair_levers` only checks the suffix (`dungeon_builder.gd:615`), so the two disagree when template substitution replaces the stairs kit. Callers: `castle_run.gd:176,294`.

`stairs_spawn_facing_y(stair_room, ascending)` (`:56`) returns the SOUTH socket's world yaw plus PI when that socket exists, and only falls through to the `ascending` branches otherwise. Every one of the 90 room scenes has a `Socket_S`, so the `ascending` argument never affects the result.

`count_secrets(definition)` (`:39`) counts rooms of `type == "secret"`; only `m7_suite.gd:269` calls it.

### Skip-floor consumables

`SkipFloorService.SKIP_ITEMS` (`skip_floor_service.gd:6-11`) maps four item ids to start floors:

| Item | Start floor |
|------|-------------|
| `skip_10_floors` | 11 |
| `skip_50_floors` | 51 |
| `skip_100_floors` | 101 |
| `skip_500_floors` | 501 |

All four item JSONs exist under `content/items/consumables/`, appear in `content/items/catalog.json`, and have drop entries in `content/loot/global_drops.json`.

`get_available_skips(inventory)` (`:14`) scans `GridInventory.slots` directly and returns entries sorted by descending start floor. `consume_skip` (`:30`) removes one instance and returns whether it succeeded. `start_floor_for_item` (`:44`) defaults to 1 for an unknown id.

`umbral_endless_menu.gd:95,116,126` presents the options. `run_flow.gd:63-67` consumes:

```gdscript
if skip_item_id != "":
    SkipFloorSvc.consume_skip(InventoryService.inventory, skip_item_id)
    start_floor = SkipFloorSvc.start_floor_for_item(skip_item_id)
```

The return value of `consume_skip` is discarded, so if the item is absent the run still starts at the skipped floor.

## Contracts

- `DungeonCatalog` and the two difficulty scripts are `RefCounted` with `class_name`, called statically. `DungeonTierService` is the only autoload here.
- Save contract: the `CharacterService` flag `dungeon_max_tier` (integer 1..10). `run_flow.gd:226-232` also persists `dungeonId` and falls back through `biomeId` for older saves.
- `DungeonCatalog.get_biome_id(id)` is the bridge from a dungeon selection to a `BiomeRegistry` biome id.
- `RunFloorConfig.mix_seed` must stay bit-identical to the C# floor-seed derivation for cross-stack reproducibility.
- Signal out: `DungeonTierService.tier_unlocked(tier)`, consumed by `hub.gd:65`.
- `SkipFloorService` requires `GridInventory` with a `slots` array of `{itemId, quantity}` and `remove_items_by_id`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| 10-dungeon catalog with tier mapping | IMPLEMENTED | `dungeon_catalog.gd:8-73` |
| Unlock-on-clear progression | IMPLEMENTED | `dungeon_tier_service.gd:50-53`, `run_flow.gd:391` |
| Per-character unlock persistence | IMPLEMENTED | `dungeon_tier_service.gd:16-17,33` |
| Skip-floor consumables | IMPLEMENTED | `skip_floor_service.gd`, all 4 items present in `content/` |
| Castle tier scaling | IMPLEMENTED | `castle_tier_difficulty.gd`, applied at `dungeon_builder.gd:932-939` and `global_drop_service.gd:19` |
| Endless floor scaling | IMPLEMENTED | `endless_difficulty.gd`, applied at `dungeon_builder.gd:923-931` |
| Catalog as data | PLACEHOLDER | hardcoded `ENTRIES` array duplicating `BiomeRegistry` names (`dungeon_catalog.gd:8-19`) |
| Tier as a difficulty axis | ABSENT | tier is the dungeon slot; a given dungeon has exactly one difficulty |
| Within-run difficulty growth in castle mode | ABSENT | `_apply_floor_scaling` uses only `RunFlow.get_dungeon_tier()` (`dungeon_builder.gd:932-939`) |
| Endless scaling cap | ABSENT | HP and damage grow without bound to floor 999999 (`endless_difficulty.gd:17-32`) |
| `skip_item` consumption check | BROKEN | `consume_skip` result discarded, so a missing item still skips (`run_flow.gd:65`) |
| Floor seed mixing | PARTIAL | plain addition of `floor_index * 7919` rather than a hash (`run_floor_config.gd:17`) |
| `MAX_SECRETS_PER_FLOOR` | STUB | read only by `m7_suite.gd`; the generator uses `RoomGraphConfig.max_secrets` |
| `count_secrets` | STUB | read only by `m7_suite.gd:269` |
| `stairs_spawn_facing_y(..., ascending)` | PARTIAL | the `ascending` argument is unreachable because every scene has a `Socket_S` (`run_floor_config.gd:56-63`) |
| `find_stairs_room_id` vs the builder's stair lookup | PARTIAL | one accepts `type == "corridor"`, the other only the `_stairs` suffix (`run_floor_config.gd:51` vs `dungeon_builder.gd:615`) |
| Tier rewards beyond scaling | ABSENT | no per-tier loot table, boss, or modifier; only the three multipliers |
| Endless heavy-bonus threshold | PARTIAL | `HP_HEAVY_AFTER_FLOOR = 10` combined with `floor_tier(10) = 1` means the bonus first applies at floor 20 (`endless_difficulty.gd:20-22`) |

## Related

- Improvement plan: [`../actual_improvements/dungeon-catalog-tiers.md`](../actual_improvements/dungeon-catalog-tiers.md)
- [`local-procgen.md`](local-procgen.md) — `DungeonSeedService`, tier and floor seed derivation
- [`biome-registry.md`](biome-registry.md) — `get_biome_id` target, duplicated display names
- [`dungeon-builder.md`](dungeon-builder.md) — applies both difficulty scripts
- [`run-flow.md`](run-flow.md) — the only caller of `on_dungeon_cleared` and the skip path
- [`stair-lever.md`](stair-lever.md) — `stairs_spawn_facing_y` consumer
- [`castle-run.md`](castle-run.md) — `find_stairs_room_id` consumer
- [`progression-service.md`](progression-service.md), [`character-service.md`](character-service.md) — flag storage
- [`loot-and-equipment.md`](loot-and-equipment.md) — `GlobalDropService` and the skip items
- [`ui/hub_vendors.md`](ui/hub_vendors.md) — hub portal label
