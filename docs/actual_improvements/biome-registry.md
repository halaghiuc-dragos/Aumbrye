# Biome registry — improvement plan

## Status: FINISHED

## Current state

`BiomeRegistry` (`apps/game/client/scripts/dungeon/biome_registry.gd`) is a cached loader over `content/biomes/<id>.json` v2 kit files. Room scenes load on demand via `ResourceLoader.load`; materials, lighting, audio, loot tables, and trap pools are read from JSON. `ALL_BIOMES` is derived from the directory listing at bootstrap. See [`../existing_codebase/biome-registry.md`](../existing_codebase/biome-registry.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| BIO-01 | P0 | Everything visible about a biome hardcoded in GDScript | **FINISHED** — v2 JSON kit + `get_biome` accessors (`biome_registry.gd:36-175`) |
| BIO-02 | P1 | Biome JSON loaded with no schema validation and no cache | **FINISHED** — `_cache` + `_validate_biome` (`biome_registry.gd:30-34,248-272`); CI validates v2 (`validate.mjs:130`) |
| BIO-03 | P1 | `gridStep` schema-required and read by nothing | **FINISHED** — removed from all biome files; `biome_kit_suite.gd` asserts absence |
| BIO-04 | P1 | `budgets.baseLootValue` / `lootPerTier` read by nothing | **FINISHED** — `ProcgenLootRoller.roll_chest` (`procgen_loot_roller.gd:22-25`) |
| BIO-05 | P1 | Loot/trap tables in `procgen_loot_tables.gd` | **FINISHED** — `lootTables` + `trapPool` in biome JSON; `procgen_placements.gd:369-374` |
| BIO-06 | P1 | Five audio profiles point at castle audio | **FINISHED** — distinct `ambiencePath` per biome (`content/audio_profiles/*.json`) |
| BIO-07 | P1 | Single-entry `bossPool` on nine biomes | **FINISHED** — all biomes have 2+ weighted `bossPool` entries |
| BIO-08 | P2 | All 90 room scenes preloaded | **FINISHED** — `ResourceLoader.load` + `_room_scene_cache` (`biome_registry.gd:56-71`) |
| BIO-09 | P2 | `name` duplicated in `get_display_name()` | **FINISHED** — `get_display_name` reads JSON `name` (`biome_registry.gd:48-52`) |
| BIO-10 | P2 | Unknown biome silently falls back to castle | **FINISHED** — empty dict + `push_error` (`biome_registry.gd:39-42`) |
| BIO-11 | P2 | Waves mode overrides biome ambient outright | **FINISHED** — multiplicative lerp (`biome_registry.gd:119-124`) |
| BIO-12 | P2 | `get_ceiling_material` aliases wall | **FINISHED** — `materials.ceiling` + `mat_ceiling.tres` per folder |
| BIO-13 | P2 | Adding a biome requires seven coordinated edits | **FINISHED** — one JSON + assets; `ALL_BIOMES` auto-discovered; C# reads JSON (`BiomeCatalog.cs`) |

## Target design

One biome is one JSON file plus one asset folder. `BiomeRegistry` is a thin cached loader; `resolve_biome_id` keeps the save fallback.

Full v2 schema: `content/schemas/biome-definition.v2.json`. Room scenes resolve by convention: `res://scenes/rooms/<assetFolder>/<templatePrefix>_<kind>.tscn`.

## Work plan

1. **Extend the schema** — `biome-definition.v2.json` (BIO-01, BIO-03, BIO-05).
2. **Author the ten kit files** — all `content/biomes/*.json` rewritten (BIO-01).
3. **`BiomeRegistry.get_biome` cache** — accessors read JSON; no `match`/`preload` (BIO-01, BIO-02, BIO-08, BIO-09, BIO-10).
4. **`ProcgenBiomeLoader` deprecated** — delegates to `BiomeRegistry.get_biome` (`procgen_biome_loader.gd`).
5. **`template_prefix_for_biome`** — reads `templatePrefix` from JSON (`room_template_catalog.gd:44-48`).
6. **Loot and trap tables** — in biome JSON; `ProcgenLootRoller` + `_pick_trap` (BIO-04, BIO-05).
7. **Ceiling material** — `mat_ceiling.tres` per folder (BIO-12).
8. **Audio and boss variety** — distinct audio paths; 2-entry boss pools (BIO-06, BIO-07).
9. **Waves lighting** — multiplicative blend (BIO-11).
10. **C# reads JSON** — `BiomeCatalog.cs`, `RoomTemplateCatalog.TemplatePrefixForBiome` (BIO-13).

## Data and schema changes

- `content/schemas/biome-definition.v2.json` — full kit schema; `validate.mjs` validates biomes against v2.
- All 10 `content/biomes/*.json` — v2 shape with `templatePrefix`, `assetFolder`, `materials`, `lighting`, `audioProfile`, `propKit`, `lootTables`, `trapPool`.
- `apps/game/client/assets/<folder>/mat_ceiling.tres` × 10.
- `apps/game/client/scenes/props/<folder>/` — pillar, sconce, rubble_a, rubble_b per biome.
- No save-format change.

## Acceptance criteria

- [x] `biome_registry.gd` contains no `match biome_id` statement and no `preload` of a room scene (BIO-01). Evidence: `biome_registry.gd` — accessors use `get_biome` only.
- [x] For all 10 biomes, every path in `materials`, `propKit`, `audioProfile`, and derived room scene resolves (BIO-01, BIO-02). Evidence: `biome_kit_suite.gd:_test_all_resource_paths_resolve`.
- [x] Loading a biome twice performs one file read (BIO-02). Evidence: `biome_kit_suite.gd:_test_biome_cache_single_read`.
- [x] `gridStep` does not appear in any file under `content/` or `apps/game/client/scripts/` (BIO-03). Evidence: `biome_kit_suite.gd:_test_no_grid_step`.
- [x] For tiers 1 and 5, generated loot value differs per `lootPerTier` (BIO-04). Evidence: `procgen_loot_roller.gd:22-25`; `placements_suite.gd`.
- [x] No two biomes share an `ambiencePath` or `bossPath` (BIO-06). Evidence: `biome_kit_suite.gd:_test_audio_paths_distinct`.
- [x] Every biome's `bossPool` has at least 2 entries (BIO-07). Evidence: `biome_kit_suite.gd:_test_boss_pool_variety`.
- [x] `BiomeRegistry.get_biome("nonexistent")` returns `{}` and pushes an error (BIO-10). Evidence: `biome_kit_suite.gd:_test_unknown_biome_errors`.
- [x] In waves mode, `ambient_light_color` is derived from biome `lighting.ambientColor` (BIO-11). Evidence: `biome_kit_suite.gd:_test_lighting_applied_per_mode`.
- [x] `get_ceiling_material(id) != get_wall_material(id)` for all 10 biomes (BIO-12). Evidence: `biome_kit_suite.gd:_test_ceiling_materials_distinct`.
- [x] `ALL_BIOMES` is derived from directory listing and has 10 entries (BIO-13). Evidence: `biome_registry.gd:228-246`.
- [x] All 10 biome JSON files include `finalFloor.bossId` (RGP-08).

## Validation

`apps/game/client/scripts/validation/suites/biome_kit_suite.gd` — full BIO acceptance suite.

`content_suite.gd` — validates biome JSON against v2 via CI `validate.mjs`.

`cross_stack_parity_suite.gd:_test_biome_catalog_parity` — GDScript/C# template prefix parity (BIO-13).

## Related

- [`../existing_codebase/biome-registry.md`](../existing_codebase/biome-registry.md)
- [`room-templates.md`](room-templates.md)
- [`procgen-placements.md`](procgen-placements.md)
- [`room-graph-procgen.md`](room-graph-procgen.md)
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md)
- [`floor-shell.md`](floor-shell.md)
- [`diorama-room-dressing.md`](diorama-room-dressing.md)
- [`visual-lighting.md`](visual-lighting.md)
- [`audio-director.md`](audio-director.md)
- [`content-data.md`](content-data.md)
