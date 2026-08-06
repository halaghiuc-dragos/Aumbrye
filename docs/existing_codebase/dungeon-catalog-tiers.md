# Dungeon catalog and tiers

Ten dungeons loaded from `content/dungeons/*.json`, each mapped to a biome and a ladder `order`. `DungeonCatalog` is the data reader, `DungeonTierService` tracks dungeon unlock count and per-dungeon difficulty caps, `CastleTierDifficulty` and `EndlessDifficulty` scale enemies, `RunFloorConfig` holds floor constants and seed mixing, and `SkipFloorService` gates endless skip consumables.

## Files

| Path | Role |
|------|------|
| `content/dungeons/*.json` | Catalog entries: `order`, `difficultyTiers`, floor growth coefficients |
| `content/schemas/dungeon-catalog-entry.v1.json` | Schema for catalog JSON |
| `apps/game/client/scripts/dungeon/dungeon_catalog.gd` | Loads catalog; id-keyed `_by_id` cache |
| `apps/game/client/scripts/dungeon/dungeon_tier_service.gd` | Autoload: unlock count, per-dungeon difficulty cap |
| `apps/game/client/scripts/dungeon/castle_tier_difficulty.gd` | HP / damage / loot from difficulty tier + floor growth |
| `apps/game/client/scripts/dungeon/endless_difficulty.gd` | Bounded HP / damage / drop scaling by endless floor |
| `apps/game/client/scripts/dungeon/run_floor_config.gd` | Floor caps, seed mixing, stair helpers, biome secret cap |
| `apps/game/client/scripts/dungeon/floor_seed_mix.gd` | SplitMix64 `FloorSeedMix.mix` |
| `apps/game/client/scripts/dungeon/run_modifier_service.gd` | Active run modifiers (`elite_packs`, `no_rest`, `sealed_doors`) |
| `apps/game/client/scripts/dungeon/skip_floor_service.gd` | Skip-floor consumables |

## How it works

### The catalog

`DungeonCatalog` loads every `content/dungeons/<id>.json` at first access (`dungeon_catalog.gd:24-54`), sorts by `order`, and caches entries in `_by_id` for O(1) lookup (`dungeon_catalog.gd:11-12,64-66`). Display names come from `content/biomes/<biomeId>.json` `name` (`dungeon_catalog.gd:67-70`), not the catalog file.

Each entry includes:

| Field | Purpose |
|-------|---------|
| `order` | Ladder position (1â€“10); replaces array index |
| `biomeId` | Procgen / display bridge |
| `difficultyTiers` | 3+ tiers with `hpMult`, `damageMult`, `lootBonus`, `modifiers` |
| `floorHpGrowth` / `floorDamageGrowth` | Per-floor multipliers inside a run (default 0.06 / 0.04) |
| `unlockRequirement` | `none` or `clear_dungeon` predecessor |
| `clearFlag` | Character theme-cleared flag |

`get_order_for_dungeon(id)` returns `order` (`dungeon_catalog.gd:104-108`). `get_tier_for_dungeon` is an alias for backward compatibility.

### Unlock state

`DungeonTierService` stores:

| Flag | Meaning |
|------|---------|
| `dungeon_unlocked_count` | How many dungeons in the ladder are selectable (1â€“10) |
| `dungeon_tier_<id>` | Highest difficulty tier unlocked for that dungeon (starts at 1) |

Legacy `dungeon_max_tier` is read as fallback (`dungeon_tier_service.gd:20-23`). `on_dungeon_cleared(dungeon_id, difficulty_tier)` (`dungeon_tier_service.gd:77-85`) unlocks the next dungeon when clearing at the frontier and bumps the per-dungeon difficulty cap when the cleared tier equals the current cap.

Consumers:

| Caller | Use |
|--------|-----|
| `castle_entry_menu.gd` | Dungeon + difficulty dropdowns |
| `run_flow.gd` | Start gate, save `difficultyTier`, clear callback |
| `dungeon_seed_service.gd` | Seed tier from dungeon `order` |

### Difficulty scaling

**Castle mode** â€” tier stats from catalog Ã— floor growth:

| Function | Formula |
|----------|---------|
| `hp_multiplier(dungeon_id, tier)` | `difficultyTiers[tier].hpMult` |
| `floor_hp_factor(dungeon_id, floor)` | `1 + floorHpGrowth Ã— (floor - 1)` |
| `combined_hp_multiplier(...)` | product of the two |

Applied in `DungeonBuilder._apply_floor_scaling` (`dungeon_builder.gd:1145-1165`). Elite enemies (`isElite` placement flag) get Ã—1.5 HP / Ã—1.25 damage.

**Endless mode** â€” bounded curve (`endless_difficulty.gd`):

