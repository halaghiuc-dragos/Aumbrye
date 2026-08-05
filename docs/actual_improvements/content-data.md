# Content data — improvement plan

## Current state
`content/` plus `content/schemas/*.v1.json` is the authored contract; CI validates with Ajv; the client loads blindly through `ContentLoader`. See [`../existing_codebase/content-data.md`](../existing_codebase/content-data.md). Several schemas describe fields the runtime never reads, and several runtime keys are absent from schemas — so CI can pass while the play path ignores the authored numbers.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CDT-01 | P0 | `xp_curve.json` / `xp-curve.v1.json` fields do not match `ProgressionService.calculate_run_xp` keys — authored `baseXpPerRun` never applied | `xp_curve.json:3-6`, `xp-curve.v1.json:10-14`, `progression_service.gd:61-68` |
| CDT-02 | P0 | Affix schema requires per-rarity `tiers`, but `AffixRoller` rolls `min`/`max` on the affix root (defaults 1–3), ignoring `tiers` | `affix-definition.v1.json:8,19-28`, `affix_roller.gd:35` |
| CDT-03 | P1 | `talentPointsPerLevel` lives on `tree.json` (schema-required) but points are read from the XP curve dict | `talent-tree.v1.json:8`, `tree.json:3`, `progression_service.gd:187-189` |
| CDT-04 | P1 | Schema filename `item-instance.v1.json` describes definitions; rolled inventory instances have no dedicated schema | `item-instance.v1.json:4-5`, inventory slots built in `grid_inventory.gd` / `affix_roller.gd:40-47` |
| CDT-05 | P1 | Schemas and content still advertise `mythic` alongside `aumbral` after client rename | `item-instance.v1.json:30`, `rarity_rules.json:9,18`, `rarity_registry.gd:10-12` |
| CDT-06 | P2 | No runtime or headless Godot check that loaded JSON matches schema — only Node CI | `content_loader.gd:19-30` |

## Target design

### Align XP curve (chosen)
Update `xp_curve.json` and `xp-curve.v1.json` to the keys code already reads:

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

Rejected: change GDScript to read `baseXpPerRun` — that formula does not match the kill/boss/escape breakdown already used by results screens and tests.

Move `talentPointsPerLevel` solely onto the curve (CDT-03): keep it on the tree as optional deprecated, or remove from tree schema in the same bump.

### Affix roller respects `tiers`
`AffixRoller.roll_instance` must:
1. Filter pool by `itemTypes` vs item def `itemType`.
2. Weight-pick using `weight`.
3. Sample `value` from `tiers[rarity].min/max` (normalize mythic→aumbral when looking up).

### Schema clarity
Rename / split:
- `item-definition.v1.json` (today's item-instance schema).
- `item-instance-roll.v1.json` for `{ instanceId, itemId, quantity, rarity, affixes[], rollSeed, … }`.

Migrate `validate.mjs` path mapping in the same PR.

### Rarity cleanup
Drop `mythic` from enums once content files use `aumbral` only; keep a one-release alias in `RarityRegistry`.

## Work plan

1. **Bump xp-curve schema + JSON to runtime keys; add `talentPointsPerLevel` to curve** — update `progression_suite` expectations. Closes CDT-01, CDT-03.
2. **Fix AffixRoller to use `tiers`, `itemTypes`, `weight`** — see loot plan LOO-*; schema already correct. Closes CDT-02.
3. **Rename item-instance schema → item-definition; add roll-instance schema; update validate.mjs** — Closes CDT-04.
4. **Remove mythic from content + schemas after alias grace** — Closes CDT-05.
5. **Optional debug assert** — when `OS.is_debug_build()`, sample-validate hot paths or document that CI remains the gate. Closes CDT-06 at P2 level.

## Data and schema changes

| File | Change |
|------|--------|
| `content/progression/xp_curve.json` | Replace unused keys with `baseXpPerKill`, `bossBonusXp`, `escapeBonusXp`, `talentPointsPerLevel` |
| `content/schemas/xp-curve.v1.json` | Match |
| `content/talents/tree.json` / `talent-tree.v1.json` | Drop or deprecate `talentPointsPerLevel` |
| `content/schemas/item-definition.v1.json` | Rename from item-instance |
| `content/schemas/item-instance-roll.v1.json` | New |
| Affix / item rarity enums | Prefer `aumbral` only |

No save migrator unless achievement/loot ids change (owned by ACH/LOO).

## Acceptance criteria
- [ ] Editing `baseXpPerKill` in `xp_curve.json` changes `calculate_run_xp(1, false, false)` without code edits. (CDT-01)
- [ ] Rolling a `legendary` iron sword samples values from `tiers.legendary`, not 1–3. (CDT-02)
- [ ] Changing only `tree.json` `talentPointsPerLevel` does not change available points; changing the curve field does. (CDT-03)
- [ ] `validate.mjs` maps item definition files to `item-definition.v1.json`; a fixture roll instance validates against the roll schema. (CDT-04)
- [ ] No content file under `content/items` or `content/affixes` requires the string `mythic` except a documented alias test. (CDT-05)

## Validation
| Suite | Assertions |
|-------|------------|
| `progression_suite.gd` | Assert curve has `baseXpPerKill`; grant math matches file |
| `inventory_suite.gd` / cross-stack | Affix value within tier range for forced rarity |
| `validate.mjs` | Fails if xp-curve still has only old keys |

## Related
- Existing state: [`../existing_codebase/content-data.md`](../existing_codebase/content-data.md)
- [`content-catalog.md`](content-catalog.md), [`progression-service.md`](progression-service.md), [`loot-and-equipment.md`](loot-and-equipment.md)
