# Biome registry — improvement plan

## Current state

A biome is split between a JSON file that holds only procgen numbers and a GDScript file that hardcodes everything the player actually sees. Adding a biome means editing five `match` statements, a new `preload` dictionary, `RoomTemplateCatalog`, `DungeonCatalog`, `ProcgenLootTables`, and the C# `BiomeCatalog`. Two of the eight schema-required JSON fields (`gridStep`, `budgets.baseLootValue`/`lootPerTier`) are read by nothing. Seven of the ten room kits, and five of the ten audio profiles, were produced by `tools/generate_expansion_biomes.py` as clones. See [`../existing_codebase/biome-registry.md`](../existing_codebase/biome-registry.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| BIO-01 | P0 | Everything visible about a biome — room scenes, materials, lighting, display name, asset folder — is hardcoded in GDScript, so a biome cannot be added or retuned as data | `biome_registry.gd:23,47,112,260,284-421` |
| BIO-02 | P1 | Biome JSON is loaded with no schema validation and no cache; a malformed file degrades silently | `procgen_biome_loader.gd:5` |
| BIO-03 | P1 | `gridStep` is schema-required and read by nothing; room spacing comes from `KIND_SPECS` half-extents instead | `content/biomes/forgotten_castle.json:8`, `content/schemas/biome-definition.v1.json:8,21`; no GDScript reader |
| BIO-04 | P1 | `budgets.baseLootValue` and `budgets.lootPerTier` are schema-required and read by nothing, so loot does not scale per biome or per tier | `content/biomes/forgotten_castle.json:33,35`; see [`procgen-placements.md`](procgen-placements.md) PLC-03 |
| BIO-05 | P1 | Loot and trap tables live in `procgen_loot_tables.gd` keyed by biome id rather than in the biome file | `procgen_loot_tables.gd:7-80` |
| BIO-06 | P1 | Five audio profiles point at the castle's `ambience_loop.wav` and `boss_theme.wav`, so half the biomes sound identical | `generate_expansion_biomes.py:273-274` |
| BIO-07 | P1 | Nine of the ten biomes have a single-entry `bossPool`, so their boss is fixed forever | `content/biomes/umbral_chapel.json` and the four other generated files (`generate_expansion_biomes.py:248`) |
| BIO-08 | P2 | All 90 room scenes are `preload`ed, so every biome's kit is resident regardless of which one is playing | `biome_registry.gd:284-421` |
| BIO-09 | P2 | `name` is duplicated between the JSON file and `get_display_name()` | `biome_registry.gd:23-44` vs `content/biomes/*.json` |
| BIO-10 | P2 | Every unknown-biome lookup silently falls back to `forgotten_castle` instead of erroring | `biome_registry.gd:44,67,109,281` |
| BIO-11 | P2 | The waves branch of `apply_run_presentation` overrides the biome's ambient color and energy outright, so the lighting profile barely applies | `biome_registry.gd:211-215` |
| BIO-12 | P2 | `get_ceiling_material` is an alias for the wall material, so ceilings can never be art-directed separately | `biome_registry.gd:79-80` |
| BIO-13 | P2 | Adding a biome requires coordinated edits in at least seven files across two language stacks | `biome_registry.gd`, `room_template_catalog.gd:26`, `dungeon_catalog.gd`, `procgen_loot_tables.gd`, `packages/procedural/Biome/BiomeCatalog.cs`, `RoomTemplateCatalog.cs` |

## Target design

One biome is one JSON file plus one asset folder. `BiomeRegistry` becomes a thin cached loader over that file, and the only thing that stays in code is the fallback behavior when a biome is missing.

### 1. The biome kit (BIO-01, BIO-05, BIO-09, BIO-12)

Extend `content/biomes/<id>.json` into a full kit. New top-level blocks, all schema-required except where noted:

