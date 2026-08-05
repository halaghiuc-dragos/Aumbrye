# Dungeon catalog and tiers — improvement plan

## Current state

The unlock ladder works: ten dungeons, clear tier N to unlock N+1, persisted per character. What is missing is any real progression *inside* a dungeon. Tier is the dungeon's slot in the list, so Frozen Fortress has exactly one difficulty forever; within a castle run, floor 1 and floor 10 have identical enemy stats. Endless scaling is unbounded to floor 999999. A skip-floor consumable is granted even when the item is not in the inventory, because the consume result is discarded. See [`../existing_codebase/dungeon-catalog-tiers.md`](../existing_codebase/dungeon-catalog-tiers.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DCT-01 | P0 | Skip-floor items are never actually required: `consume_skip`'s return value is discarded, so any `skip_item_id` starts the run at the skipped floor | `run_flow.gd:63-67`, `skip_floor_service.gd:30-33` |
| DCT-02 | P0 | Castle-mode difficulty depends only on the dungeon tier, so a 10-floor run has no difficulty curve | `dungeon_builder.gd:932-939`, `castle_tier_difficulty.gd:11-16` |
| DCT-03 | P1 | Tier and dungeon are the same axis, so a cleared dungeon has no replay value and there is no way to run Forgotten Castle at a higher difficulty | `dungeon_catalog.gd:61-73` |
| DCT-04 | P1 | Endless HP and damage multipliers are unbounded: roughly 46x at floor 1000 and roughly 47000x at the endless ceiling | `endless_difficulty.gd:17-32`, `run_floor_config.gd:7` |
| DCT-05 | P1 | Floor seeds are `run_seed + floor_index * 7919`, a fixed stride rather than a hash, so adjacent floors are correlated | `run_floor_config.gd:14-18` |
| DCT-06 | P1 | The catalog is a hardcoded array duplicating every biome's display name | `dungeon_catalog.gd:8-19` vs `biome_registry.gd:23-44` |
| DCT-07 | P1 | `find_stairs_room_id` accepts `type == "corridor"` while `DungeonBuilder` only accepts the `_stairs` suffix, so the two disagree after template substitution | `run_floor_config.gd:51` vs `dungeon_builder.gd:615` |
| DCT-08 | P2 | The endless heavy bonus first applies at floor 20 despite `HP_HEAVY_AFTER_FLOOR = 10`, because `floor_tier(10)` is 1 | `endless_difficulty.gd:7,20-22` |
| DCT-09 | P2 | Two separate constants define the secret cap; only the generator's copy has effect, and `RunFloorConfig.MAX_SECRETS_PER_FLOOR` is read only by a suite | `run_floor_config.gd:8`, `room_graph_config.gd:14`, `m7_suite.gd:245` |
| DCT-10 | P2 | The `ascending` argument to `stairs_spawn_facing_y` is unreachable because every room scene has a `Socket_S` | `run_floor_config.gd:56-63` |
| DCT-11 | P2 | `count_secrets` has no production caller | `run_floor_config.gd:39`, only `m7_suite.gd:269` |
| DCT-12 | P2 | Every catalog lookup is a linear scan over the ten entries | `dungeon_catalog.gd:29,36,43,54` |
| DCT-13 | P2 | Tiers grant only three multipliers — no per-tier loot table, boss variant, or run modifier | `castle_tier_difficulty.gd`, no other tier reader |

## Target design

Two separate ideas are tangled together today: *which dungeon* and *how hard*. Separate them, then give each floor of a run its own difficulty step.

### 1. Fix the skip exploit first (DCT-01)

```gdscript
func start_endless_run(start_floor: int = 1, skip_item_id: String = "") -> void:
    if skip_item_id != "":
        if not SkipFloorSvc.consume_skip(InventoryService.inventory, skip_item_id):
            last_hub_message = "You do not have that skip item."
            return
        start_floor = SkipFloorSvc.start_floor_for_item(skip_item_id)
    await _start_mode_run(RM.MODE_ENDLESS, BiomeRegistry.BIOME_UMBRAL, null, start_floor)
```

`SkipFloorService` additionally validates the item id against `ItemCatalog` so a renamed item fails loudly rather than silently starting at floor 1.

### 2. Dungeon and difficulty as separate axes (DCT-03, DCT-06, DCT-13)

Move the catalog into `content/dungeons/<id>.json` with a new `content/schemas/dungeon-catalog-entry.v1.json`:

