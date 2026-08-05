# Content data

Repo-root `content/` is the shared JSON definition tree for the Godot client, `scripts/validate-content`, and `packages/procedural`. Schemas live under `content/schemas/*.v1.json`. The client never validates against schemas at runtime — it loads dictionaries through `ContentLoader` and domain catalogs. Offline CI runs Ajv validation.

## Files
| Path | Role |
|------|------|
| `content/**/*.json` | Authored definitions and fixtures |
| `content/schemas/*.v1.json` | JSON Schema draft-07 contracts (24 schema files) |
| `apps/game/client/scripts/app/content_loader.gd` | Path resolution + `load_json` |
| `scripts/validate-content/validate.mjs` | Ajv runner + item catalog consistency + equipment rules |

## How it works

### Layout (domains on disk)
| Directory | Typical payload |
|-----------|-----------------|
| `achievements/` | `catalog.json` |
| `affixes/` | `prefixes.json`, `suffixes.json`, `rarity_rules.json` |
| `audio_profiles/` | Per-biome audio profile |
| `biomes/` | Biome definitions |
| `bosses/` | Boss enemy definitions (same schema family as enemies) |
| `classes/` | Playable class defs |
| `dialogue/` | Branching dialogue trees |
| `enemies/` | Regular enemy defs |
| `fixtures/` | Sample dungeon/inventory/character JSON for tests |
| `items/equipment/`, `items/consumables/`, `items/materials/` | Item definitions |
| `items/catalog.json` | Index of item ids by category (tooling; see content-catalog) |
| `loot/` | `global_drops.json` skip-item chances |
| `merchant/` | Merchant pack JSON |
| `npcs/` | Hub NPC defs (`dialogueId`, `interactType`, position) |
| `progression/` | `xp_curve.json` |
| `quests/` | Quest defs |
| `recipes/` | Blacksmith recipes |
| `relics/` | Run relic defs |
| `schemas/` | `*.v1.json` |
| `statuses/` | Status effect defs |
| `talents/` | `tree.json` |
| `weapons/` | Weapon combat defs |

`ARCHITECTURE.md` §8 lists the same domains. File count fluctuates with content; validation walks every `.json` under `content/` except `schemas/`.

### JSON conventions
- Top-level objects usually carry `schemaVersion: 1` and an `id` string when they are catalog entries.
- Item defs require `id`, `name`, `itemType`, `gridWidth`, `gridHeight`, `stackSize` per `item-instance.v1.json` (misnamed — these are **definitions**, not rolled instances).
- Affix packs wrap `{ "schemaVersion", "affixes": [ ... ] }` with per-affix `tiers` keyed by rarity (`affix-definition.v1.json`).
- Rarity strings in schemas still include both `mythic` and `aumbral` (`item-instance.v1.json:28-30`, `affix-rarity-rules.v1.json`).

### Schemas (24)
`achievement-catalog`, `affix-definition`, `affix-pack`, `affix-rarity-rules`, `audio-profile`, `biome-definition`, `character-state`, `class-definition`, `dialogue-definition`, `dungeon-definition`, `enemy-definition`, `global-drops`, `inventory`, `item-catalog`, `item-instance`, `merchant-pack`, `npc-definition`, `quest-definition`, `recipe-definition`, `relic-definition`, `status-definition`, `talent-tree`, `weapon-definition`, `xp-curve`.

### Runtime load
`ContentLoader.content_root()` (`content_loader.gd:8-12`): `ProjectSettings` `aumbrye/content_root` if set, else `res://` globalized joined with `../../..` (repo root from `apps/game/client`). `load_json(relative)` opens the absolute path, `JSON.parse_string`, returns `{}` on missing/invalid (`content_loader.gd:19-30`). Debug builds `push_error` on missing files; release `push_warning`.

### Tooling validation
`validate.mjs` maps path prefixes to schemas (`resolveSchemaForFile`, lines 68-142). Files without a mapping print `SKIP (no schema)`. Extra checks: `validateItemCatalogConsistency` (catalog ↔ disk ids) and `validateContentRules` (allowed equipment stat keys, `weaponId` presence). `--strict-content` fails placeholder descriptions matching `/^M6 content item\.?$/i`.

### Known schema ↔ code skew
| Content / schema field | Runtime reader | Result |
|------------------------|----------------|--------|
| `xp_curve.json` `baseXpPerRun`, `tierXpBonus`, `abandonedXpFraction` | `ProgressionService.calculate_run_xp` reads `baseXpPerKill`, `bossBonusXp`, `escapeBonusXp` | Defaults `25` / `150` / `50` — authored curve keys unused |
| `talents/tree.json` `talentPointsPerLevel` | `ProgressionService._talent_points_from_level` reads `_curve.get("talentPointsPerLevel", 1)` | Tree field ignored; curve lacks the key → always `1` |
| Affix `tiers` per rarity | `AffixRoller` uses top-level `min`/`max` defaults `1`/`3` | Authored tier tables unused for values |
| `items/catalog.json` | `ItemCatalog` scans directories only | Catalog is tooling-only at runtime |

## Contracts

**Consumers:** Godot catalogs (`scripts/content/*`, dialogue/quest/relic loaders), `AffixRoller`, `ProgressionService`, `AchievementService`, `GlobalDropService`, C# `packages/procedural`, CI `validate-content`.

**Project setting:** `aumbrye/content_root` overrides path for exports.

**No runtime schema validation** — missing keys become silent defaults.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Domain JSON tree + 24 schemas | IMPLEMENTED | `content/`, `content/schemas/` |
| CI Ajv validation | IMPLEMENTED | `scripts/validate-content/validate.mjs` |
| Runtime schema validation | ABSENT | `ContentLoader.load_json` returns parsed dict only (`content_loader.gd:19-30`) |
| `item-instance.v1.json` naming | FAKE | Schema describes item **definitions** used by inventory, not rolled instances |
| XP curve keys vs `ProgressionService` | BROKEN | Schema requires `baseXpPerRun` (`xp-curve.v1.json:10`); code reads `baseXpPerKill` (`progression_service.gd:62`) |
| Affix tier tables vs roller | BROKEN | Schema requires `tiers` (`affix-definition.v1.json:8`); roller uses `min`/`max` (`affix_roller.gd:35`) |
| Dual mythic/aumbral in schemas | PARTIAL | Both enum members still legal while client normalizes mythic→aumbral |

## Related
- Improvement plan: [`../actual_improvements/content-data.md`](../actual_improvements/content-data.md)
- [`content-catalog.md`](content-catalog.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`progression-service.md`](progression-service.md), [`ARCHITECTURE.md`](../ARCHITECTURE.md)
