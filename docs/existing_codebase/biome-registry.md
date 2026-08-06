# Biome registry

Ten biomes are fully data-driven. Each `content/biomes/<id>.json` v2 file declares procgen config plus the visible kit: materials, lighting, audio profile path, prop kit, loot tables, and trap pool. `BiomeRegistry` caches and validates JSON at load time; room scenes load on demand per active biome.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/biome_registry.gd` | Cached biome loader, accessors, run presentation |
| `content/biomes/*.json` | 10 full biome kit definitions (v2) |
| `content/schemas/biome-definition.v2.json` | Schema for kit JSON |
| `apps/game/client/scripts/dungeon/procgen/procgen_biome_loader.gd` | Deprecated wrapper → `BiomeRegistry.get_biome` |
| `apps/game/client/scripts/validation/suites/biome_kit_suite.gd` | Acceptance tests BIO-01..BIO-13 |

## How it works

### Discovery and cache

`biome_registry.gd:228-246` lists `content/biomes/*.json` into `ALL_BIOMES` on bootstrap (`_BOOTSTRAP` at `:274`). `get_biome(id)` (`:36-45`) reads through `ContentLoader`, validates required keys (`:_validate_biome`), caches in `_cache`, and returns a duplicate. Unknown ids return `{}` with `push_error` — no castle fallback except `resolve_biome_id` for saves.

### Accessors (all read JSON)

| Function | Evidence | Source |
|----------|----------|--------|
| `get_display_name(id)` | `:48-52` | JSON `name` |
| `get_room_scenes(id)` | `:56-71` | `ResourceLoader.load` per `templatePrefix` + `assetFolder` |
| `get_floor/wall/ceiling/accent_material` | `:74-90, :214-223` | JSON `materials.*` paths |
| `get_lighting_profile(id)` | `:103-116` | JSON `lighting` block |
| `get_audio_profile_path(id)` | `:178-182` | JSON `audioProfile` |
| `biome_from_template_id(id)` | `:93-100` | matches `templatePrefix` across `ALL_BIOMES` |

Room scene convention: `res://scenes/rooms/<assetFolder>/<templatePrefix>_<kind>.tscn` for kinds in `ROOM_KINDS` (`:17-27`).

### Run presentation

`apply_run_presentation(parent, biome_id, run_mode)` (`:119-175`) builds `WorldEnvironment` from the JSON lighting profile. Waves mode (`RunModeConfig.MODE_WAVES`) lerps ambient color toward a waves tint at 0.4 rather than replacing it (`:123-124`). `ArenaFillLight` uses `lighting.torchColor` (`:164-168`).

### Biome JSON (v2)

Example shape (`content/biomes/forgotten_castle.json`):

```json
{
  "id": "forgotten_castle",
  "name": "Forgotten Castle",
  "templatePrefix": "castle",
  "assetFolder": "castle",
  "materials": { "floor": "res://assets/castle/mat_floor.tres", ... },
  "lighting": { "ambientColor": [0.58, 0.5, 0.44], ... },
  "audioProfile": "content/audio_profiles/forgotten_castle.json",
  "propKit": { "pillar": "res://scenes/props/castle/pillar.tscn", ... },
  "lootTables": { "treasure": [...], "secret": [...], "side": [...], "armory": [...] },
  "trapPool": [{ "trapId": "spike_trap", "weight": 3 }, ...],
  "bossPool": [{ "enemyId": "boss_castle_knight", "weight": 3 }, ...],
  "budgets": { "baseLootValue": 80, "lootPerTier": 14, ... }
}
```

Who reads what:

| Key | Reader |
|-----|--------|
| Full dict | `BiomeRegistry.get_biome`, `DungeonProcgen.generate` (`dungeon_procgen.gd:29`) |
| `roomCount`, `requiresSecret`, `roomTemplateIds` | `room_graph_config.gd`, `room_graph_assigner.gd` |
| `enemyPool`, `bossPool`, `budgets`, `lootTables`, `trapPool` | `procgen_placements.gd`, `procgen_loot_roller.gd` |
| `materials`, `lighting`, `audioProfile` | `BiomeRegistry` accessors → floor shell, `VisualLighting`, `AudioDirector` |
| `propKit` | declared for [`diorama-room-dressing.md`](diorama-room-dressing.md) consumers |
| `templatePrefix` | `RoomTemplateCatalog.template_prefix_for_biome` (`room_template_catalog.gd:44-48`) |
| `finalFloor.bossId` | `dungeon_procgen.gd` `_generate_final_floor` |

`gridStep` is **ABSENT** — removed from schema and all biome files (BIO-03).

### C# parity

`packages/procedural/Biome/BiomeCatalog.cs` loads the same JSON files, exposing `TemplatePrefix`, `AssetFolder`, room counts, and pools. `RoomTemplateCatalog.TemplatePrefixForBiome` delegates to `BiomeCatalog` (`RoomTemplateCatalog.cs:212-217`).

## Contracts

- `BiomeRegistry` is a `RefCounted` with `class_name`, called statically. Not an autoload.
- Material paths: JSON `materials.floor|wall|ceiling|accent` must exist under `res://assets/<assetFolder>/`.
- Room scenes: `res://scenes/rooms/<assetFolder>/<templatePrefix>_<kind>.tscn`.
- Audio: JSON `audioProfile` relative path under `content/audio_profiles/`.
- `resolve_biome_id(definition, fallback)` (`biome_registry.gd:185-190`) is the save fallback entry point.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Data-driven biome kit (materials, lighting, rooms, audio) | IMPLEMENTED | `biome_registry.gd`; all 10 v2 JSON files |
| Cached validated JSON load | IMPLEMENTED | `_cache` + `_validate_biome` (`biome_registry.gd:30-45,248-272`) |
| On-demand room scene load | IMPLEMENTED | `_room_scene_cache` (`biome_registry.gd:56-71`) |
| Distinct ceiling materials | IMPLEMENTED | `mat_ceiling.tres` per folder; `get_ceiling_material` (`:87-88`) |
| Loot/trap tables in biome JSON | IMPLEMENTED | `lootTables`, `trapPool`; `procgen_loot_roller.gd`, `procgen_placements.gd:369-374` |
| `budgets.baseLootValue` / `lootPerTier` consumed | IMPLEMENTED | `procgen_loot_roller.gd:22-25` |
| Distinct audio per biome | IMPLEMENTED | 10 unique `ambiencePath` in `content/audio_profiles/*.json` |
| Weighted boss variety (2+ per biome) | IMPLEMENTED | all `bossPool` arrays have ≥2 entries |
| Waves lighting preserves biome profile | IMPLEMENTED | lerp in `apply_run_presentation` (`biome_registry.gd:123-124`) |
| Unknown biome errors (no silent castle fallback) | IMPLEMENTED | `get_biome` returns `{}` (`biome_registry.gd:39-42`) |
| `ALL_BIOMES` auto-discovered | IMPLEMENTED | `_ensure_biome_index` (`biome_registry.gd:228-246`) |
| Room kit art quality (clone blockouts) | PLACEHOLDER | seven of ten kits still generated clones; see [`room-templates.md`](room-templates.md) |
| `propKit` runtime dressing consumer | PARTIAL | paths exist; `diorama_room_dressing.gd` not yet reading `propKit` |
| `DungeonCatalog` tier list in data | PARTIAL | still code; see [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) DCT-01 |

## Related

- Improvement plan: [`../actual_improvements/biome-registry.md`](../actual_improvements/biome-registry.md)
- [`room-templates.md`](room-templates.md)
- [`room-graph-procgen.md`](room-graph-procgen.md)
- [`procgen-placements.md`](procgen-placements.md)
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md)
- [`floor-shell.md`](floor-shell.md)
- [`visual-lighting.md`](visual-lighting.md)
- [`audio-director.md`](audio-director.md)
- [`diorama-room-dressing.md`](diorama-room-dressing.md)
- [`content-data.md`](content-data.md)