```json
{
  "id": "forgotten_castle",
  "biomeId": "forgotten_castle",
  "order": 1,
  "unlockRequirement": { "kind": "clear_dungeon", "dungeonId": null },
  "difficultyTiers": [
    { "tier": 1, "label": "Ruined",   "hpMult": 1.00, "damageMult": 1.00, "lootBonus": 0.00, "modifiers": [] },
    { "tier": 2, "label": "Haunted",  "hpMult": 1.35, "damageMult": 1.18, "lootBonus": 0.15, "modifiers": ["elite_packs"] },
    { "tier": 3, "label": "Cursed",   "hpMult": 1.80, "damageMult": 1.40, "lootBonus": 0.35, "modifiers": ["elite_packs", "no_rest"] }
  ]
}
```

`order` replaces array position, and `name` is dropped entirely — the display name comes from `BiomeRegistry` via `biomeId` (DCT-06). `unlockRequirement` makes the ladder explicit and extensible (clear the previous dungeon, or reach a character level, or hold an item) rather than implicit in the index.

`difficultyTiers` is the new axis: each dungeon can be re-run harder for better loot, which is where replay value comes from (DCT-03). Progress is stored per dungeon: `CharacterService` flag `dungeon_tier_<id>` holds the highest difficulty tier cleared, and clearing tier T of a dungeon unlocks tier T+1 of that dungeon plus the next dungeon at tier 1. The existing global `dungeon_max_tier` flag becomes `dungeon_unlocked_count` and `save_migrator.gd` maps the old value across.

`modifiers` are named run modifiers resolved by [`run-flow.md`](run-flow.md); the first three are `elite_packs` (one enemy per combat room is promoted), `no_rest` (the `rest` content type is suppressed), and `sealed_doors` (all locks require two keys). Each is a small, testable rule rather than a stat multiplier.

`CastleTierDifficulty` becomes a thin reader over the selected tier's `hpMult`/`damageMult`/`lootBonus` instead of computing from linear constants, which removes the uncapped growth and lets designers tune per dungeon (DCT-13).

### 3. Per-floor difficulty inside a run (DCT-02)

Enemy scaling gains a floor term. `DungeonBuilder._apply_floor_scaling` in castle mode uses:

```
hp_mult      = tier.hpMult     * (1.0 + 0.06 * (floor_index - 1))
damage_mult  = tier.damageMult * (1.0 + 0.04 * (floor_index - 1))
```

At floor 10 that is a 1.54x HP and 1.36x damage step across a run — noticeable without being punishing, and it composes with the tier multiplier rather than replacing it. The coefficients live in the dungeon JSON as `floorHpGrowth` and `floorDamageGrowth` so they are tunable per dungeon.

This pairs with the threat budget already scaling by tier in [`procgen-placements.md`](procgen-placements.md): enemy *count* grows with depth, enemy *stats* grow with floor, and both grow with tier.

### 4. Bounded endless curve (DCT-04, DCT-08)

Replace the two-term linear formula with an explicitly bounded curve:

```gdscript
const HP_SOFT_CAP := 25.0
const HP_GROWTH := 0.14          # per floor tier
const HP_KNEE_TIER := 12         # linear below, logarithmic above

static func hp_multiplier(floor_index: int) -> float:
    var tier := floor_tier(floor_index)
    if tier <= HP_KNEE_TIER:
        return 1.0 + tier * HP_GROWTH
    var knee := 1.0 + HP_KNEE_TIER * HP_GROWTH
    return minf(HP_SOFT_CAP, knee + log(float(tier - HP_KNEE_TIER) + 1.0) * 2.5)
```

Damage uses the same shape with `DAMAGE_SOFT_CAP = 12.0` and `DAMAGE_GROWTH = 0.11`. The knee at tier 12 (floor 120) keeps the early-endless feel identical to today, and the soft caps mean floor 100000 is hard but not arithmetic overflow. The `HP_HEAVY_AFTER_FLOOR` / `HP_HEAVY_BONUS` pair and its off-by-one-tier behavior are deleted (DCT-08).

Above the cap, difficulty comes from modifiers instead of multipliers: at every 50 endless floors, add one modifier from the same named set used by difficulty tiers. That is more interesting than a bigger number and is testable.

### 5. Hashed floor seeds (DCT-05)

