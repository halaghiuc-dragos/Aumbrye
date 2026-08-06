# Progression service — improvement plan

## Status: FINISHED

## Current state
XP, levels, talent ranks, and death shards work on the live path; the XP curve keys match `ProgressionService`, all four aptitude economy talents apply at runtime, and abandon honors `abandonedXpFraction`. See [`../existing_codebase/progression-service.md`](../existing_codebase/progression-service.md). Curve alignment shared with [`content-data.md`](content-data.md) **CDT-01** / **CDT-03**.

## Gaps
| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| PRG-01 | P0 | `calculate_run_xp` ignored authored economy keys | **FINISHED** |
| PRG-02 | P0 | Talents `apt_3`–`apt_6` had no runtime consumer | **FINISHED** |
| PRG-03 | P1 | `talentPointsPerLevel` on `tree.json` was unread | **FINISHED** |
| PRG-04 | P1 | `abandonedXpFraction` never applied on abandon | **FINISHED** |
| PRG-05 | P2 | `grant_xp` ignored `reason` for analytics/achievements | **FINISHED** |

## Target design

### Curve alignment (same as CDT-01)
`xp_curve.json` uses the kill/boss/escape formula already used by results copy. Keys: `baseXpPerKill`, `bossBonusXp`, `escapeBonusXp`, `talentPointsPerLevel`, `deathXpFraction`, `abandonedXpFraction`, `levels`.

### Talent effects
| Stat | Wired into |
|------|-----------|
| `xpGain` | `grant_xp`: `amount = int(amount * (1.0 + totals.xpGain))` before apply |
| `goldFind` | `CharacterService.add_gold` multiplier |
| `lootQuality` | `AffixRoller.rarity_weights` bonus on rare+ (stacks with mode bonus) |
| `cooldownReduction` | `WeaponController.get_weapon_art_cooldown_duration` scale |

### Single talentPointsPerLevel source
Read only from `_curve`; removed from `tree.json` / `talent-tree.v1.json`.

### Abandon
`RunFlow.abandon_active_run` grants `apply_abandon_xp_fraction(full_xp)` when fraction > 0 (authored `0` → no XP, honest).

### XP grant analytics
`grant_xp` emits `xp_granted(amount, reason)`; `AchievementService` records `xp_granted_<reason>` flags on `CharacterService` for future achievement predicates.

## Work plan

1. **Rewrite xp_curve.json + schema to runtime keys; update progression_suite** — Closes PRG-01, PRG-03, CDT-01/03. **Done**
2. **Apply `xpGain` in `grant_xp`** — **Done**
3. **Apply `lootQuality` in AffixRoller** — **Done**
4. **Apply `goldFind` on gold grants** — **Done**
5. **Apply `cooldownReduction` on weapon art cooldown** — **Done**
6. **Honor `abandonedXpFraction`; use `reason` for ACH hooks** — **Done**

## Data and schema changes

| File | Change |
|------|--------|
| `content/progression/xp_curve.json` | `baseXpPerKill`, `bossBonusXp`, `escapeBonusXp`, `talentPointsPerLevel`; `deathXpFraction`, `abandonedXpFraction`, `levels` |
| `content/schemas/xp-curve.v1.json` | Match required properties |
| `content/talents/tree.json` | `talentPointsPerLevel` removed |
| `content/schemas/talent-tree.v1.json` | No `talentPointsPerLevel` |

No save migrator for XP math change (existing XP totals stay; future grants differ).

## Acceptance criteria
- [x] Setting `baseXpPerKill` to `50` doubles `calculate_run_xp(2, false, false)` vs `25`. (PRG-01)
- [x] With `apt_4` unlocked, `grant_xp(100)` stores more than 100 XP by the authored `valuePerRank`. (PRG-02)
- [x] With `apt_3` unlocked, rare+ roll weights increase vs baseline in a unit test. (PRG-02)
- [x] With `apt_5` unlocked, a +100 gold grant exceeds raw amount by `goldFind` bonus. (PRG-02)
- [x] With `apt_6` unlocked, weapon art cooldown is shorter by authored fraction. (PRG-02)
- [x] Tree JSON no longer required to carry `talentPointsPerLevel`. (PRG-03)
- [x] Abandon grants `floor(full * abandonedXpFraction)` via `apply_abandon_xp_fraction`. (PRG-04)

## Validation
`progression_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `prog.curve.keys_match_reader` | Curve has `baseXpPerKill`; calculate uses file value |
| `prog.talent.xp_gain_applies` | Unlock apt_4, grant_xp, assert gained > raw |
| `prog.talent.loot_quality_shifts_weights` | `rarity_weights` with lootQuality bonus |
| `prog.talent.gold_find_applies` | apt_5 unlock, add_gold delta > raw |
| `prog.talent.cooldown_reduction_applies` | Weapon art cooldown < base with reduction |
| `prog.talent.each_node_has_consumer` | Static map talent effect stats → applicator files |
| `prog.abandon_xp_fraction` | `apply_abandon_xp_fraction` matches curve; run_flow wired |
| `prog.xp_granted_reason_hook` | Reason recorded on CharacterService flag |

## Related
- Existing state: [`../existing_codebase/progression-service.md`](../existing_codebase/progression-service.md)
- [`content-data.md`](content-data.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`run-flow.md`](run-flow.md), [`achievements-meta.md`](achievements-meta.md)
