# M5 Balance Notes (BAL-5.1)

> Mid-content pass — data tweaks over code. TTK targets vs `castle_grunt` (~90 HP).

## Weapon TTK (light combo, no buffs)

| Weapon | Est. combo DPS | TTK grunt | Notes |
|--------|----------------|-----------|-------|
| Sword (castle) | ~52 | ~1.7s | Baseline |
| Greatsword | ~44 swing | ~2.0s | Higher poise, hyperarmor active frames |
| Dagger | ~38 multihit | ~2.4s | Bleed adds ~8 over 6s |
| Spear | ~48 poke | ~1.9s | Safer range |
| Bow (charged) | ~42 ranged | ~2.1s | Stamina gated |

## Enemy tuning

- Crystal golem: +30% HP, frost resist 0.5 — reward frost weapons/items
- Swamp witch: poison resist 0.6 — physical still primary
- Minibosses: ~2.5× grunt HP, phase at 50%

## Affix / loot (LOOT-5.2)

- Epic: 2–3 affixes, weight 6%
- Legendary: 3–4 affixes, weight 3%
- Mythic: 4–5 affixes, weight 1% (stub unique rules via tier caps)

## Status pacing

- Burn: 3 dmg/s × 5s, max 3 stacks
- Bleed: 2 dmg/0.8s × 6s, stacks to 5 (dagger identity)
- Poison: 2.5 dmg/1.2s × 8s; swamp hazards apply 4s refresh
- Freeze: 45% slow, 3s
- Stun: 1.2s lockout

## Recommended playtest

1. Hub → portal → select biome → Start Run
2. Hub → I key → Loadout → swap weapons
3. Arena (`Arena Door`) for moveset feel vs training grunt
4. Crystal/Swamp full run: boss phase telegraphs, poison fairness

## Open tuning

- Bow draw stamina cost may need +2 if kiting too safe
- Swamp hydra poison DPS if deaths feel unfair (add cleanse zone radius)