`mix_seed` moves to a 64-bit mixer shared with the RNG streams in [`procgen-placements.md`](procgen-placements.md) section 3 and [`local-procgen.md`](local-procgen.md) LPG-05:

```gdscript
static func mix_seed(run_seed: int, floor_index: int) -> int:
    var x := (int(run_seed) << 21) ^ int(floor_index)
    x = (x ^ (x >> 33)) * 0xFF51AFD7ED558CCD
    x = (x ^ (x >> 33)) * 0xC4CEB9FE1A85EC53
    x = x ^ (x >> 33)
    return maxi(1, x & 0x7FFFFFFF)
```

This is a breaking change for reproducibility, so it must land together with the identical C# change (`RunFloorConfig` has a C# mirror) and with regenerated fixtures. The parity assertion belongs in [`room-graph-procgen.md`](room-graph-procgen.md) RGP-05.

### 6. Consistency cleanup (DCT-07, DCT-09 through DCT-12)

- One stair lookup: `RunFloorConfig.find_stairs_room_id` and `DungeonBuilder._setup_stair_levers` both select on `room_type == "corridor"`, matching the assigner (DCT-07; the builder half is [`dungeon-builder.md`](dungeon-builder.md) step 7).
- One secret cap: delete `RunFloorConfig.MAX_SECRETS_PER_FLOOR`, move the value into the biome kit as `maxSecrets`, and have `RoomGraphConfig` read it (DCT-09; the biome field is [`biome-registry.md`](biome-registry.md) BIO-01).
- `stairs_spawn_facing_y` drops the unreachable `ascending` branches and takes the socket direction to face explicitly (DCT-10).
- `count_secrets` either gets a production caller in the generation assertion path or is deleted (DCT-11). Preference: keep it and use it in the generator to assert the cap.
- `DungeonCatalog` builds an id-keyed dictionary once at load (DCT-12).

## Work plan

1. **Skip exploit** — check `consume_skip`'s return; add the failure message (DCT-01). One-line fix, land immediately.
2. **Per-floor scaling** — floor term in `_apply_floor_scaling`, coefficients as constants first (DCT-02). Independently landable and immediately felt.
3. **Bounded endless curve** — new `EndlessDifficulty` formulas, delete the heavy-bonus pair (DCT-04, DCT-08).
4. **Catalog to data** — `content/dungeons/*.json`, schema, `DungeonCatalog` reads and caches, drop `name` (DCT-06, DCT-12).
5. **Difficulty tiers** — `difficultyTiers` block, per-dungeon `dungeon_tier_<id>` flag, `CastleTierDifficulty` reads the selected tier, entry menu gains a tier selector, `save_migrator` maps the old flag (DCT-03, DCT-13).
6. **Run modifiers** — the three named modifiers, applied in `RunFlow` and read by the placement and content passes (DCT-13).
7. **Hashed floor seeds** — GDScript and C# together, regenerate fixtures (DCT-05).
8. **Consistency cleanup** — stair lookup, secret cap, `stairs_spawn_facing_y`, `count_secrets` (DCT-07, DCT-09, DCT-10, DCT-11).

## Data and schema changes

- New `content/schemas/dungeon-catalog-entry.v1.json` and `content/dungeons/<id>.json` x 10, shape as above.
- `content/schemas/biome-definition.v2.json` gains `maxSecrets` (integer, default 2), replacing both current constants (DCT-09).
- Save format:
  - `dungeon_max_tier` (integer 1..10) becomes `dungeon_unlocked_count` (integer 1..10) plus `dungeon_tier_<id>` (integer, default 1) per dungeon.
  - `save_migrator.gd` sets `dungeon_unlocked_count = old dungeon_max_tier` and `dungeon_tier_<id> = 1` for every dungeon. Coordinate with [`save-migrator.md`](save-migrator.md) and [`local-save.md`](local-save.md).
  - Active-run saves gain `difficultyTier` so a resumed run keeps its multipliers.
- Fixture regeneration: any checked-in definition whose seed derives from `mix_seed` (`content/fixtures/*`, `seed1.json`, `seed99999.json`) changes when DCT-05 lands.

## Acceptance criteria

