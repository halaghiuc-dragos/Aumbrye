# Content data

Repo-root `content/` is the shared JSON definition tree for the Godot client, `scripts/validate-content`, and `packages/procedural`. Schemas live under `content/schemas/*.v1.json`. The client loads dictionaries through `ContentLoader`; **debug builds** validate hot-path JSON via `ContentSchemaValidator`. Offline CI runs Ajv validation.

## Files
| Path | Role |
|------|------|
| `content/**/*.json` | Authored definitions and fixtures |
| `content/schemas/*.v1.json` | JSON Schema draft-07 contracts (`*.v1.json` under `content/schemas/`) |
| `apps/game/client/scripts/app/content_loader.gd` | Path resolution + `load_json` (+ debug schema validation) |
| `apps/game/client/scripts/app/content_schema_validator.gd` | Structural validation for XP curve, items, affixes, roll instances |
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
| `fixtures/` | Sample dungeon/inventory/character/roll-instance JSON for tests |
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
- Item defs require `id`, `name`, `itemType`, `gridWidth`, `gridHeight`, `stackSize` per `item-definition.v1.json` (definitions, not rolled instances).
- Rolled instances match `item-instance-roll.v1.json` (`instanceId`, `itemId`, `quantity`, `rarity`, `affixes[]`, `rollSeed`); fixture `fixtures/item_instance_roll_sample.v1.json`.
- Affix packs wrap `{ "schemaVersion", "affixes": [ ... ] }` with per-affix `tiers` keyed by rarity (`affix-definition.v1.json`); authored tiers use `aumbral` only.
- `inventory.v2.json` / `character-state.v2.json` still accept `mythic` in saved payloads for migration; item/affix definition schemas do not.

### Schemas (representative v1)
`achievement-catalog`, `affix-definition`, `affix-pack`, `affix-rarity-rules`, `audio-profile`, `biome-definition`, `character-state`, `class-definition`, `dialogue-definition`, `dungeon-definition`, `enemy-definition`, `global-drops`, `inventory`, `item-catalog`, `item-definition`, `item-instance-roll`, `merchant-pack`, `npc-definition`, `quest-definition`, `recipe-definition`, `relic-definition`, `status-definition`, `talent-tree`, `weapon-definition`, `xp-curve`.

### Runtime load
`ContentLoader.content_root()` (`content_loader.gd:9-13`): `ProjectSettings` `aumbrye/content_root` if set, else `res://` globalized joined with `../../..` (repo root from `apps/game/client`). `load_json(relative)` opens the absolute path, `JSON.parse_string`, returns `{}` on missing/invalid (`content_loader.gd:20-34`). Debug builds call `ContentSchemaValidator.validate_loaded` on non-empty dicts; release skips runtime checks. Missing files: `push_error` in debug, `push_warning` in release.

### Tooling validation
`validate.mjs` maps path prefixes to schemas (`resolveSchemaForFile`, lines 68-142). Files without a mapping print `SKIP (no schema)`. Extra checks: `validateItemCatalogConsistency` (catalog ↔ disk ids) and `validateContentRules` (allowed equipment stat keys, `weaponId` presence). `--strict-content` fails placeholder descriptions matching `/^M6 content item\.?$/i`.

### Schema ↔ code alignment (post CDT-01–06)

| Area | Status |
|------|--------|
| XP curve keys | `xp_curve.json` uses `baseXpPerKill`, `bossBonusXp`, `escapeBonusXp`, `talentPointsPerLevel` — matches `ProgressionService.calculate_run_xp` |
| Talent points | Authoritative on XP curve only; removed from `talents/tree.json` |
| Affix tiers | `AffixRoller._roll_tier_value()` reads `tiers[rarity]` |
| Item schemas | `item-definition.v1.json` for defs; `item-instance-roll.v1.json` for rolled instances |
| Rarity naming | Content uses `aumbral`; `RarityRegistry` aliases legacy `mythic` |

## Contracts

**Consumers:** Godot catalogs (`scripts/content/*`, dialogue/quest/relic loaders), `AffixRoller`, `ProgressionService`, `AchievementService`, `GlobalDropService`, C# `packages/procedural`, CI `validate-content`.

**Project setting:** `aumbrye/content_root` overrides path for exports.

**Runtime validation:** `ContentSchemaValidator` runs in debug builds on hot-path loads; `AffixRoller` validates rolled instances in debug.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Domain JSON tree + schemas | IMPLEMENTED | `content/`, `content/schemas/` |
| CI Ajv validation | IMPLEMENTED | `scripts/validate-content/validate.mjs` |
| Debug runtime schema validation | IMPLEMENTED | `content_schema_validator.gd`; wired from `ContentLoader` |
| Item definition vs roll schemas | IMPLEMENTED | `item-definition.v1.json`, `item-instance-roll.v1.json` |
| XP curve keys vs `ProgressionService` | IMPLEMENTED | `xp_curve.json` + `progression_suite.gd` |
| Affix tier tables vs roller | IMPLEMENTED | `affix_roller.gd` `_roll_tier_value` |
| Mythic/aumbral naming | IMPLEMENTED | Content uses `aumbral`; `RarityRegistry` legacy alias |
| Strict item catalog at runtime | IMPLEMENTED | `project.godot:30`, `item_catalog.gd:55-71`; see [`content-catalog.md`](content-catalog.md) |

## Related
- Improvement plan: [`../actual_improvements/content-data.md`](../actual_improvements/content-data.md)
- [`content-catalog.md`](content-catalog.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`progression-service.md`](progression-service.md), [`ARCHITECTURE.md`](../ARCHITECTURE.md)
