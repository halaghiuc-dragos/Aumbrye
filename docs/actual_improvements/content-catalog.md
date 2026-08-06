# Content catalog — improvement plan

## Status: FINISHED

## Current state
Domain catalogs share `ContentDirLoader.load_id_map()` over `ContentLoader`. `content/items/catalog.json` is enforced by Node validation and optionally at runtime via `aumbrye/strict_item_catalog`. Cache clears via `ContentLoader.clear_all_caches()` / `DebugConsole` `content_reload` (F12). See [`../existing_codebase/content-catalog.md`](../existing_codebase/content-catalog.md).

## Gaps
| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| CCT-01 | P1 | `content/items/catalog.json` unused at runtime | **FINISHED** — strict allowlist behind `aumbrye/strict_item_catalog` |
| CCT-02 | P1 | No shared loader helper | **FINISHED** — `ContentDirLoader.load_id_map` |
| CCT-03 | P2 | Static caches never clear | **FINISHED** — `clear_all_caches()` + `content_reload` command |
| CCT-04 | P2 | `catalog.json` `relics` key vs `RelicCatalog` path split | **FINISHED** — `relics` removed from schema and catalog |

## Target design

### Single directory loader (chosen)
`ContentDirLoader.load_id_map(relative_dirs, id_key := "id")` in `scripts/content/content_dir_loader.gd`. All six catalogs call it.

### Catalog.json as allowlist (optional strict mode)
Project setting `aumbrye/strict_item_catalog` (default `false`):
- When true, `ItemCatalog._ensure_loaded` intersects disk ids with `catalog.json` and `push_error` on extras/missing.
- Default false in player builds so a forgotten catalog line does not soft-lock loot mid-run; CI already fails the mismatch.

### Relics clarity
`relics` removed from `items/catalog.json` schema. Run relics remain under `content/relics/` (`RelicCatalog`). Material charms that unlock relics stay in `materials/`.

### Dev reload
`ContentLoader.clear_all_caches()` called from `DebugConsole` command `content_reload` (F12 in debug builds).

## Work plan

1. **Introduce `ContentDirLoader.load_id_map` and migrate Item/Enemy/Class/Relic/Quest/Dialogue catalogs** — **FINISHED** (CCT-02).
2. **Add strict catalog intersection behind project setting; document in ARCHITECTURE** — **FINISHED** (CCT-01).
3. **Resolve `relics` key in item catalog schema** — **FINISHED** (CCT-04).
4. **Debug cache clear command** — **FINISHED** (CCT-03).

## Data and schema changes

- Dropped `relics` from `item-catalog.v1.json` and `catalog.json`.
- No save format change.

## Acceptance criteria
- [x] All six directory catalogs share one loader implementation (grep shows a single walk helper). (CCT-02)
- [x] With strict setting on, an equipment JSON whose id is absent from `catalog.json` fails load with `push_error`. (CCT-01)
- [x] Schema and `catalog.json` no longer imply run relics live under `items/`. (CCT-04)
- [x] Debug command empties `ItemCatalog` cache and reloads a newly added file without restart. (CCT-03)

## Validation
| Suite | Checks |
|-------|--------|
| `validate.mjs` | `validateItemCatalogConsistency` (`validate.mjs:278-349`); `items/catalog.json` schema (`item-catalog.v1.json`, no `relics` key) |
| `m6_suite` | `m6.content.shared_dir_loader`, `m6.content.no_duplicate_dir_walk` (CCT-02); `m6.content.strict_rejects_orphan` (CCT-01); `m6.content.reload_command`, `m6.content.cache_clear_reload` (CCT-03) |
| `cross_stack_parity_suite` | Unaffected identifiers |

## Related
- Existing state: [`../existing_codebase/content-catalog.md`](../existing_codebase/content-catalog.md)
- [`content-data.md`](content-data.md), [`packages.md`](packages.md)
