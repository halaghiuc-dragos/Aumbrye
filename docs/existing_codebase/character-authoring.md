# Character authoring

How character art gets into the game. The **primary path** is authored voxel manifests: `content/characters/*.json` plus `assets/characters/*/*.voxels.json` loaded by `build_from_manifest()` in `diorama_character_skin.gd`. Player height variants (`player_warden`, `player_warden_compact`, `player_warden_tall`), combat archetypes (`enemy_melee`, `enemy_ranged`, `enemy_brute`, `enemy_hound`, `enemy_shield`, `enemy_dummy`), and ten biome silhouettes (`enemy_biome_castle` … `enemy_biome_umbral`) ship palette-snapped vertex colours via `VoxelMeshBuilder`.

A **fallback path** still exists: unmapped profiles assemble 6–9 runtime `BoxMesh` primitives from the hardcoded `PROFILES` dictionary (`_build_humanoid`). Equipment with `"visual"` blocks can swap head meshes through `apply_equipment()`.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/voxel_grid.gd` | `EDGE := 0.04`, `REQUIRED_PIVOTS`, joint helpers |
| `apps/game/client/scripts/art/characters/voxel_mesh_builder.gd` | Greedy voxel mesh builder + palette snap |
| `apps/game/client/scripts/art/characters/character_rig_catalog.gd` | Manifest loader; `BIOME_ARCHETYPE_IDS`, height-variant resolution |
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | Builds every body; `build_from_manifest`, `build_enemy_body`, `apply_equipment`, appearance overlays |
| `apps/game/client/scripts/art/props/diorama_weapon_kit.gd` | Hand-held weapon meshes (sword, greatsword, dagger, spear, bow, shield, axe, staff, unknown) |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | `add_box()` / materials |
| `apps/game/client/scripts/art/characters/diorama_viewmodel.gd` | First-person arms |
| `apps/game/client/scripts/art/characters/diorama_anim_library.gd` | Procedurally keyframed clips driving pivots |
| `apps/game/client/scripts/save/character_appearance.gd` | Player customization profile (variants, skin, hair, face, trim) |
| `apps/game/client/assets/shared/pixel_diorama_surface.gdshader` | `use_vertex_color` path for authored meshes; procedural pattern for props |
| `content/characters/*.json` | Rig manifests (`character-rig.v1.json` schema) |
| `content/schemas/character-rig.v1.json` | Manifest schema |
| `tools/generate_character_voxels.py` | Generates `.voxels.json` assets and manifests from `tools/voxel-import/archetypes.py` |
| `tools/voxel-import/` | `.vox` conversion, palette snap, mesh grid tests |

## Asset inventory

Character voxel data lives under `apps/game/client/assets/characters/`:

| Archetype | Parts |
|-----------|-------|
| `player_warden` | `head`, `torso`, `arml`, `armr`, `legl`, `legr`, `hair_short`, `hair_long` |
| `enemy_melee`, `enemy_ranged`, `enemy_brute` | six body parts each |
| `enemy_biome_castle`, `enemy_biome_crystal`, `enemy_biome_swamp`, `enemy_biome_frost`, `enemy_biome_cathedral`, `enemy_biome_vault`, `enemy_biome_prism`, `enemy_biome_mire`, `enemy_biome_hollow`, `enemy_biome_umbral` | six body parts each, theme palette from `archetypes.py` |
| `enemy_hound` | quadruped: `torso`, `head`, `tail`, `legl`, `legr`, `legbl`, `legbr` |
| `enemy_shield`, `enemy_dummy` | six body parts each |
| `equipment/` | `iron_helm`, `castle_helm` |

Manifests under `content/characters/` (19 total): three player height variants, six combat archetypes, ten biome archetypes.

## How a body is built

1. `build_player_body()` / `build_enemy_body()` remove any existing `DioramaVisual`, hide legacy meshes, create a new visual root.
2. **Manifest path:** `CharacterRigCatalog.archetype_for_player(profile)` or `archetype_for_enemy(enemy_id, data)` picks the manifest; `build_from_manifest()` instantiates pivots at `joint * VoxelGrid.EDGE`, attaches `ArrayMesh` from `.voxels.json` with `use_vertex_color` materials.
3. **Fallback:** `_build_humanoid()` reads `PROFILES` and attaches `BoxMesh` primitives.
4. **Appearance:** `_apply_player_appearance()` applies bulk joint offsets (no `Root.scale`), skin-tone shader tint, hair voxels, face accents, class armour overlays, hood/visor/trim boxes.
5. **Equipment:** `apply_equipment()` attaches equipment voxel meshes and hides replaced parts.

`build_enemy_body()` signature: `(parent, enemy_type, theme, enemy_id, enemy_data)`. `castle_enemy_base.gd:128` passes enemy id and catalog data so biome melee grunts resolve to `enemy_biome_<theme>` manifests.

### The rig contract

```
DioramaVisual/Root/LegL/Mesh
DioramaVisual/Root/LegR/Mesh
DioramaVisual/Root/Torso/Mesh
DioramaVisual/Root/Torso/Head/Mesh
DioramaVisual/Root/Torso/ArmL/Mesh
DioramaVisual/Root/Torso/ArmL/ShieldMount
DioramaVisual/Root/Torso/ArmR/Mesh
DioramaVisual/Root/Torso/ArmR/WeaponMount
```

`VoxelGrid.REQUIRED_PIVOTS["biped"]` lists every pivot animation clips may key. `diorama_anim_suite._test_rig_contracts` builds each manifest and asserts pivots, track resolution, uniform scale, and `ArrayMesh` leaf meshes.

## Pixel look

- **Authored characters:** vertex colours from `.voxels.json`, snapped to `PixelDioramaStyle.PALETTES` in `VoxelMeshBuilder._snap_to_palette()`. Shader `use_vertex_color` skips per-box procedural cells.
- **Props / fallback boxes:** procedural `triplanar_pattern_uv` in object space (`pixel_diorama_surface.gdshader`).
- **Default viewport:** `480×270` (`pixel_diorama_settings.gd`).

## Customization surface

`character_appearance.gd` profile fields:

| Field | Values | Effect |
|-------|--------|--------|
| `theme` | 11 `PaletteTheme` rows | Body palette |
| `heightVariant` | `compact`, `standard`, `tall` | Manifest selection (`player_warden_*`) |
| `bulkVariant` | `lean`, `standard`, `heavy` | ±1 voxel hip/shoulder joint offset |
| `skinTone` | `warm`, `neutral`, `cool` | `skin_tint` shader uniform on head |
| `hair` | `none`, `short`, `long` | Voxel hair mesh on head |
| `face` | `open`, `stern`, `kind` | Accent boxes on head |
| `head` | `open`, `visor`, `hood` | Visor/hood toggles |
| `trim` | `0`, `1`, `2` | Belt trim / pauldrons |

Class-distinct armour overlays (`_apply_class_armor`) read `CharacterService.class_id` at runtime. Legacy `height`/`bulk` floats migrate via `CharacterAppearance.sanitize()` (save schema v5).

## Validation

| Suite | Checks |
|-------|--------|
| `voxel_grid_suite.gd` | All `assets/characters/**` vertices on `VoxelGrid.EDGE`; colours on palette |
| `diorama_anim_suite.gd` | Required pivots; animation track paths; uniform scale; `ArrayMesh` leaves; weapon kit coverage |
| `content_suite.gd` | Manifest fields; mesh paths exist; equipment visual attach pivots |
| `quality_bar_suite.gd` | CHA-01–CHA-12 regression guards |

CI job `voxel-import` (`.github/workflows/ci.yml`) runs `pytest` on `tools/voxel-import/` and verifies `generate_character_voxels.py` output matches committed assets.

## Current state

| Surface | Status |
|---------|--------|
| Authored voxel meshes | IMPLEMENTED |
| Manifest loader + height variants | IMPLEMENTED |
| Biome enemy silhouettes (10 themes) | IMPLEMENTED |
| Equipment visuals | IMPLEMENTED |
| Pixel-cell coherence (vertex colour) | IMPLEMENTED |
| Appearance without Root.scale | IMPLEMENTED |
| Weapon kit (8 archetypes + unknown) | IMPLEMENTED |
| Customization (skin, hair, face, class armour) | IMPLEMENTED |
| Chunky default preset (480×270) | IMPLEMENTED |
| Rig-contract validation | IMPLEMENTED |
| Voxel generation CI drift check | IMPLEMENTED |
| Box fallback | PARTIAL (error + fallback) |

## Related

- Improvement plan: [`../actual_improvements/character-authoring.md`](../actual_improvements/character-authoring.md) — **FINISHED**
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`character-appearance.md`](character-appearance.md)
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md)
