# Content catalog

Client-side catalogs are thin static loaders over `ContentLoader`. There is no single registry autoload: `ItemCatalog`, `EnemyCatalog`, `ClassCatalog`, and `RelicCatalog` live under `scripts/content/`; dialogue, quests, achievements, and others use parallel patterns. All six directory-scan catalogs share `ContentDirLoader.load_id_map()`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/app/content_loader.gd` | Root resolution + `load_json` + `clear_all_caches()` |
| `apps/game/client/scripts/content/content_dir_loader.gd` | Shared `DirAccess` walk for JSON catalogs |
| `apps/game/client/scripts/content/item_catalog.gd` | Scans equipment/consumables/materials dirs; optional strict `catalog.json` allowlist |
| `apps/game/client/scripts/content/enemy_catalog.gd` | Scans `enemies/` + `bosses/`; legacy id aliases |
| `apps/game/client/scripts/content/class_catalog.gd` | Scans `classes/` |
| `apps/game/client/scripts/content/relic_catalog.gd` | Scans `relics/` |
| `apps/game/client/scripts/dialogue/dialogue_catalog.gd` | Scans `dialogue/` |
| `apps/game/client/scripts/quests/quest_catalog.gd` | Scans `quests/` |
| `apps/game/client/scripts/debug/debug_console.gd` | Debug `content_reload` command (F12) |
| `scripts/validate-content/validate.mjs` | Schema map + catalog↔disk consistency |
| `content/items/catalog.json` | Tooling index of item ids by category (equipment, consumables, materials) |

## How it works

### `ContentLoader`
See also content-data. `content_path(relative)` joins `content_root()` with a repo-relative path such as `content/items/equipment/iron_sword.json` (`apps/game/client/scripts/app/content_loader.gd:15-16`). `clear_all_caches()` (`content_loader.gd:36-42`) calls `clear_cache()` on all six directory catalogs.

### `ContentDirLoader`
`load_id_map(relative_dirs, id_key := "id", catalog_label, stamp_content_path, warn_missing_id)` (`apps/game/client/scripts/content/content_dir_loader.gd:7-19`) walks each directory with `DirAccess`, loads JSON via `ContentLoader`, keys by `id`. When `stamp_content_path` is true, sets `data["content_path"]` to the repo-relative file path (`content_dir_loader.gd:46-47`).

### `ItemCatalog`
`CATEGORY_DIRS` (`apps/game/client/scripts/content/item_catalog.gd:6-10`): `content/items/equipment`, `consumables`, `materials`. `_ensure_loaded` (`item_catalog.gd:46-52`) calls `ContentDirLoader.load_id_map(..., true, true)`. When `aumbrye/strict_item_catalog` is true (`project.godot:30`, `item_catalog.gd:55-71`), intersects disk ids with `catalog.json` categories `equipment`, `consumables`, `materials` and `push_error` on orphans/missing entries. API: `get_definition`, `get_content_path`, `has_item`, `get_loot_value`, `clear_cache`.

### `EnemyCatalog`
Loads `content/enemies` and `content/bosses` via `ContentDirLoader` (`apps/game/client/scripts/content/enemy_catalog.gd:14-17`, `62`). `LEGACY_ALIASES` (`enemy_catalog.gd:10-12`) maps `castle_knight` → `boss_castle_knight`. `get_scene` loads `def.scene` PackedScene and caches it (`enemy_catalog.gd:34-46`). `clear_cache` also clears `_scenes` (`enemy_catalog.gd:54-56`).

### `ClassCatalog`
`CLASSES_DIR := "content/classes"` (`apps/game/client/scripts/content/class_catalog.gd:6`). Loaded via `ContentDirLoader` at `class_catalog.gd:60`. Helpers: `get_all_classes` (sorted by name), `is_weapon_allowed` (empty `allowedWeapons` → allow all), `get_stat_bonuses`, `get_starting_weapon_item_id` (default `"castle_sword"`).

### `RelicCatalog`
`RELIC_DIR := "content/relics"` (`apps/game/client/scripts/content/relic_catalog.gd:4`). Loaded via `ContentDirLoader` at `relic_catalog.gd:29`. `get_definition`, `get_all_ids`. Run relics are **not** listed in `items/catalog.json` (schema `content/schemas/item-catalog.v1.json:5-8`).

### Parallel catalogs (not under `scripts/content/`)
Same directory-walk pattern via `ContentDirLoader`: `DialogueCatalog` (`dialogue_catalog.gd:23-25`), `QuestCatalog` (`quest_catalog.gd:31`). Others: `AchievementService._load_catalog` (single file), `AffixRoller` (three affix files), `ProgressionService` (xp curve + talent tree), `GlobalDropService` (loot file), biome/dungeon catalogs elsewhere.

### `validate-content`
`resolveSchemaForFile` maps `items/catalog.json` → `item-catalog.v1.json` (`scripts/validate-content/validate.mjs:115-116`). `validateItemCatalogConsistency` (`validate.mjs:278-349`) requires every disk item id listed in `catalog.json` and every listed id present on disk; warns on unexpected `itemType` per folder. Categories: equipment, consumables, materials only (no `relics` key).

### Dev reload
`DebugConsole` autoload (`project.godot:56`) registers `content_reload` → `ContentLoader.clear_all_caches()` (`debug_console.gd:12-16`, `45-47`). Bound to F12 (`debug_console` input action, `project.godot:232`) in debug builds only (`debug_console.gd:9-10`).

## Contracts

**Lookup key:** always JSON `id` field.

**Failure mode:** missing file → `{}` / empty def; missing dir → `push_warning`.

**C# parity:** `packages/procedural` also reads `content/`; cross-stack checks live in `cross_stack_parity_suite.gd` (affix determinism noted there).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Directory-scan catalogs for items/enemies/classes/relics/quests/dialogue | IMPLEMENTED | `item_catalog.gd:49`, `enemy_catalog.gd:62`, `class_catalog.gd:60`, `relic_catalog.gd:29`, `quest_catalog.gd:31`, `dialogue_catalog.gd:23` |
| Shared `ContentDirLoader` | IMPLEMENTED | `apps/game/client/scripts/content/content_dir_loader.gd:7-50` |
| `items/catalog.json` tooling consistency | IMPLEMENTED | `scripts/validate-content/validate.mjs:278-349` |
| Runtime strict `catalog.json` allowlist | IMPLEMENTED | `project.godot:30`, `item_catalog.gd:55-71` |
| Hot-reload / cache invalidation | IMPLEMENTED | `content_loader.gd:36-42`, `debug_console.gd:45-47` |
| `catalog.json` run relics confusion | RESOLVED | `content/schemas/item-catalog.v1.json:8`; run relics in `content/relics/` |

## Related
- Improvement plan: [`../actual_improvements/content-catalog.md`](../actual_improvements/content-catalog.md)
- [`content-data.md`](content-data.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`enemies.md`](enemies.md)
