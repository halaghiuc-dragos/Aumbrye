# Dungeon catalog and tiers — improvement plan

## Status: FINISHED

## Current state

All DCT-01–DCT-13 gaps are implemented. The catalog loads from `content/dungeons/*.json`; display names come from biome JSON, not the catalog. Dungeon unlock uses `dungeon_unlocked_count`; per-dungeon difficulty caps use `dungeon_tier_<id>`. Castle runs scale by difficulty tier plus per-floor growth; endless scaling is bounded. Skip-floor consumption is enforced. See [`../existing_codebase/dungeon-catalog-tiers.md`](../existing_codebase/dungeon-catalog-tiers.md).

## Gaps

| ID | Sev | Gap | Status | Evidence |
|----|-----|-----|--------|----------|
| DCT-01 | P0 | Skip-floor items not required | **FINISHED** | `run_flow.gd:84-88` checks `consume_skip` return; `skip_floor_service.gd:36-41` validates `ItemCatalog` |
| DCT-02 | P0 | No per-floor castle difficulty curve | **FINISHED** | `castle_tier_difficulty.gd:31-42` floor factors; `dungeon_builder.gd:1145-1165` applies combined multipliers |
| DCT-03 | P1 | Tier equals dungeon slot only | **FINISHED** | `content/dungeons/*.json` `difficultyTiers`; `dungeon_tier_service.gd:77-85`; `castle_entry_menu.gd:72-88` |
| DCT-04 | P1 | Unbounded endless multipliers | **FINISHED** | `endless_difficulty.gd:6-32` soft caps 25 HP / 12 damage |
| DCT-05 | P1 | Additive floor seed stride | **FINISHED** | `floor_seed_mix.gd:6-14`; `run_floor_config.gd:17-18`; `cross_stack_parity_suite.gd:60-81` |
| DCT-06 | P1 | Hardcoded catalog names | **FINISHED** | `dungeon_catalog.gd:67-70` loads JSON; no `name` in catalog files |
| DCT-07 | P1 | Stair lookup disagreement | **FINISHED** | `run_floor_config.gd:47-56` `is_stairs_room`; `dungeon_builder.gd:787` uses same helper |
| DCT-08 | P2 | Heavy-bonus off-by-one tier | **FINISHED** | removed — `endless_difficulty.gd` no longer has `HP_HEAVY_*` |
| DCT-09 | P2 | Duplicate secret cap constant | **FINISHED** | `MAX_SECRETS_PER_FLOOR` deleted; `run_floor_config.gd:43-45` `max_secrets_for_biome`; `room_graph_config.gd:37` |
| DCT-10 | P2 | Unreachable `ascending` in `stairs_spawn_facing_y` | **FINISHED** | `run_floor_config.gd:59-65` single-arg API |
| DCT-11 | P2 | `count_secrets` no production caller | **FINISHED** | `dungeon_procgen.gd:116-121` asserts cap via `count_secrets` |
| DCT-12 | P2 | Linear catalog scans | **FINISHED** | `dungeon_catalog.gd:11-12` `_by_id` dictionary at load |
| DCT-13 | P2 | Tier rewards beyond three multipliers | **FINISHED** | `difficultyTiers[].modifiers`; `run_modifier_service.gd`; `procgen_placements.gd:114-127`, `room_content_assigner.gd:201-204,323-325` |

## Target design

Implemented as specified in the original plan: data-driven catalog, separate dungeon order vs difficulty tier, per-floor castle growth from JSON coefficients, bounded endless curve with depth modifiers every 50 floors, SplitMix64 floor seeds, unified stair lookup, biome-sourced secret cap, and three named run modifiers (`elite_packs`, `no_rest`, `sealed_doors`).

## Work plan

All steps landed:

1. Skip exploit — `run_flow.gd:84-88` (DCT-01)
2. Per-floor scaling — `castle_tier_difficulty.gd`, `dungeon_builder.gd` (DCT-02)
3. Bounded endless — `endless_difficulty.gd` (DCT-04, DCT-08)
4. Catalog to data — `content/dungeons/*.json`, `dungeon_catalog.gd` (DCT-06, DCT-12)
5. Difficulty tiers — `dungeon_tier_service.gd`, `castle_entry_menu.gd`, `save_migrator.gd:604-625` v6→v7 (DCT-03, DCT-13)
6. Run modifiers — `run_modifier_service.gd`, procgen/content hooks (DCT-13)
7. Hashed floor seeds — pre-existing `floor_seed_mix.gd` + parity fixture (DCT-05)
8. Consistency cleanup — stair lookup, secret cap, `stairs_spawn_facing_y`, `count_secrets` (DCT-07, DCT-09–DCT-11)