- [ ] Starting an endless run with a `skip_item_id` the inventory does not contain leaves the player in the hub with a message and does not consume anything (DCT-01).
- [ ] In castle mode, an enemy on floor 10 has strictly more HP than the same enemy id on floor 1 of the same run (DCT-02).
- [ ] Each dungeon exposes at least 3 difficulty tiers, and selecting tier 2 yields strictly higher enemy HP and `lootBonus` than tier 1 (DCT-03).
- [ ] `EndlessDifficulty.hp_multiplier(999999) <= 25.0` and `damage_multiplier(999999) <= 12.0` (DCT-04).
- [ ] `mix_seed(s, f)` and `mix_seed(s, f + 1)` differ in at least 10 bit positions for 1000 sampled `(s, f)` pairs (DCT-05).
- [ ] GDScript `mix_seed` equals the C# implementation for 1000 sampled pairs (DCT-05).
- [ ] `dungeon_catalog.gd` contains no display-name string (DCT-06).
- [ ] `find_stairs_room_id(definition)` and the room that receives the stair lever are always the same room (DCT-07).
- [ ] `RunFloorConfig.MAX_SECRETS_PER_FLOOR` no longer exists; `RoomGraphConfig.max_secrets` comes from the biome file (DCT-09).
- [ ] A save written before the migration loads with `dungeon_unlocked_count` equal to its old `dungeon_max_tier` and every `dungeon_tier_<id>` at 1 (save format).

## Validation

Extend `apps/game/client/scripts/validation/suites/m5_suite.gd` (which already owns the tier tests at `:392-442`):

- `test_skip_requires_item` — clear the inventory, call `start_endless_run(1, "skip_500_floors")`, assert the run did not start and `last_hub_message` is set; then add the item and assert the run starts at floor 501 and the item count dropped by 1.
- `test_difficulty_tier_selection` — for each dungeon, assert `difficultyTiers.size() >= 3` and that `hpMult` and `lootBonus` are strictly increasing.
- `test_tier_unlock_per_dungeon` — clear tier 1 of `forgotten_castle`; assert `dungeon_tier_forgotten_castle == 2` and `dungeon_unlocked_count == 2`.
- `test_catalog_from_data` — assert `DungeonCatalog.all_dungeon_ids()` matches the file listing of `content/dungeons/`, and that `get_display_name` delegates to `BiomeRegistry`.

Extend `apps/game/client/scripts/validation/suites/m7_suite.gd` (which owns the floor-config tests at `:240-274`):

- `test_endless_curve_bounded` — assert `hp_multiplier` and `damage_multiplier` are monotonically non-decreasing over floors 1..2000 and never exceed their soft caps at floor 999999.
- `test_floor_seed_avalanche` — assert the Hamming distance between `mix_seed(s, f)` and `mix_seed(s, f + 1)` is at least 10 for 1000 sampled pairs.
- `test_secret_cap_from_biome` — assert the generated secret count never exceeds the biome's `maxSecrets` for 200 seeds x 10 biomes.

Extend `apps/game/client/scripts/validation/suites/dungeon_suite.gd`:

- `test_floor_scaling_curve` — build floors 1 and 10 of one castle run; assert the same enemy id's `max_health` differs by the expected ratio.
- `test_stair_lookup_agreement` — for 200 seeds x 10 biomes, assert `find_stairs_room_id(definition)` equals the room id of the room holding the stair lever.

Extend `apps/game/client/scripts/validation/suites/cross_stack_parity_suite.gd`:

- `test_floor_seed_parity` — compare GDScript `mix_seed` against a checked-in fixture emitted by the C# implementation.

## Related

- [`../existing_codebase/dungeon-catalog-tiers.md`](../existing_codebase/dungeon-catalog-tiers.md)
- [`local-procgen.md`](local-procgen.md) — LPG-05 seed hashing, tier seed derivation
- [`biome-registry.md`](biome-registry.md) — BIO-01 biome kit, `maxSecrets`, display names
- [`procgen-placements.md`](procgen-placements.md) — threat budget by tier, RNG streams
- [`dungeon-builder.md`](dungeon-builder.md) — applies the multipliers, stair lever lookup
- [`room-graph-procgen.md`](room-graph-procgen.md) — RGP-05 parity assertions
- [`run-flow.md`](run-flow.md) — run modifiers, skip path, unlock-on-clear
- [`save-migrator.md`](save-migrator.md), [`local-save.md`](local-save.md) — flag migration
- [`ui/hub_vendors.md`](ui/hub_vendors.md), [`ui/run_flow_ui.md`](ui/run_flow_ui.md) — tier selector UI
- [`loot-and-equipment.md`](loot-and-equipment.md) — `lootBonus` consumer
