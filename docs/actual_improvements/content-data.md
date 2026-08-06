# Content data — improvement plan

## Status: FINISHED

## Current state
`content/` plus `content/schemas/*.v1.json` is the authored contract; CI validates with Ajv; the client loads through `ContentLoader` with debug structural checks via `ContentSchemaValidator`. See [`../existing_codebase/content-data.md`](../existing_codebase/content-data.md).

## Gaps
| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| CDT-01 | P0 | `xp_curve.json` / `xp-curve.v1.json` fields do not match `ProgressionService.calculate_run_xp` keys | **FINISHED** |
| CDT-02 | P0 | Affix schema requires per-rarity `tiers`, but `AffixRoller` ignored `tiers` | **FINISHED** |
| CDT-03 | P1 | `talentPointsPerLevel` lived on `tree.json` but points were read from the XP curve dict | **FINISHED** |
| CDT-04 | P1 | Schema filename `item-instance.v1.json` described definitions; rolled instances had no schema | **FINISHED** |
| CDT-05 | P1 | Schemas and content advertised `mythic` alongside `aumbral` after client rename | **FINISHED** |
| CDT-06 | P2 | No runtime or headless Godot check that loaded JSON matches schema | **FINISHED** |

## Target design

### Align XP curve (chosen)
`xp_curve.json` and `xp-curve.v1.json` use the keys `ProgressionService` already reads:

```json
{
  "schemaVersion": 1,
  "baseXpPerKill": 25,
  "bossBonusXp": 150,
  "escapeBonusXp": 50,
  "deathXpFraction": 0.5,
  "abandonedXpFraction": 0,
  "talentPointsPerLevel": 1,
  "levels": [ ... ]
}
```

`talentPointsPerLevel` lives solely on the curve; removed from `tree.json` / `talent-tree.v1.json`.

### Affix roller respects `tiers`
`AffixRoller.roll_instance`:
1. Filters pool by `itemTypes` vs item def `itemType`.
2. Weight-picks using `weight`.
3. Samples `value` from `tiers[rarity].min/max` (normalizes mythic→aumbral when looking up).

### Schema clarity
- `item-definition.v1.json` — item definitions (formerly misnamed `item-instance`).
- `item-instance-roll.v1.json` — `{ instanceId, itemId, quantity, rarity, affixes[], rollSeed, … }`.
- `validate.mjs` maps `content/items/**` → `item-definition.v1.json`; fixture roll sample validates against roll schema.

### Rarity cleanup
`mythic` removed from content/schemas; `RarityRegistry.LEGACY_ALIASES` keeps mythic→aumbral for one-release alias grace (tested in `m7_suite.gd`).

### Runtime schema checks
`ContentLoader.load_json` calls `ContentSchemaValidator.validate_loaded` in debug builds. `AffixRoller` validates rolled instances in debug builds. Full JSON Schema validation remains in CI (`validate.mjs`).

## Work plan
1. **Align XP curve JSON and schema** — `content/progression/xp_curve.json`, `content/schemas/xp-curve.v1.json`; keys match `ProgressionService.calculate_run_xp` / `_talent_points_from_level` (CDT-01, CDT-03).
2. **Remove `talentPointsPerLevel` from talent tree** — `content/talents/tree.json`, `content/schemas/talent-tree.v1.json` (CDT-03).
3. **Rewrite `AffixRoller`** — `affix_roller.gd`: `itemTypes` filter, weighted pick, `_roll_tier_value` from `tiers[rarity]` (CDT-02).
4. **Rename item schema + add roll schema** — `item-definition.v1.json`, `item-instance-roll.v1.json`, delete `item-instance.v1.json`; `fixtures/item_instance_roll_sample.v1.json`; `validate.mjs` mapping (CDT-04).
5. **Rarity cleanup** — `aumbral` in affix/item schemas and content; `RarityRegistry.LEGACY_ALIASES` for `mythic` (CDT-05).
6. **Debug runtime validation** — `content_schema_validator.gd`; wire from `content_loader.gd` and `affix_roller.gd`; extend `progression_suite.gd` / `inventory_suite.gd` (CDT-06).

## Data and schema changes

| File | Change |
|------|--------|
| `content/progression/xp_curve.json` | Runtime keys: `baseXpPerKill`, `bossBonusXp`, `escapeBonusXp`, `talentPointsPerLevel` |
| `content/schemas/xp-curve.v1.json` | Match |
| `content/talents/tree.json` / `talent-tree.v1.json` | `talentPointsPerLevel` removed |
| `content/schemas/item-definition.v1.json` | Renamed from item-instance |
| `content/schemas/item-instance-roll.v1.json` | New |
| Affix / item rarity enums | `aumbral` only in authored content |

## Acceptance criteria
- [x] Editing `baseXpPerKill` in `xp_curve.json` changes `calculate_run_xp(1, false, false)` without code edits. (CDT-01)
- [x] Rolling a `legendary` iron sword samples values from `tiers.legendary`, not 1–3. (CDT-02)
- [x] Changing only `tree.json` `talentPointsPerLevel` does not change available points; changing the curve field does. (CDT-03)
- [x] `validate.mjs` maps item definition files to `item-definition.v1.json`; a fixture roll instance validates against the roll schema. (CDT-04)
- [x] No content file under `content/items` or `content/affixes` requires the string `mythic` except a documented alias test. (CDT-05)
- [x] Debug builds validate hot-path content structure via `ContentSchemaValidator`. (CDT-06)

## Validation
| Suite | Assertions |
|-------|------------|
| `progression_suite.gd` | Curve has `baseXpPerKill`; grant math matches file; talent points from curve |
| `inventory_suite.gd` | Affix value within tier range for forced legendary `iron_sword` |
| `validate.mjs` | Fails if xp-curve still has only old keys; affix content has no `mythic` tier keys |

## Related
- Existing state: [`../existing_codebase/content-data.md`](../existing_codebase/content-data.md)
- [`content-catalog.md`](content-catalog.md), [`progression-service.md`](progression-service.md), [`loot-and-equipment.md`](loot-and-equipment.md)
