# Content catalog

Client-side catalogs are thin static loaders over `ContentLoader`. There is no single registry autoload: `ItemCatalog`, `EnemyCatalog`, `ClassCatalog`, and `RelicCatalog` live under `scripts/content/`; dialogue, quests, achievements, and others use parallel patterns. `content/items/catalog.json` is enforced by Node validation but **not** read by `ItemCatalog` at runtime.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/app/content_loader.gd` | Root resolution + `load_json` |
| `apps/game/client/scripts/content/item_catalog.gd` | Scans equipment/consumables/materials dirs |
| `apps/game/client/scripts/content/enemy_catalog.gd` | Scans `enemies/` + `bosses/`; legacy id aliases |
| `apps/game/client/scripts/content/class_catalog.gd` | Scans `classes/` |
| `apps/game/client/scripts/content/relic_catalog.gd` | Scans `relics/` |
| `apps/game/client/scripts/dialogue/dialogue_catalog.gd` | Scans `dialogue/` |
| `apps/game/client/scripts/quests/quest_catalog.gd` | Scans `quests/` |
| `scripts/validate-content/validate.mjs` | Schema map + catalog↔disk consistency |
| `content/items/catalog.json` | Tooling index of item ids by category |

## How it works

### `ContentLoader`
See also content-data. `content_path(relative)` joins `content_root()` with a repo-relative path such as `content/items/equipment/iron_sword.json` (`content_loader.gd:15-16`).

### `ItemCatalog`
`CATEGORY_DIRS` (`item_catalog.gd:6-10`): `content/items/equipment`, `consumables`, `materials`. `_ensure_loaded` walks each dir, `load_json`, keys by `data.id`, stamps `content_path` (`item_catalog.gd:39-65`). Skips files missing `id`. API: `get_definition`, `get_content_path`, `has_item`, `get_loot_value` (prefers `lootValue`, else `value`, else `1`).

**Does not open `content/items/catalog.json`.**

### `EnemyCatalog`
Loads `content/enemies` and `content/bosses` the same way (`enemy_catalog.gd:49-75`). `LEGACY_ALIASES` maps `castle_knight` → `boss_castle_knight` (`enemy_catalog.gd:10-12`). `get_scene` loads `def.scene` PackedScene and caches it (`enemy_catalog.gd:29-41`).

### `ClassCatalog`
`CLASSES_DIR := "content/classes"` (`class_catalog.gd:6`). Helpers: `get_all_classes` (sorted by name), `is_weapon_allowed` (empty `allowedWeapons` → allow all), `get_stat_bonuses`, `get_starting_weapon_item_id` (default `"castle_sword"`).

### `RelicCatalog`
`RELIC_DIR := "content/relics"` (`relic_catalog.gd:4`). `get_definition`, `get_all_ids`.

### Parallel catalogs (not under `scripts/content/`)
Same directory-walk pattern: `DialogueCatalog`, `QuestCatalog`, `AchievementService._load_catalog` (single file), `AffixRoller` (three affix files), `ProgressionService` (xp curve + talent tree), `GlobalDropService` (loot file), biome/dungeon catalogs elsewhere.

### `validate-content`
`SCHEMA_MAP` / `resolveSchemaForFile` (`validate.mjs:45-142`) assigns schemas by path prefix. `validateItemCatalogConsistency` (`validate.mjs:209-284`) requires every disk item id listed in `catalog.json` and every listed id present on disk; warns on unexpected `itemType` per folder. `validateContentRules` (`validate.mjs:286-325`) checks equipment stat allowlist and `weaponId` → `content/weapons/<id>.json`.

## Contracts

**Lookup key:** always JSON `id` field.

**Failure mode:** missing file → `{}` / empty def; missing dir → `push_warning`.

**C# parity:** `packages/procedural` also reads `content/`; cross-stack checks live in `cross_stack_parity_suite.gd` (affix determinism noted there).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Directory-scan catalogs for items/enemies/classes/relics | IMPLEMENTED | `scripts/content/*.gd` |
| `items/catalog.json` tooling consistency | IMPLEMENTED | `validate.mjs:209-284` |
| Runtime use of `items/catalog.json` | ABSENT | `ItemCatalog` only scans dirs (`item_catalog.gd:39-43`) |
| Unified ContentRegistry autoload | ABSENT | Four class_name catalogs + scattered loaders |
| Hot-reload / cache invalidation | ABSENT | Static `_definitions` filled once (`_ensure_loaded` early return) |
| `catalog.json` `relics` array vs materials folder | PARTIAL | Schema allows `relics` (`item-catalog.v1.json:19-22`); ItemCatalog does not scan a relics item folder — run relics are `content/relics/` via `RelicCatalog` |

## Related
- Improvement plan: [`../actual_improvements/content-catalog.md`](../actual_improvements/content-catalog.md)
- [`content-data.md`](content-data.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`enemies.md`](enemies.md)