## Data and schema changes

- Added `content/schemas/dungeon-catalog-entry.v1.json` and `content/dungeons/<id>.json` × 10.
- `biome-definition.v1.json` already exposes `maxSecrets` (default 2 via `room_graph_config.gd:37`).
- Save v7: `dungeon_unlocked_count`, `dungeon_tier_<id>`, active-run `difficultyTier` (`save_migrator.gd:604-625`).
- Floor-seed parity unchanged in `content/fixtures/mix_seed_parity.json`.

## Acceptance criteria

- [x] Starting endless with missing skip item blocks the run and sets `last_hub_message` (DCT-01) — `run_flow.gd:84-88`; `m5_suite` skip test deferred to hub flow; `m7_suite` catalog skip items.
- [x] Castle floor 10 enemies have more HP than floor 1 (DCT-02) — `dungeon_suite.gd` `_test_floor_scaling_curve`.
- [x] Floor 10 final-floor layout uses biome template prefix and `finalFloor.bossId` (RGP-08).
- [x] Each dungeon has ≥3 difficulty tiers with strictly increasing `hpMult` and `lootBonus` (DCT-03) — `m5_suite.gd` `_test_difficulty_tier_selection`.
- [x] `EndlessDifficulty.hp_multiplier(999999) <= 25.0` and damage `<= 12.0` (DCT-04) — `m7_suite.gd` `_test_endless_curve_bounded`.
- [x] `mix_seed(s, f)` vs `mix_seed(s, f+1)` Hamming distance ≥ 10 for 1000 samples (DCT-05) — `m7_suite.gd` `_test_floor_seed_avalanche`.
- [x] GDScript `mix_seed` matches C# fixture (DCT-05) — `cross_stack_parity_suite.gd:60-81`.
- [x] `dungeon_catalog.gd` contains no display-name string (DCT-06) — `m5_suite.gd` `_test_catalog_from_data`.
- [x] `find_stairs_room_id` matches stairs template room (DCT-07) — `dungeon_suite.gd` `_test_stair_lookup_agreement`.
- [x] `RunFloorConfig.MAX_SECRETS_PER_FLOOR` removed; cap from biome (DCT-09) — `m7_suite.gd` `_test_secret_cap_from_biome`.
- [x] Save v6→v7 sets `dungeon_unlocked_count` from `dungeon_max_tier` and `dungeon_tier_<id> = 1` (`save_migrator.gd:604-625`).

## Validation

Extended suites:

- `m5_suite.gd`: `_test_catalog_from_data`, `_test_difficulty_tier_selection`, `_test_tier_unlock_per_dungeon`
- `m7_suite.gd`: `_test_endless_curve_bounded`, `_test_floor_seed_avalanche`, `_test_secret_cap_from_biome`
- `dungeon_suite.gd`: `_test_floor_scaling_curve`, `_test_stair_lookup_agreement`
- `cross_stack_parity_suite.gd`: existing `mix_seed_parity`

## Related

- [`../existing_codebase/dungeon-catalog-tiers.md`](../existing_codebase/dungeon-catalog-tiers.md)
- [`local-procgen.md`](local-procgen.md) — LPG-05 seed hashing
- [`biome-registry.md`](biome-registry.md) — display names, `maxSecrets`
- [`procgen-placements.md`](procgen-placements.md) — threat budget by tier
- [`dungeon-builder.md`](dungeon-builder.md) — floor scaling application
- [`room-graph-procgen.md`](room-graph-procgen.md) — RGP-05 parity
- [`run-flow.md`](run-flow.md) — skip path, modifiers, unlock-on-clear
- [`save-migrator.md`](save-migrator.md), [`local-save.md`](local-save.md) — v7 flags
- [`ui/hub_vendors.md`](ui/hub_vendors.md), [`ui/run_flow_ui.md`](ui/run_flow_ui.md) — tier selector
- [`loot-and-equipment.md`](loot-and-equipment.md) — `lootBonus` via `global_drop_service.gd:19-26`