| Constant | Value |
|----------|-------|
| `HP_SOFT_CAP` | 25.0 |
| `DAMAGE_SOFT_CAP` | 12.0 |
| Knee tier | 12 (floor 120) |

`RunModifierService.apply_endless_floor_modifiers(floor)` adds modifiers every 50 floors (`run_modifier_service.gd:33-38`).

### Run modifiers

From `difficultyTiers[].modifiers` at run start (`run_flow.gd:115-117`) or endless depth:

| Modifier | Effect |
|----------|--------|
| `elite_packs` | First enemy per combat room marked `isElite` (`procgen_placements.gd:114-127`) |
| `no_rest` | Rest content weight zero (`room_content_assigner.gd:201-204,223`) |
| `sealed_doors` | Locks require 2 keys (`room_content_assigner.gd:323-325`, `room_locked_door_content.gd:92-99`) |

### Floor constants and seed mixing

`RunFloorConfig.mix_seed` delegates to `FloorSeedMix.mix` (`run_floor_config.gd:17-18`). Floor 1 returns the input seed unchanged (`floor_seed_mix.gd:8-9`).

`max_secrets_for_biome(biome_id)` reads `maxSecrets` from biome JSON, default 2 (`run_floor_config.gd:43-45`). `count_secrets(definition)` counts `type == "secret"` rooms; `dungeon_procgen.gd:116-121` rejects definitions exceeding the biome cap.

`is_stairs_room` / `find_stairs_room_id` match `templateId` ending `_stairs` (`run_floor_config.gd:47-56`). `DungeonBuilder._setup_stair_levers` uses the same helper (`dungeon_builder.gd:787`).

`stairs_spawn_facing_y(stair_room)` uses the SOUTH socket yaw + Ï€ (`run_floor_config.gd:59-65`).

### Skip-floor consumables

`SkipFloorService.consume_skip` validates `ItemCatalog` and returns false when the item is absent (`skip_floor_service.gd:36-41`). `run_flow.gd:84-88` aborts the endless start and sets `last_hub_message` when consumption fails.

## Contracts

- Save v7: `dungeon_unlocked_count`, `dungeon_tier_<id>`, active-run `difficultyTier` (`save_migrator.gd:604-625`).
- `RunFlow.get_dungeon_tier()` returns dungeon **order** (seed / API). `get_difficulty_tier()` returns the selected difficulty tier within the dungeon.
- `RunFloorConfig.mix_seed` must stay identical to C# `DungeonSeedDeriver.MixFloorSeed` (`content/fixtures/mix_seed_parity.json`).
- Signal: `DungeonTierService.tier_unlocked(tier)`, `difficulty_tier_unlocked(dungeon_id, tier)`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Data-driven 10-dungeon catalog | IMPLEMENTED | `content/dungeons/*.json`, `dungeon_catalog.gd` |
| Per-dungeon difficulty tiers (3+) | IMPLEMENTED | `difficultyTiers` in catalog JSON; `castle_entry_menu.gd:72-88` |
| Dungeon ladder unlock | IMPLEMENTED | `dungeon_unlocked_count`; `dungeon_tier_service.gd:77-80` |
| Per-floor castle scaling | IMPLEMENTED | `castle_tier_difficulty.gd:31-42`; `dungeon_builder.gd:1145-1165` |
| Bounded endless scaling | IMPLEMENTED | `endless_difficulty.gd:6-32` |
| Skip-floor consumption gate | IMPLEMENTED | `run_flow.gd:84-88` |
| Hashed floor seeds | IMPLEMENTED | `floor_seed_mix.gd`; C# parity fixture |
| Run modifiers | IMPLEMENTED | `run_modifier_service.gd`; procgen/content hooks |
| Secret cap from biome | IMPLEMENTED | `run_floor_config.gd:43-45`; `dungeon_procgen.gd:116-121` |
| Unified stair lookup | IMPLEMENTED | `run_floor_config.gd:47-56`; `dungeon_builder.gd:787` |
| Id-keyed catalog cache | IMPLEMENTED | `dungeon_catalog.gd:11-12,64-66` |

## Related

- Improvement plan: [`../actual_improvements/dungeon-catalog-tiers.md`](../actual_improvements/dungeon-catalog-tiers.md) - **FINISHED**
- [`local-procgen.md`](local-procgen.md) â€” floor seed derivation
- [`biome-registry.md`](biome-registry.md) â€” display names, `maxSecrets`
- [`dungeon-builder.md`](dungeon-builder.md) â€” scaling application
- [`run-flow.md`](run-flow.md) â€” skip path, modifiers, unlock-on-clear
- [`save-migrator.md`](save-migrator.md) â€” v7 migration
- [`loot-and-equipment.md`](loot-and-equipment.md) â€” `lootBonus` consumer
