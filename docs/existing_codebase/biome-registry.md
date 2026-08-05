# Biome registry

Ten biomes exist. `content/biomes/<id>.json` holds their procgen config (room counts, template ids, enemy and boss pools, budgets). Everything else about a biome — its room scenes, materials, lighting, display name, and asset folder — is hardcoded in `BiomeRegistry` as five parallel `match` statements plus ten `preload` dictionaries.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/biome_registry.gd` | Biome ids, room scenes, materials, lighting, run presentation |
| `content/biomes/*.json` | 10 procgen configs |
| `content/schemas/biome-definition.v1.json` | Schema for the above |
| `tools/generate_expansion_biomes.py` | The script that generated 5 of the 10 biomes |

## How it works

### The ten biomes

`biome_registry.gd:6-20` declares the ids and `ALL_BIOMES`:

| Constant | Id | Template prefix | Asset folder |
|----------|-----|-----------------|--------------|
| `BIOME_CASTLE` | `forgotten_castle` | `castle` | `assets/castle` |
| `BIOME_CRYSTAL` | `crystal_caverns` | `crystal` | `assets/crystal` |
| `BIOME_SWAMP` | `poison_swamp` | `swamp` | `assets/swamp` |
| `BIOME_FROZEN` | `frozen_fortress` | `frozen` | `assets/frozen` |
| `BIOME_CATHEDRAL` | `dark_cathedral` | `cathedral` | `assets/cathedral` |
| `BIOME_VAULT` | `iron_vault` | `vault` | `assets/vault` |
| `BIOME_PRISM` | `prism_depths` | `prism` | `assets/prism` |
| `BIOME_MIRE` | `venom_mire` | `mire` | `assets/mire` |
| `BIOME_HOLLOW` | `glacial_hollow` | `hollow` | `assets/hollow` |
| `BIOME_UMBRAL` | `umbral_chapel` | `umbral` | `assets/umbral` |

Adding a biome means editing six places in this one file: `ALL_BIOMES`, `get_display_name()` (`:23`), `get_room_scenes()` (`:47`), `get_lighting_profile()` (`:112`), `_material_path()` (`:260`), and a new `_<theme>_rooms()` preload dictionary (`:284-421`). It also means editing `RoomTemplateCatalog.template_prefix_for_biome()` (`room_template_catalog.gd:26`), `DungeonCatalog`, `ProcgenLootTables`' five `match` statements, and the C# `BiomeCatalog`.

### Lookups

| Function | Line | Behavior |
|----------|------|-----------|
| `get_display_name(id)` | `:23` | hardcoded strings; unknown ids fall through to "Forgotten Castle" |
| `get_room_scenes(id)` | `:47` | returns one of ten dictionaries of 9 `preload`ed `PackedScene`s. All 90 scenes are preloaded into the binary regardless of which biome is playing. |
| `get_floor_material` / `get_wall_material` / `get_accent_material` | `:71-84` | runtime `load("res://assets/<folder>/mat_<kind>.tres")` |
| `get_ceiling_material` | `:79` | an alias for the wall material |
| `biome_from_template_id(id)` | `:87` | maps the first `_`-delimited slice of a template id back to a biome id |
| `get_lighting_profile(id)` | `:112` | a hardcoded dictionary of `ambient_color`, `ambient_energy`, `fog_enabled`, `fog_color`, `fog_density` |
| `get_audio_profile_path(id)` | `:249` | `content/audio_profiles/<id>.json` |
| `resolve_biome_id(definition, fallback)` | `:253` | `definition.biomeId`, defaulting to `forgotten_castle` |

All 30 material files (`mat_floor.tres`, `mat_wall.tres`, `mat_accent.tres` per folder) and all 10 audio profiles exist, so no lookup dead-ends.

`apply_run_presentation(parent, biome_id, run_mode)` (`:196`) is the presentation entry point: builds a `WorldEnvironment` from the lighting profile, then branches on run mode — waves gets a fixed purple ambient plus an `ArenaFillLight` and no fog (`:211-215`), castle and endless route through `VisualLighting.apply_indoor_environment` and hide the `DirectionalLight3D` (`:216-217`, `:228-229`), and everything else desaturates the background and calls `PixelDioramaSettings.configure_environment` (`:218-221`). It finishes with `VisualLighting.apply_biome_atmosphere` and `AudioDirector.set_biome`. Because the waves branch overrides `ambient_light_color` and `ambient_light_energy` outright, the biome's lighting profile has almost no effect in waves mode.

### The biome JSON

Every file has the same eight keys, and the schema requires all of them plus optional `requiresSecret` with `additionalProperties: false` (`content/schemas/biome-definition.v1.json:7-8`):

```json
{
  "id": "forgotten_castle",
  "name": "Forgotten Castle",
  "roomCount": { "min": 18, "max": 22 },
  "gridStep": 14,
  "roomTemplateIds": ["castle_entrance", ... 9 entries],
  "enemyPool": [{ "enemyId": "castle_grunt", "weight": 3 }, ...],
  "bossPool": [{ "enemyId": "boss_castle_knight" }, { "enemyId": "miniboss_castle_captain" }],
  "budgets": { "baseEnemyThreat": 200, "baseLootValue": 80, "threatPerTier": 35, "lootPerTier": 14 },
  "requiresSecret": true
}
```

Who reads what:

| Key | Reader |
|-----|--------|
| `id` | `procgen_placements.gd:119` (loot table selection) |
| `name` | nothing in GDScript; `BiomeRegistry.get_display_name` has its own copy |
| `roomCount.min/max` | `room_graph_config.gd` |
| `gridStep` | **nothing** — `RoomGraphGeometry` spaces rooms from `KIND_SPECS` half-extents |
| `roomTemplateIds` | `room_graph_assigner.gd` |
| `enemyPool` | `procgen_placements.gd:85` |
| `bossPool` | `procgen_placements.gd:212-213`, `:274` (boss-reservation filter) |
| `budgets.baseEnemyThreat`, `threatPerTier` | `procgen_placements.gd:59-63` |
| `budgets.baseLootValue`, `lootPerTier` | **nothing** in GDScript |
| `requiresSecret` | `room_graph_config.gd` |

Two of the ten fields the schema requires are therefore inert in the GDScript stack.

Per-biome values:

| Biome | roomCount | baseEnemyThreat | threatPerTier | Boss pool size |
|-------|-----------|-----------------|---------------|----------------|
| `forgotten_castle` | 18-22 | 200 | 35 | 2 |
| the other 9 | 6-10 (expansion 5) or authored | 100 (expansion 5) | 20 (expansion 5) | 1 (expansion 5) |

`ProcgenBiomeLoader.load()` (`procgen_biome_loader.gd:5`) reads the file with no schema validation and no cache; a missing file yields `{}`, which `DungeonProcgen` reports as `"Unknown biome"` (`dungeon_procgen.gd:29-31`).

### Where the expansion biomes came from

`tools/generate_expansion_biomes.py` generated `iron_vault`, `prism_depths`, `venom_mire`, `glacial_hollow`, and `umbral_chapel`: their 45 room scenes, biome JSON, and audio profiles. It emits every room as a 16 x 12 `CastleBlockout` with only `Socket_N` and `Socket_S`, no `Props` node, and door flags set only for `entrance` (south) and `boss` (north) (`generate_expansion_biomes.py:192-233`). The `frozen` and `cathedral` scenes have byte-identical structure (`frozen_boss.tscn`, `cathedral_stairs.tscn`), so seven of the ten kits are generated clones. Its `write_material()` is an empty `pass` (`:175-177`), deferring to `tools/generate_pixel_diorama_materials.py`, which it invokes at the end (`:300-301`).

The generated audio profiles all point at `res://assets/audio/castle/ambience_loop.wav` and `boss_theme.wav` (`:273-274`), so five biomes share the castle's audio.

The generated biome JSON hardcodes `roomCount` 6-10, `gridStep` 14, `baseEnemyThreat` 100, `baseLootValue` 60, `threatPerTier` 20, `lootPerTier` 10, and a single-entry `bossPool` for all five (`:244-255`).

## Contracts

- `BiomeRegistry` is a `RefCounted` with `class_name`, called statically. It is not an autoload.
- Material path contract: `res://assets/<folder>/mat_{floor,wall,accent}.tres` must exist for every biome.
- Room scene contract: `res://scenes/rooms/<folder>/<prefix>_<kind>.tscn` for the 9 kinds, and the dictionary key must equal the template id that `RoomTemplateCatalog.template_prefix_for_biome` produces.
- Audio contract: `content/audio_profiles/<biome_id>.json`, consumed by `AudioDirector`.
- Lighting profile keys consumed by `VisualLighting.apply_indoor_environment` and `apply_biome_atmosphere`.
- Callers of `apply_run_presentation`: the run scenes. The `DirectionalLight3D` and `ArenaFillLight` node names are a contract with them.
- `resolve_biome_id` is the single place `DungeonBuilder` decides which biome a definition belongs to (`dungeon_builder.gd:89`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| 10 biomes with distinct materials, lighting, and audio profiles | IMPLEMENTED | `biome_registry.gd:112-193,260-281`; 30 material files, 10 audio profiles present |
| Procgen config as data | IMPLEMENTED | `content/biomes/*.json` + `biome-definition.v1.json` |
| Room scenes, materials, lighting, display names | PLACEHOLDER | five hardcoded `match` statements and ten `preload` dictionaries (`biome_registry.gd:23,47,112,260,284-421`) |
| All 90 room scenes preloaded regardless of biome | PARTIAL | `:284-421` uses `preload`, not `load` |
| `budgets.baseLootValue`, `budgets.lootPerTier` | STUB | required by the schema, read by nothing in GDScript |
| `gridStep` | STUB | required by the schema, read by nothing; spacing comes from `KIND_SPECS` |
| `name` | PARTIAL | duplicated in `get_display_name` rather than read from the file |
| 7 of 10 room kits | BROKEN | generated clones, wrong dimensions and no `Props`; see [`room-templates.md`](room-templates.md) |
| 5 of 10 audio profiles | PLACEHOLDER | point at castle audio files (`generate_expansion_biomes.py:273-274`) |
| Biome loot tables | PLACEHOLDER | hardcoded in `procgen_loot_tables.gd`, not in the biome file; see [`procgen-placements.md`](procgen-placements.md) |
| Biome JSON validation at load | ABSENT | `procgen_biome_loader.gd:5` |
| Biome prop/dressing kits | ABSENT | nine dressing recipes shared across all ten biomes; see [`diorama-room-dressing.md`](diorama-room-dressing.md) |
| Lighting profile in waves mode | PARTIAL | overridden wholesale (`biome_registry.gd:211-215`) |
| Unknown biome id handling | PARTIAL | every lookup silently falls through to `forgotten_castle` (`:44,67,109,281`) |

## Related

- Improvement plan: [`../actual_improvements/biome-registry.md`](../actual_improvements/biome-registry.md)
- [`room-templates.md`](room-templates.md) — the 90 scenes this registry maps
- [`room-graph-procgen.md`](room-graph-procgen.md) — `roomCount`, `requiresSecret`, `roomTemplateIds` consumers
- [`procgen-placements.md`](procgen-placements.md) — `enemyPool`, `bossPool`, `budgets`
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) — the tier list that selects a biome
- [`floor-shell.md`](floor-shell.md) — material consumers
- [`visual-lighting.md`](visual-lighting.md) — lighting profile consumers
- [`audio-director.md`](audio-director.md) — audio profile consumers
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — per-biome props
- [`content-data.md`](content-data.md), [`content-catalog.md`](content-catalog.md) — content loading and validation
- [`tools-scripts.md`](tools-scripts.md) — `generate_expansion_biomes.py`
