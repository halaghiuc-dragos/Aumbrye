# Loot and equipment — improvement plan

## Status: FINISHED

## Current state

Affix rarity **weights** and **counts** from `content/affixes/rarity_rules.json` drive `AffixRoller`. **`LOO-01 FINISHED`**: pool filters by `itemTypes`, weighted selection, values from `tiers[rarity]`. Castle chests, pickups, and merchant gear route through `InventoryService.add_loot` with affix rolling for equipment. `forgotten_castle` chest tables load from `content/loot/tables/forgotten_castle.json`. See [`../existing_codebase/loot-and-equipment.md`](../existing_codebase/loot-and-equipment.md).



## Gaps

| ID | Sev | Gap | Evidence |

|----|-----|-----|----------|

| LOO-01 | P0 | ~~`AffixRoller` ignores tiers~~ **FINISHED** — `_roll_tier_value`, `_build_affix_pool`, weighted pick | was `affix_roller.gd:30-38` |

| LOO-02 | P0 | ~~Castle chests, pickups, and merchant gear never call the roller~~ **FINISHED** — `add_loot` in `inventory_service.gd`; `loot_chest.gd`, `world_item_pickup.gd`, `merchant_service.gd` | was `loot_chest.gd:72`, `world_item_pickup.gd:51` |

| LOO-03 | P1 | ~~No per-enemy/biome equipment drop tables~~ **FINISHED (start)** — `content/loot/tables/forgotten_castle.json` + `LootTableLoader`; `BiomeRegistry` resolves external tables | was `global_drop_service.gd` only |

| LOO-04 | P1 | ~~Elemental affix stats don't reach combat~~ **FINISHED** — `equipment.gd` folds `FLAT_DAMAGE_STAT_KEYS` affixes into `bonusDamage` | was `equipment.gd:211-219` |

| LOO-05 | P2 | ~~`mythic` still in rarity_rules~~ **FINISHED** — `rarity_rules.json` uses `aumbral` only; `validate.mjs` rejects `mythic` key | was `rarity_rules.json:9-19` |



## Target design



### Honest roller

```gdscript

static func roll_instance(item_id: String, roll_seed: int = -1, forced_rarity: String = "", run_mode: String = "") -> Dictionary:

    # 1. rarity from weights (existing)

    # 2. count from affixCounts (existing)

    # 3. build pool: prefixes+suffixes where itemTypes contains def.itemType (or empty itemTypes = all)

    # 4. weighted sample without replacement using weight

    # 5. value = rng from tiers[normalize(rarity)] or tiers.aumbral fallback from mythic

```



Determinism: same `roll_seed` ⇒ identical instance (keep `roll_identical` contract used by suites).



### Castle loot path

Route equipment grants through `InventoryService.add_loot` (INV plan). Chests may mark entries `"roll": true` or rely on itemType.



### Drop tables (chosen)

Add `content/loot/tables/<biome_id>.json` with weighted `itemId` entries for elite/boss/chest fill, validated by `validate.mjs`. Replace hardcoded lists in `procgen_loot_tables.gd` over time. Rejected: only code tables forever — they already drift from catalog.



## Work plan



1. **Rewrite affix selection to use tiers/itemTypes/weight** — keep weight/count rarity behaviour. Closes LOO-01; aligns CDT-02.

2. **Wire castle equipment grants through roller (INV-01 / LOO-02)** — **DONE**.

3. **Add biome loot table JSON + migrate one biome from ProcgenLootTables** — **DONE** (`forgotten_castle`).

4. **Assert elemental affix stats apply in WeaponController path** — **DONE** (`equipment.gd` + `inventory_suite.gd`).

5. **Drop mythic weight key once content clean** — **DONE**.



## Data and schema changes



- Affix schema already correct; no change required for LOO-01.

- `content/schemas/loot-table.v1.json` + `validate.mjs` mapping for `content/loot/tables/*.json`.

- Optional chest placement key `roll`; optional item def `rollAffixes`.



## Acceptance criteria

- [x] Forced `legendary` roll of a weapon never attaches an armor-only affix; values fall inside `tiers.legendary`. (LOO-01)

- [x] Castle chest equipment grant produces `affixes` array when rarity count > 0. (LOO-02)

- [x] At least one biome loads chest items from JSON table, not only `procgen_loot_tables.gd` literals. (LOO-03)

- [x] Cross-stack / inventory suite: identical seed ⇒ identical affix ids and values after the rewrite. (LOO-01)

- [x] Elemental affix `fireDamage` folds into `bonusDamage` for combat. (LOO-04)



## Validation

| Suite | Checks |

|-------|--------|

| `inventory_suite.gd` | Tier range + itemType filter; `add_loot` rolls equipment; external loot table; elemental affix → `bonusDamage` |

| `cross_stack_parity_suite.gd` | Determinism after roller fix |

| `validate.mjs` | Loot table itemIds ∈ catalog; no `mythic` in affix content |



## Related

- Existing state: [`../existing_codebase/loot-and-equipment.md`](../existing_codebase/loot-and-equipment.md)

- [`inventory-service.md`](inventory-service.md), [`content-data.md`](content-data.md), [`waves-run.md`](waves-run.md)

