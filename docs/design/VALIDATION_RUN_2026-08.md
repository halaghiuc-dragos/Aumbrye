# Validation run — 2026-08

**Date:** 2026-08-04  
**Scope:** Minimal — `node scripts/validate-content/validate.mjs` from repo root only.  
**PowerShell script:** None (`scripts/validate-content/` has `validate.mjs`, `package.json` only; no `validate-content.ps1`).  
**Godot MCP:** Not run.

## Result: **PASS**

| Step | Outcome |
|------|---------|
| `node scripts/validate-content/validate.mjs` | Exit code 0; 198 files validated |

### Summary

- **Schema:** All content JSON files pass (including previously failing affix rules, boss lore fields, and mythic/aumbral rarity).
- **Content rules:** Catalog consistency (78 item ids), stat keys, and weaponId references all pass.
- **Runner:** Completes cleanly; weapon file check uses `existsSync` (no ENOENT crash).

### Fixes applied

| Issue | Fix |
|-------|-----|
| `affixes/rarity_rules.json` — `aumbral` extra properties | Extended `affix-rarity-rules.v1.json` with `aumbral` in `affixCounts` / `rarityWeights` |
| Boss files — `title`, `loreText` | Extended `enemy-definition.v1.json` |
| Mythic items — `rarity: "aumbral"` not in enum | Added `aumbral` to `item-instance.v1.json` rarity enum |
| `castle_chalice.json` — `healthRegen` | Added to `ALLOWED_ITEM_STAT_KEYS` and `Equipment.STAT_KEYS` |
| `cathedral_shadow_cloak.json` — `evasion` | Added to `ALLOWED_ITEM_STAT_KEYS` and `Equipment.STAT_KEYS` (found on full run) |
| Missing `content/weapons/staff.json` | Created minimal staff weapon definition |
| Missing `content/weapons/axe.json` | Created minimal axe weapon definition (referenced by `war_hammer`) |
| `statSync` ENOENT crash | Switched weapon file check to `existsSync` in `validate.mjs` |

### Files changed

- `content/schemas/affix-rarity-rules.v1.json`
- `content/schemas/enemy-definition.v1.json`
- `content/schemas/item-instance.v1.json`
- `content/weapons/staff.json` (new)
- `content/weapons/axe.json` (new)
- `scripts/validate-content/validate.mjs`
- `apps/game/client/scripts/items/equipment.gd`