```json
{
  "id": "forgotten_castle",
  "name": "Forgotten Castle",
  "templatePrefix": "castle",
  "assetFolder": "castle",

  "roomCount": { "min": 18, "max": 22 },
  "roomTemplateIds": [ ... 10 entries including castle_corridor ],
  "requiresSecret": true,

  "materials": {
    "floor":   "res://assets/castle/mat_floor.tres",
    "wall":    "res://assets/castle/mat_wall.tres",
    "ceiling": "res://assets/castle/mat_ceiling.tres",
    "accent":  "res://assets/castle/mat_accent.tres"
  },

  "lighting": {
    "ambientColor": [0.58, 0.50, 0.44],
    "ambientEnergy": 0.78,
    "fogEnabled": false,
    "fogColor": [0.20, 0.18, 0.22],
    "fogDensity": 0.008,
    "torchColor": [1.0, 0.72, 0.38],
    "torchEnergy": 2.2
  },

  "audioProfile": "content/audio_profiles/forgotten_castle.json",

  "propKit": {
    "pillar": "res://scenes/props/castle/pillar.tscn",
    "sconce": "res://scenes/props/castle/sconce.tscn",
    "rubble": ["res://scenes/props/castle/rubble_a.tscn", "res://scenes/props/castle/rubble_b.tscn"]
  },

  "enemyPool": [ ... ],
  "bossPool": [ { "enemyId": "boss_castle_knight", "weight": 3 }, { "enemyId": "miniboss_castle_captain", "weight": 1 } ],
  "budgets": { "baseEnemyThreat": 200, "baseLootValue": 80, "threatPerTier": 35, "lootPerTier": 14 },
  "lootTables": { "treasure": [...], "secret": [...], "side": [...], "armory": [...] },
  "trapPool": [ { "trapId": "spike_trap", "weight": 3 }, { "trapId": "falling_trap", "weight": 1 } ]
}
```

`templatePrefix` replaces `RoomTemplateCatalog.template_prefix_for_biome()`. `assetFolder` and the explicit `materials` paths replace `_material_path()`, and `materials.ceiling` gives ceilings their own material (BIO-12). `lighting` replaces `get_lighting_profile()`. `name` becomes the single source for `get_display_name()` (BIO-09). `propKit` is the data hook [`diorama-room-dressing.md`](diorama-room-dressing.md) and [`room-templates.md`](room-templates.md) RTP-04 need so a theme's props are declared rather than coded. `lootTables` and `trapPool` come from [`procgen-placements.md`](procgen-placements.md) (BIO-05).

Room scenes are resolved by convention from `templatePrefix`: `res://scenes/rooms/<assetFolder>/<templatePrefix>_<kind>.tscn` for each kind in `RoomTemplateCatalog.KIND_SPECS`. No dictionary needed, and the suite asserts every path exists.

`gridStep` is deleted from the schema and from all ten files: room spacing genuinely comes from `KIND_SPECS`, and keeping a second unused number invites someone to "fix" spacing by editing it (BIO-03).

### 2. Cached, validated loading (BIO-02, BIO-08, BIO-10)

`BiomeRegistry` gains a static cache:

```gdscript
static var _cache: Dictionary = {}          # biome_id -> Dictionary

static func get_biome(biome_id: String) -> Dictionary:
    if _cache.has(biome_id):
        return _cache[biome_id]
    var data := ContentLoader.load_json("content/biomes/%s.json" % biome_id)
    if data.is_empty():
        push_error("BiomeRegistry: unknown biome '%s'" % biome_id)
        return {}
    _cache[biome_id] = data
    return data
```

Every accessor (`get_display_name`, `get_room_scenes`, `get_floor_material`, `get_lighting_profile`, `get_audio_profile_path`) reads from this dictionary. An unknown id returns empty and pushes an error rather than silently becoming the castle (BIO-10); the one place a fallback is legitimate is `resolve_biome_id(definition, fallback)`, which keeps it because old saves may lack `biomeId`.

`get_room_scenes` switches from `preload` to `ResourceLoader.load` with a per-biome cache, so only the active biome's kit is resident (BIO-08). `ProcgenBiomeLoader` is deleted and its callers use `BiomeRegistry.get_biome`, giving one loader with one cache (BIO-02).

Validation runs in two places: `scripts/validate-content/validate.mjs` in CI against the extended schema, and a startup assertion in the validation suite that loads all ten biomes and checks every referenced resource path resolves.

