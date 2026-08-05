# Progression service

`ProgressionService` is the autoload for permanent XP, level, and talents. Run outcomes call `grant_xp` / `calculate_run_xp` / `apply_death_xp_fraction`. Recoverable death XP uses `XpShardPickup` spawned by `castle_run.gd`. The talent tree defines 18 nodes across three branches; four aptitude stats are aggregated but never read by combat, loot, or economy code.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/progression/progression_service.gd` | XP, level, talents, save dict |
| `apps/game/client/scripts/progression/xp_shard_pickup.gd` | World interact → `grant_xp` + clear shard flag |
| `content/progression/xp_curve.json` | Level thresholds + (mismatched) economy keys |
| `content/talents/tree.json` | Three branches × six nodes |
| `apps/game/client/scripts/dungeon/castle_run.gd` | Spawns `XpShardPickup` from `RunFlow` shard meta |
| `apps/game/client/scripts/combat/combat_stat_modifiers.gd` | Applies a subset of talent stats in combat |

## How it works

### XP and level
Loads `XP_CURVE_PATH` into `_curve` / `_levels` (`progression_service.gd:161-163`).

`grant_xp(amount, reason)` (`progression_service.gd:45-58`) adds XP, `_recalc_level()`, emits `progression_changed`, returns `{ gained, levels_gained, level, xp }`.

`_recalc_level` (`progression_service.gd:177-184`) sets level to the highest `levels[].level` whose `xpRequired` ≤ current XP.

`calculate_run_xp(kills, boss_defeated, escaped)` (`progression_service.gd:61-68`):

```text
kills * baseXpPerKill(default 25)
+ bossBonusXp(default 150) if boss
+ escapeBonusXp(default 50) if escaped
```

`xp_curve.json` instead authors `baseXpPerRun`, `tierXpBonus`, `abandonedXpFraction` — **none of those keys are read**. Defaults always apply today.

`apply_death_xp_fraction` uses `deathXpFraction` (0.5 in file) (`progression_service.gd:71-73`).

Talent points available: `(level - 1) * talentPointsPerLevel` from **curve** dict default `1` (`progression_service.gd:187-189`). `tree.json` also has `talentPointsPerLevel: 1` but that field is never read by the service.

### Talents
`unlock_talent` checks max rank, cost, and `requires` (`progression_service.gd:84-108`). `get_talent_stat_totals` sums `effects[].stat` × `valuePerRank` × rank (`progression_service.gd:111-131`).

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
| `lootQuality` | No | Only listed in `Equipment.STAT_KEYS` / talents UI — no loot/AffixRoller reader |
| `xpGain` | No | `grant_xp` does not multiply by talent totals |
| `goldFind` | No | No merchant/coin path reads it |
| `cooldownReduction` | No | No weapon art / ability cooldown reader |

### XP shard
`RunFlow` stores recoverable XP on death; `castle_run._spawn_recoverable_xp_shard` (`castle_run.gd:152-170`) instances `XpShardPickup`, which on interact calls `ProgressionService.grant_xp(..., "xp_shard")` and `RunFlow.clear_recoverable_xp_shard()` (`xp_shard_pickup.gd:60-66`).

### Save
`to_save_dict` / `from_save_dict` (`progression_service.gd:140-158`): `level`, `xp`, `talentPointsSpent`, `talents`.

## Contracts

**Signal:** `progression_changed` — InventoryService reapplies gear; UI listeners.

**Content keys read:** `levels[].level`, `levels[].xpRequired`, `deathXpFraction`, `baseXpPerKill`, `bossBonusXp`, `escapeBonusXp`, `talentPointsPerLevel` (curve); talent `branches[].nodes[]` with `id`, `maxRank`, `costPerRank`, `requires`, `effects[].stat`, `effects[].valuePerRank`.

**Callers of grant/calculate:** `RunFlow` escape/death/waves paths.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| XP grant + level from curve thresholds | IMPLEMENTED | `progression_service.gd:45-58`, `177-184` |
| Death XP fraction from JSON | IMPLEMENTED | `deathXpFraction` in file + `apply_death_xp_fraction` |
| Run XP economy keys in JSON | BROKEN | File has `baseXpPerRun`; code reads `baseXpPerKill` defaults (`progression_service.gd:62-67`) |
| Talent unlock + combat arms/guard/aptitude move/stam | IMPLEMENTED | Tree + `CombatStatModifiers` / Health |
| `lootQuality` / `xpGain` / `goldFind` / `cooldownReduction` | FAKE | Aggregated in `get_talent_stat_totals`; zero gameplay readers (grep under `scripts/`) |
| XP shard pickup | IMPLEMENTED | `xp_shard_pickup.gd`, `castle_run.gd:152-170` |
| `tree.json` `talentPointsPerLevel` | FAKE | Authored but unread (`progression_service.gd:187-189` reads curve) |
| Respec | PARTIAL | `respec_talents` clears state (`progression_service.gd:134-137`); hub UX coverage owned elsewhere |

## Related
- Improvement plan: [`../actual_improvements/progression-service.md`](../actual_improvements/progression-service.md)
- [`run-flow.md`](run-flow.md), [`content-data.md`](content-data.md), [`inventory-service.md`](inventory-service.md), [`ui/talents.md`](ui/talents.md)
