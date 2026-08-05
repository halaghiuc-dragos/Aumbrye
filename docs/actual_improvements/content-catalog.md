# Content catalog — improvement plan

## Current state
Domain catalogs are independent static loaders over `ContentLoader`. CI keeps `content/items/catalog.json` honest against disk, but the Godot `ItemCatalog` never reads that file. See [`../existing_codebase/content-catalog.md`](../existing_codebase/content-catalog.md). Cache is process-lifetime with no invalidation, which is fine for shipping builds and awkward for content iteration.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CCT-01 | P1 | `content/items/catalog.json` is unused at runtime — disk orphans can still load if dropped in a folder, and catalog-only ids cannot | `item_catalog.gd:39-43` vs `validate.mjs:209-284` |
| CCT-02 | P1 | No shared loader helper — each catalog reimplements DirAccess walk + missing-id warnings; drift risk | Compare `item_catalog.gd:46-65`, `enemy_catalog.gd:56-75`, `quest_catalog.gd:24-44` |
| CCT-03 | P2 | Static caches never clear — editor/content iteration requires game restart | `_ensure_loaded` early returns when `_definitions` non-empty |
| CCT-04 | P2 | `catalog.json` `relics` key vs `RelicCatalog` path split confuses authors | `item-catalog.v1.json:19-22`, `relic_catalog.gd:4` |

## Target design

### Single directory loader (chosen)
Extract:

```gdscript
# content_dir_loader.gd
static func load_id_map(relative_dirs: Array[String], id_key := "id") -> Dictionary
```

All catalogs call it. Rejected: one giant `ContentRegistry` autoload — it would couple unrelated domains and force load order for little benefit.

### Catalog.json as allowlist (optional strict mode)
Debug / CI flag `aumbrye/strict_item_catalog`:
- When true, `ItemCatalog._ensure_loaded` intersects disk ids with `catalog.json` and `push_error` on extras/missing.
- Default false in player builds so a forgotten catalog line does not soft-lock loot mid-run; CI already fails the mismatch.

### Relics clarity
Remove `relics` from `items/catalog.json` schema **or** document that array as material charms only and keep `content/relics/` separate. Prefer removing the misleading key if the array duplicates material ids.

### Dev reload
`ContentLoader.clear_all_caches()` called from a debug console command clears every catalog's `_definitions` / `_loaded` flags.

## Work plan

1. **Introduce `ContentDirLoader.load_id_map` and migrate Item/Enemy/Class/Relic/Quest/Dialogue catalogs** — behaviour-identical. Closes CCT-02.
2. **Add strict catalog intersection behind project setting; document in ARCHITECTURE** — Closes CCT-01.
3. **Resolve `relics` key in item catalog schema** — Closes CCT-04.
4. **Debug cache clear command** — Closes CCT-03.

## Data and schema changes

- Possibly drop `relics` from `item-catalog.v1.json` and `catalog.json`.
- No save format change.

## Acceptance criteria
- [ ] All six directory catalogs share one loader implementation (grep shows a single walk helper). (CCT-02)
- [ ] With strict setting on, an equipment JSON whose id is absent from `catalog.json` fails load with `push_error`. (CCT-01)
- [ ] Schema and `catalog.json` no longer imply run relics live under `items/`. (CCT-04)
- [ ] Debug command empties `ItemCatalog` cache and reloads a newly added file without restart. (CCT-03)

## Validation
| Suite | Checks |
|-------|--------|
| `validate.mjs` | Existing catalog consistency (keep) |
| New / `m6_suite` | Strict mode rejects orphan file |
| `cross_stack_parity_suite` | Unaffected identifiers |

## Related
- Existing state: [`../existing_codebase/content-catalog.md`](../existing_codebase/content-catalog.md)
- [`content-data.md`](content-data.md), [`packages.md`](packages.md)
