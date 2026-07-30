# Run Economy (M4)

Authoritative rules for what players keep or lose when a dungeon run ends. The backend enforces these rules in `POST /api/v1/runs/{id}/complete`; the client displays the outcome.

## Outcomes

| Outcome | Loot | XP | Run relics | Active run |
|---------|------|-----|------------|------------|
| **escaped** | Keep all items in `lootClaimedInstanceIds` (affix-rolled on server) | Full run XP | Cleared | Cleared |
| **died** | Unextracted loot lost; claimed IDs not persisted | `deathXpFraction` (default 50%) of run XP | Lost | Cleared |
| **abandoned** | Lost | `abandonedXpFraction` (default 0%) | Lost | Cleared |

## XP calculation

```
runXp = baseXpPerRun + (tier - 1) * tierXpBonus
```

Values come from `content/progression/xp_curve.json`. Level-ups use the `levels` table; talent points = `(level - 1) * talentPointsPerLevel` from `content/talents/tree.json`.

## Loot and affixes

- Only **equipment** items (`weapon`, `armor`) receive affix rolls on escape.
- Stackables (consumables, materials) are added by `itemId` without affix rolling.
- Each loot `instanceId` from the dungeon definition maps to a deterministic `rollSeed` (derived from the instance UUID).
- Identical `rollSeed` + `itemDefId` always produces identical rarity and affixes.

## Rarity affix counts (default)

| Rarity | Affixes |
|--------|---------|
| common | 0 |
| magic | 1 |
| rare | 2 |
| epic | 2–3 (stub weights) |
| legendary | 3–4 (stub) |
| mythic | 4 (stub) |

Full weights: `content/affixes/rarity_rules.json`.

## Run relics

Temporary in-run buffs tracked in `CharacterState.runRelics`. Cleared on any run end. On **death**, run relics are explicitly removed before save write.

## Escape requirements

- Boss must be defeated (`bossDefeated: true`).
- All `lootClaimedInstanceIds` must exist in the run's dungeon definition.

## Client notes

- Godot should call `complete_run` with claimed loot IDs only on successful escape.
- On death, still call complete with `outcome: "died"`; server applies reduced XP and strips run relics.
- Outcome summary is returned in `CompleteRunResponse.progression` for HUD display (Godot wave).

## Tuning

Defaults are playtest starting points. Adjust `content/progression/xp_curve.json` and `content/affixes/rarity_rules.json`; no code change required for curve/weight tweaks.
