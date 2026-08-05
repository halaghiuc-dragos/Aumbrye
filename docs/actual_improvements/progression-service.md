# Progression service — improvement plan

## Current state
XP, levels, talent ranks, and death shards work on the live path, but the authored XP economy keys do not match the reader, and four aptitude talents only change the talents UI math. See [`../existing_codebase/progression-service.md`](../existing_codebase/progression-service.md). Cross-link content skew: [`content-data.md`](content-data.md) **CDT-01** / **CDT-03**.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PRG-01 | P0 | `calculate_run_xp` ignores authored `baseXpPerRun` / `tierXpBonus`; uses missing keys with hardcoded defaults | `xp_curve.json:3-5`, `progression_service.gd:61-68` |
| PRG-02 | P0 | Talents `apt_3`–`apt_6` (`lootQuality`, `xpGain`, `goldFind`, `cooldownReduction`) have no runtime consumer | `tree.json:139-164`; grep under `scripts/` only hits `equipment.gd` / `talents_ui.gd` |
| PRG-03 | P1 | `talentPointsPerLevel` on `tree.json` is unread; curve default silently wins | `tree.json:3`, `progression_service.gd:187-189` |
| PRG-04 | P1 | `abandonedXpFraction` in curve is never applied on abandon | `xp_curve.json:6`; `RunFlow.abandon_active_run` grants no XP |
| PRG-05 | P2 | `grant_xp` ignores `reason` for analytics/achievements (`talent_spender` etc.) | `progression_service.gd:45` `_reason` unused |

## Target design

### Curve alignment (same as CDT-01)
Make JSON match the kill/boss/escape formula already used by results copy, **or** change the formula to `baseXpPerRun + tier*tierXpBonus + kills*…` with an explicit design choice. Chosen: **keep kill/boss/escape formula** and rewrite the JSON/schema — results screens and mental model already assume kill-scaled XP.

Add optional `tierXpBonusPerFloor` later; do not leave dead keys.

### Talent effects that do work
| Stat | Wire into |
|------|-----------|
| `xpGain` | `grant_xp`: `amount = int(amount * (1.0 + totals.xpGain))` before apply |
| `goldFind` | `CharacterService.add_gold` / coin rewards multiplier |
| `lootQuality` | `AffixRoller._pick_rarity` weight bonus on rare+ (stack with mode bonus) |
| `cooldownReduction` | Weapon art / skill cooldown remaining scale on `WeaponController` |

Rejected: remove the four nodes from the tree — the UI already sells them; shipping inert nodes is the P0 lie.

### Single talentPointsPerLevel source
Read only from `_curve` after CDT-01 puts the key there; remove from tree schema.

### Abandon
Either apply `abandonedXpFraction` (likely 0 → grant nothing, honest) or delete the key from schema.

## Work plan

1. **Rewrite xp_curve.json + schema to runtime keys; update progression_suite** — Closes PRG-01, PRG-03, CDT-01/03.
2. **Apply `xpGain` in `grant_xp`** — Closes part of PRG-02.
3. **Apply `lootQuality` in AffixRoller / add_loot path** — depends on LOO/INV; Closes part of PRG-02.
4. **Apply `goldFind` on gold/coin grants** — Closes part of PRG-02.
5. **Apply `cooldownReduction` on weapon art cooldown** — Closes remainder of PRG-02.
6. **Honor or delete `abandonedXpFraction`; use `_reason` for ACH hooks** — Closes PRG-04, PRG-05.

## Data and schema changes

| File | Change |
|------|--------|
| `content/progression/xp_curve.json` | `baseXpPerKill`, `bossBonusXp`, `escapeBonusXp`, `talentPointsPerLevel`; keep `deathXpFraction`, `levels` |
| `content/schemas/xp-curve.v1.json` | Match required properties |
| `content/talents/tree.json` | Remove unused top-level `talentPointsPerLevel` |
| `content/schemas/talent-tree.v1.json` | Drop required `talentPointsPerLevel` |

No save migrator for XP math change (existing XP totals stay; future grants differ).

## Acceptance criteria
- [ ] Setting `baseXpPerKill` to `50` doubles `calculate_run_xp(2, false, false)` vs `25`. (PRG-01)
- [ ] With `apt_4` unlocked, `grant_xp(100)` stores more than 100 XP by the authored `valuePerRank`. (PRG-02)
- [ ] With `apt_3` unlocked, rare+ roll weights increase vs baseline in a unit test. (PRG-02)
- [ ] With `apt_5` unlocked, a +10 gold grant becomes 10×(1+bonus). (PRG-02)
- [ ] With `apt_6` unlocked, weapon art cooldown is shorter by authored fraction. (PRG-02)
- [ ] Tree JSON no longer required to carry `talentPointsPerLevel`. (PRG-03)
- [ ] Abandon either grants `floor(full * abandonedXpFraction)` or the key is gone from schema. (PRG-04)

## Validation
Extend `progression_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `prog.curve.keys_match_reader` | Curve has `baseXpPerKill`; calculate uses file value |
| `prog.talent.xp_gain_applies` | Unlock apt_4, grant_xp, assert gained > raw |
| `prog.talent.loot_quality_shifts_weights` | Mock roller weights with apt_3 |
| `prog.talent.each_node_has_consumer` | Static map talent effect stats → known applicator symbols |

## Related
- Existing state: [`../existing_codebase/progression-service.md`](../existing_codebase/progression-service.md)
- [`content-data.md`](content-data.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`run-flow.md`](run-flow.md), [`achievements-meta.md`](achievements-meta.md)
