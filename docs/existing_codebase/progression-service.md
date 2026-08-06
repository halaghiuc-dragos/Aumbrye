# Progression service

`ProgressionService` is the autoload for permanent XP, level, and talents. Run outcomes call `grant_xp` / `calculate_run_xp` / `apply_death_xp_fraction` / `apply_abandon_xp_fraction`. Recoverable death XP uses `XpShardPickup` spawned by `castle_run.gd`. The talent tree defines 18 nodes across three branches; all aptitude stats have runtime consumers.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/progression/progression_service.gd` | XP, level, talents, save dict, `xp_granted` signal |
| `apps/game/client/scripts/progression/xp_shard_pickup.gd` | World interact → `grant_xp` + clear shard flag |
| `content/progression/xp_curve.json` | Level thresholds + run XP economy keys |
| `content/talents/tree.json` | Three branches × six nodes |
| `apps/game/client/scripts/dungeon/castle_run.gd` | Spawns `XpShardPickup` from `RunFlow` shard meta |
| `apps/game/client/scripts/combat/combat_stat_modifiers.gd` | Applies combat talent stats |
| `apps/game/client/scripts/loot/affix_roller.gd` | `lootQuality` → rare+ rarity weight bonus |
| `apps/game/client/scripts/save/character_service.gd` | `goldFind` → `add_gold` multiplier |
| `apps/game/client/scripts/combat/weapon_controller.gd` | `cooldownReduction` → weapon art cooldown scale |
| `apps/game/client/scripts/meta/achievement_service.gd` | Listens to `xp_granted` for per-reason analytics flags |
| `apps/game/client/scripts/app/run_flow.gd` | Escape/death/abandon XP grants |

## How it works

### XP and level
Loads `XP_CURVE_PATH` into `_curve` / `_levels` (`progression_service.gd:161-163`).

`grant_xp(amount, reason)` (`progression_service.gd:46-66`) multiplies by `1.0 + xpGain` talent total, adds XP, `_recalc_level()`, emits `progression_changed`, and when `reason` is non-empty emits `xp_granted(amount, reason)`.

`_recalc_level` (`progression_service.gd:177-184`) sets level to the highest `levels[].level` whose `xpRequired` ≤ current XP.

`calculate_run_xp(kills, boss_defeated, escaped)` (`progression_service.gd:69-76`):

```text
kills * baseXpPerKill (25 in file)
+ bossBonusXp (150) if boss
+ escapeBonusXp (50) if escaped
```

`apply_death_xp_fraction` uses `deathXpFraction` (0.5) (`progression_service.gd:79-81`).

`apply_abandon_xp_fraction` uses `abandonedXpFraction` (0 in file → no abandon XP) (`progression_service.gd:84-86`).

Talent points available: `(level - 1) * talentPointsPerLevel` from curve (`progression_service.gd:195-197`).

### Talents
`unlock_talent` checks max rank, cost, and `requires` (`progression_service.gd:92-116`). `get_talent_stat_totals` sums `effects[].stat` × `valuePerRank` × rank (`progression_service.gd:119-139`).

Tree branches (`tree.json`):

| Branch | Nodes | Stats |
|--------|-------|-------|
| `arms` | arms_1–6 | `physicalDamage`, `staminaCostReduction`, `critChance`, `poiseDamage` |
| `guard` | guard_1–6 | `maxHealth`, `armor`, `blockReduction`, `poise`, `damageReduction` |
| `aptitude` | apt_1–6 | `staminaRegen`, `moveSpeed`, `lootQuality`, `xpGain`, `goldFind`, `cooldownReduction` |

### Which talent stats have runtime effect

| Stat | Applied? | Evidence |
|------|----------|----------|
| `physicalDamage` | Yes | `CombatStatModifiers.damage_multiplier` (`combat_stat_modifiers.gd:7-10`) |
| `staminaCostReduction` | Yes | `stamina_cost_multiplier` (`combat_stat_modifiers.gd:33-34`) |
| `critChance` | Yes | `crit_chance` (`combat_stat_modifiers.gd:37-38`) |
| `poiseDamage` | Yes | `poise_damage_multiplier` (`combat_stat_modifiers.gd:29-30`) |
| `maxHealth` | Yes | `Health.configure` via merged stats (`inventory_service.gd:188-190`) |
| `armor` | Yes | `incoming_damage_multiplier` (`combat_stat_modifiers.gd:44`) + meta |
| `blockReduction` | Yes | `Guard.set_combat_stat_modifiers` (`guard.gd:97-98`) |
| `poise` | Yes | `max_poise_bonus` (`combat_stat_modifiers.gd:60-61`) |
| `damageReduction` | Yes | `incoming_damage_multiplier` + player meta |
| `staminaRegen` | Yes | `stamina_regen_multiplier` (`combat_stat_modifiers.gd:56-57`) |
| `moveSpeed` | Yes | `move_speed_multiplier` (`combat_stat_modifiers.gd:64-67`) |
| `lootQuality` | Yes | `AffixRoller.rarity_weights` rare+ weight bonus (`affix_roller.gd:110-125`) |
| `xpGain` | Yes | `grant_xp` multiplier (`progression_service.gd:49-50`) |
| `goldFind` | Yes | `CharacterService.add_gold` multiplier (`character_service.gd:73-80`) |
| `cooldownReduction` | Yes | `WeaponController.get_weapon_art_cooldown_duration` (`weapon_controller.gd:208-216`) |

### Abandon XP
`RunFlow.abandon_active_run` (`run_flow.gd:326-338`) computes full run XP, applies `apply_abandon_xp_fraction`, and grants with reason `"abandon"` when result > 0.

### XP shard
`RunFlow` stores recoverable XP on death; `castle_run._spawn_recoverable_xp_shard` (`castle_run.gd:152-170`) instances `XpShardPickup`, which on interact calls `ProgressionService.grant_xp(..., "xp_shard")` and `RunFlow.clear_recoverable_xp_shard()` (`xp_shard_pickup.gd:60-66`).

### Save
`to_save_dict` / `from_save_dict` (`progression_service.gd:148-166`): `level`, `xp`, `talentPointsSpent`, `talents`.

## Contracts

**Signals:** `progression_changed` — InventoryService reapplies gear; UI listeners. `xp_granted(amount, reason)` — `AchievementService` records `xp_granted_<reason>` on `CharacterService.flags`.

**Content keys read:** `levels[].level`, `levels[].xpRequired`, `deathXpFraction`, `abandonedXpFraction`, `baseXpPerKill`, `bossBonusXp`, `escapeBonusXp`, `talentPointsPerLevel` (curve); talent `branches[].nodes[]` with `id`, `maxRank`, `costPerRank`, `requires`, `effects[].stat`, `effects[].valuePerRank`.

**Callers of grant/calculate:** `RunFlow` escape/death/abandon/waves paths.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| XP grant + level from curve thresholds | IMPLEMENTED | `progression_service.gd:46-66`, `185-192` |
| Death XP fraction from JSON | IMPLEMENTED | `deathXpFraction` + `apply_death_xp_fraction` |
| Run XP economy keys in JSON | IMPLEMENTED | `xp_curve.json:3-5`, `calculate_run_xp` |
| Talent unlock + all branch stats | IMPLEMENTED | Tree + combat/loot/economy readers |
| Abandon XP fraction | IMPLEMENTED | `apply_abandon_xp_fraction`, `run_flow.gd:326-338` |
| XP grant reason analytics | IMPLEMENTED | `xp_granted` signal, `achievement_service.gd:122-126` |
| XP shard pickup | IMPLEMENTED | `xp_shard_pickup.gd`, `castle_run.gd:152-170` |
| Respec | PARTIAL | `respec_talents` clears state (`progression_service.gd:142-145`); hub UX coverage owned elsewhere |

## Related
- Improvement plan: [`../actual_improvements/progression-service.md`](../actual_improvements/progression-service.md)
- [`run-flow.md`](run-flow.md), [`content-data.md`](content-data.md), [`inventory-service.md`](inventory-service.md), [`ui/talents.md`](ui/talents.md)