### 3. Distinct audio and bosses (BIO-06, BIO-07)

Each biome gets its own `ambiencePath` and `bossPath`. Until authored audio exists, point them at distinct generated stems rather than the castle's files, and mark the profiles `PLACEHOLDER` in [`audio-director.md`](audio-director.md) so the gap is visible instead of hidden behind an identical path.

Each biome's `bossPool` grows to at least two weighted entries so the floor boss varies, using the minibosses that already exist per theme (`generate_expansion_biomes.py:33,62,91,120,149` lists one per biome). Weighted selection is implemented in [`procgen-placements.md`](procgen-placements.md) PLC-11.

### 4. One place to add a biome (BIO-13)

After the above, adding a biome is: one JSON file, one asset folder with four materials, ten room scenes, one audio profile, and one `DungeonCatalog` entry (which is itself moved to data — see [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) DCT-01). The C# `BiomeCatalog` and `RoomTemplateCatalog.cs` read the same JSON files rather than duplicating them, which also removes the parity risk in [`room-graph-procgen.md`](room-graph-procgen.md) RGP-05.

`ALL_BIOMES` is derived by listing `content/biomes/*.json` at startup rather than hand-maintained.

### 5. Lighting that survives run mode (BIO-11)

`apply_run_presentation` stops overwriting biome ambient values in waves mode. Instead the waves branch multiplies: `ambient_energy = max(profile_energy, profile_energy * 1.3)` and `background_color = ambient.lerp(waves_tint, 0.4)`, so an umbral arena still reads as umbral. `ArenaFillLight` uses the biome's `lighting.torchColor` rather than a fixed purple.

## Work plan

1. **Extend the schema** — add `templatePrefix`, `assetFolder`, `materials`, `lighting`, `audioProfile`, `propKit`, `lootTables`, `trapPool`; remove `gridStep`; make `bossPool[].weight` optional (BIO-01, BIO-03, BIO-05).
2. **Author the ten kit files** — transcribe the current hardcoded values so the change is behavior-preserving before any tuning (BIO-01).
3. **`BiomeRegistry.get_biome` cache** — add the loader; rewrite the five accessors against it; delete the five `match` statements and the ten `preload` dictionaries (BIO-01, BIO-02, BIO-08, BIO-09, BIO-10).
4. **Delete `ProcgenBiomeLoader`** — repoint `DungeonProcgen` at `BiomeRegistry.get_biome` (BIO-02).
5. **Delete `template_prefix_for_biome`** — `RoomTemplateCatalog` reads `templatePrefix` (BIO-13).
6. **Loot and trap tables** — move from `procgen_loot_tables.gd`, land with [`procgen-placements.md`](procgen-placements.md) step 5 (BIO-04, BIO-05).
7. **Ceiling material** — add `mat_ceiling.tres` per folder, use it in `FloorShellBuilder`/`CastleBlockout` (BIO-12; ceiling ownership moves per [`floor-shell.md`](floor-shell.md) FSH-04).
8. **Audio and boss variety** — distinct audio paths, two-entry weighted boss pools (BIO-06, BIO-07).
9. **Waves lighting** — multiplicative rather than absolute overrides (BIO-11).
10. **C# reads the JSON** — `BiomeCatalog.cs` and `RoomTemplateCatalog.cs` load `content/biomes/*.json` (BIO-13).

## Data and schema changes

- `content/schemas/biome-definition.v1.json` — the full block above. `additionalProperties: false` stays; every new block is validated. Because the file is versioned `.v1`, and the changes are additive except for removing `gridStep`, bump to `biome-definition.v2.json` and keep the v1 file until the C# side migrates. `scripts/validate-content/validate.mjs` validates against v2.
- All 10 `content/biomes/*.json` rewritten to the new shape.
- New `apps/game/client/assets/<folder>/mat_ceiling.tres` x 10.
- New `apps/game/client/scenes/props/<folder>/` prop scenes referenced by `propKit`.
- No save-format change: only `biomeId` is persisted, and it is unchanged.

## Acceptance criteria

