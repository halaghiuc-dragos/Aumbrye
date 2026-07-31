# M6 Balance Notes

Generated during BAL-6.1. Run `scripts/balance/balance-cli.ps1 -Summary -Export` to refresh counts.

## Content volume (EA caps)

| Category | Cap | M6 count |
|----------|-----|----------|
| Themes | 5 | 5 |
| Enemies | ≤20 | 20 (roster) + training_grunt |
| Bosses | ≤8 | 8 |
| Items (catalog) | ≤80 | 78 |

## DPS bands (stub targets)

| Role | Attack damage range | Notes |
|------|---------------------|-------|
| Melee grunt | 14–17 | Castle/frost/swamp slashers |
| Ranged | 13–16 | Archers, spitters, acolytes |
| Heavy | 19–24 | Brutes, knights, bosses phase 1 |
| Boss | 22–26 | Phase 2 +10% damage (manual tune) |

## Status tuning

| Status | Stacks on hit (M6) | Resist notes |
|--------|-------------------|--------------|
| Freeze | 1–2 (frost theme) | Frost enemies apply freeze fairly |
| Poison | 2 (swamp) | Devourer/hydra alias |
| Burn | 1 (fire weapons) | Flame sword affix |

## Outliers flagged for M7

- `mythic_*` items: unique rules stubbed (affix counts only)
- Miniboss threat_cost may crowd elite slots in frozen/cathedral pools
- Crystal roster renamed IDs (crawler/spitter/wisp) — legacy slime/bat defs remain on disk

## CLI

```powershell
./scripts/balance/balance-cli.ps1 -Summary -Export
```
