# Loot and equipment — improvement plan

## Current state
Affix rarity **weights** and **counts** from `content/affixes/rarity_rules.json` drive `AffixRoller` when something actually rolls. See [`../existing_codebase/loot-and-equipment.md`](../existing_codebase/loot-and-equipment.md). Authored per-affix `tiers`, `itemTypes`, and `weight` are ignored, so rolled values are flat 1–3 and armor can roll weapon-only affixes. Castle mode never rolls — only waves uses the roller. That makes the affix content largely ornamental for the primary play path.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| LOO-01 | P0 | `AffixRoller` ignores `tiers` / `itemTypes` / `weight` — rarity tables for **values** and pool filtering are fake relative to content | `affix_roller.gd:30-38`; `prefixes.json` `tiers` / `itemTypes` / `weight` |
| LOO-02 | P0 | Castle chests, pickups, and merchant gear never call the roller | `loot_chest.gd:72`, `world_item_pickup.gd:51`; cross-link **INV-01** |
| LOO-03 | P1 | No per-enemy/biome equipment drop tables — only skip consumables via `global_drops.json` | `global_drop_service.gd`; enemy JSON has no consumed `dropTable` |
| LOO-04 | P1 | Flat damage affix stats (`fireDamage`, etc.) fold only through equipment `bonusDamage` from **base** def stats; affix `stat` strings must match `STAT_KEYS` or they apply into totals loosely — verify elemental affixes land in combat | `equipment.gd:150-160`, `CombatStatModifiers.flat_damage_bonus` |
| LOO-05 | P2 | `mythic` still in rarity_rules with weight 0 beside `aumbral` | `rarity_rules.json:9-19` |

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
2. **Wire castle equipment grants through roller (INV-01 / LOO-02)**.
3. **Add biome loot table JSON + migrate one biome from ProcgenLootTables** — Closes LOO-03 start.
4. **Assert elemental affix stats apply in WeaponController path** — Closes LOO-04.
5. **Drop mythic weight key once content clean** — Closes LOO-05.

## Data and schema changes

- Affix schema already correct; no change required for LOO-01.
- New `content/schemas/loot-table.v1.json` + `validate.mjs` mapping.
- Optional chest placement key `roll`.

## Acceptance criteria
- [ ] Forced `legendary` roll of a weapon never attaches an armor-only affix; values fall inside `tiers.legendary`. (LOO-01)
- [ ] Castle chest equipment grant produces `affixes` array when rarity count > 0. (LOO-02)
- [ ] At least one biome loads chest items from JSON table, not only `procgen_loot_tables.gd` literals. (LOO-03)
- [ ] Cross-stack / inventory suite: identical seed ⇒ identical affix ids and values after the rewrite. (LOO-01)

## Validation
| Suite | Checks |
|-------|--------|
| `inventory_suite.gd` | Tier range + itemType filter |
| `cross_stack_parity_suite.gd` | Determinism after roller fix |
| `validate.mjs` | Loot table itemIds ∈ catalog |

## Related
- Existing state: [`../existing_codebase/loot-and-equipment.md`](../existing_codebase/loot-and-equipment.md)
- [`inventory-service.md`](inventory-service.md), [`content-data.md`](content-data.md), [`waves-run.md`](waves-run.md)