- [ ] `biome_registry.gd` contains no `match biome_id` statement and no `preload` of a room scene (BIO-01).
- [ ] For all 10 biomes, every path in `materials`, `propKit`, `audioProfile`, and every derived room scene path resolves to an existing resource (BIO-01, BIO-02).
- [ ] Loading a biome twice performs one file read (BIO-02).
- [ ] `gridStep` does not appear in any file under `content/` or `apps/game/client/scripts/` (BIO-03).
- [ ] For tiers 1 and 5 of the same biome, generated loot value differs in line with `lootPerTier` (BIO-04; asserted in [`procgen-placements.md`](procgen-placements.md)).
- [ ] No two biomes share an `ambiencePath` or `bossPath` (BIO-06).
- [ ] Every biome's `bossPool` has at least 2 entries (BIO-07).
- [ ] `BiomeRegistry.get_biome("nonexistent")` returns `{}` and pushes an error; no accessor returns castle data for it (BIO-10).
- [ ] In waves mode, the applied `ambient_light_color` is derived from the biome's `lighting.ambientColor` (BIO-11).
- [ ] `get_ceiling_material(id) != get_wall_material(id)` for all 10 biomes (BIO-12).
- [ ] `ALL_BIOMES` is derived from the directory listing and has 10 entries (BIO-13).
- [ ] All 10 files validate against `biome-definition.v2.json` under `node scripts/validate-content/validate.mjs` (BIO-01).

## Validation

New suite `apps/game/client/scripts/validation/suites/biome_kit_suite.gd`:

- `test_all_biomes_load` — for each id in `ALL_BIOMES`, assert `get_biome` returns a non-empty dictionary with every required key.
- `test_all_resource_paths_resolve` — assert `ResourceLoader.exists` for every material, prop, and derived room scene path across all 10 biomes.
- `test_room_scene_convention` — for each biome and each kind in `KIND_SPECS`, assert `res://scenes/rooms/<assetFolder>/<templatePrefix>_<kind>.tscn` exists and instantiates as a `RoomTemplate`.
- `test_biome_cache_single_read` — instrument `ContentLoader.load_json` with a counter; call `get_biome` twice; assert 1.
- `test_unknown_biome_errors` — assert `get_biome("nope")` is empty and no accessor returns castle values.
- `test_boss_pool_variety` — assert every biome has 2 or more `bossPool` entries with weights.
- `test_audio_paths_distinct` — assert 10 distinct `ambiencePath` values.
- `test_lighting_applied_per_mode` — call `apply_run_presentation` for castle, endless, and waves with `umbral_chapel`; assert the resulting `ambient_light_color` is within 0.25 of the profile's color in all three.
- `test_no_grid_step` — assert `get_biome(id).has("gridStep") == false` for all 10.

Extend `apps/game/client/scripts/validation/suites/content_suite.gd`:

- `test_biome_schema_v2` — assert every `content/biomes/*.json` has exactly the v2 key set.

Extend `apps/game/client/scripts/validation/suites/cross_stack_parity_suite.gd` (see [`room-graph-procgen.md`](room-graph-procgen.md) RGP-05):

- `test_biome_catalog_parity` — assert the C# `BiomeCatalog` reports the same ids, room counts, and template prefixes as the JSON files.

## Related

- [`../existing_codebase/biome-registry.md`](../existing_codebase/biome-registry.md)
- [`room-templates.md`](room-templates.md) — RTP-04 authored kits, RTP-08 corridor kind
- [`procgen-placements.md`](procgen-placements.md) — PLC-01 loot tables, PLC-03 loot budget, PLC-11 boss weights
- [`room-graph-procgen.md`](room-graph-procgen.md) — RGP-05 parity, `roomCount` and `requiresSecret`
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) — DCT-01 tier list to data
- [`floor-shell.md`](floor-shell.md) — FSH-04 ceiling ownership, material consumers
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — `propKit` consumer
- [`visual-lighting.md`](visual-lighting.md) — lighting block consumer
- [`audio-director.md`](audio-director.md) — audio profile consumer
- [`content-data.md`](content-data.md) — schema validation pipeline
