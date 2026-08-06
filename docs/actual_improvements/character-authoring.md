# Character authoring — improvement plan

## Status: FINISHED

## Current state

Authored voxel manifests under `content/characters/` and `assets/characters/*/*.voxels.json` load through `build_from_manifest()` in `diorama_character_skin.gd`. Player height variants (`player_warden`, `player_warden_compact`, `player_warden_tall`) and enemy archetypes (`enemy_melee`, `enemy_ranged`, `enemy_brute`, ten `enemy_biome_*` silhouettes, `enemy_hound`, `enemy_shield`, `enemy_dummy`) ship palette-snapped vertex colours. `build_enemy_body()` resolves biome manifests via `CharacterRigCatalog.archetype_for_enemy()`. `apply_equipment()` handles helm `"visual"` blocks. Unmapped profiles still fall back to `_build_humanoid` box assembly with `push_error`. See [`../existing_codebase/character-authoring.md`](../existing_codebase/character-authoring.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| CHA-01 | P0 | No authored character art exists in any format; all bodies are runtime primitives | `diorama_character_skin.gd:365-451`; zero raster/model/voxel files under `apps/game/client/` | **FINISHED** — `assets/characters/**/*.voxels.json`; `build_from_manifest()` |
| CHA-02 | P0 | No import pipeline for authored character assets — no importer, no source-art directory, no naming convention | `apps/game/client/` has no `*.vox`/`*.png` and no plugin under `addons/` other than `godot_mcp` | **FINISHED** — `VoxelGrid`, `VoxelMeshBuilder`, `tools/generate_character_voxels.py`, `tools/voxel-import/`, `content/characters/*.json`, `character-rig.v1.json` |
| CHA-03 | P0 | Body proportions are hardcoded in GDScript, not content data, so new archetypes require code edits | `diorama_character_skin.gd:32-86` | **FINISHED** — manifests drive joints/meshes; `PROFILES` is fallback only |
| CHA-04 | P0 | Every enemy in the game maps onto one of 6 silhouettes; visual identity is a palette swap keyed off the id prefix | `diorama_character_skin.gd:154-169`, `:199-217` | **FINISHED** — distinct voxel archetypes + `CharacterRigCatalog.BIOME_ARCHETYPE_IDS` + per-biome manifests |
| CHA-05 | P0 | Equipped armour has no visual representation; the body never changes when gear changes | No equipment read anywhere in `diorama_character_skin.gd`; `content/items/equipment/*.json` has no visual key | **FINISHED** — `apply_equipment()` + helm `visual` blocks |
| CHA-06 | P1 | Pixel cells are computed per-box in object space, so cells do not align between torso, head, and limbs of the same body | `pixel_diorama_surface.gdshader:43-48` | **FINISHED** — `use_vertex_color` + palette-snapped `ARRAY_COLOR` meshes |
| CHA-07 | P1 | Appearance `height`/`bulk` apply non-uniform `Root.scale`, which rescales object-space pixel cells and shears child boxes | `diorama_character_skin.gd:107` | **FINISHED** — height manifests (`player_warden_compact`/`_tall`); bulk via joint offsets; no `Root.scale` |
| CHA-08 | P1 | Weapon kit resolves only 6 ids; every other weapon silently renders as a generic sword | `diorama_weapon_kit.gd:37-53` (`_:` branch) | **FINISHED** — axe, staff, expanded aliases; `unknown` mesh + `push_warning` |
| CHA-09 | P1 | Customization is 4 axes of box scale/toggle — no face, hair, skin tone, or class-distinct armour | `character_appearance.gd:8-20` | **FINISHED** — `skinTone`, `hair`, `face`, class armour overlays; creation UI updated |
| CHA-10 | P1 | Chunky pixel look is off by default: the default preset is native 1080p with `pixel_scale: 2.0` | `pixel_diorama_settings.gd:64-75` | **FINISHED** — default viewport `480×270` |
| CHA-11 | P2 | Code and comments claim "voxel" and a "0.02 m grid" that nothing implements or enforces | `diorama_weapon_kit.gd:3,7`; `pixel_diorama_surface.gdshader:40` | **FINISHED** — comments reference `VoxelGrid.EDGE` (0.04 m); shader documents vertex-colour path |
| CHA-12 | P2 | No authoring-side validation: nothing checks that a body satisfies the pivot-name rig contract | `diorama_anim_library.gd` keys tracks by name with no contract assertion | **FINISHED** — `diorama_anim_suite._test_rig_contracts`, `voxel_grid_suite`, `content_suite._test_equipment_visual_pivots` |

## Target design

### Decision: authored voxel models, mesh-rendered, on the existing pivot rig

The game is 3D with an orbit camera, lock-on, a first-person mode, dynamic lights, and real shadows. "Made of pixels" in that context means **voxels**: an artist places discrete coloured cells in a 3D grid, and each body part is exported as a mesh whose faces land exactly on cell boundaries.

Alternatives and why they are rejected:

| Alternative | Rejected because |
|-------------|------------------|
| 2D sprites / 8-direction billboards | Breaks lock-on framing, free orbit yaw, first-person arms, and per-limb animation already in use |
| Sprite-stacked slices | Silhouette falls apart at the low camera pitch used here; shadow casting becomes incorrect |
| Pixel textures on the current boxes | Keeps the blockout silhouette, which is the actual complaint; texel density still fights `root.scale` |
| Runtime voxel engine (chunked, editable) | Enormous cost for zero gameplay benefit; characters are not destructible |

Keeping the mesh-per-part model means `DioramaAnimLibrary`, `DioramaAnimController`, `DioramaViewmodel`, `MaterialFlash`, `MaterialDissolve`, `CharacterFloorSnap`, and the hitbox/hurtbox layout all keep working: only the leaf `Mesh` node's `mesh` resource changes from `BoxMesh` to an imported `ArrayMesh`.

### Voxel grid

Fix a single global voxel edge of **0.04 m**, declared once as `VoxelGrid.EDGE := 0.04` in `apps/game/client/scripts/art/characters/voxel_grid.gd`.

### Source art and format

- Source models live in `art-source/characters/<archetype>/<part>.vox` (MagicaVoxel `.vox`).
- Runtime meshes are committed as `res://assets/characters/<archetype>/<part>.voxels.json`, generated by `tools/generate_character_voxels.py` from `tools/voxel-import/archetypes.py`.
- `tools/voxel-import/` also converts `.vox` → intermediate `.mesh.json` for palette/grid unit tests and optional `.mesh` export.

### Rig manifest

Schema `content/schemas/character-rig.v1.json`, instances under `content/characters/<archetype>.json`. `joint` values are integer voxel coordinates; loader multiplies by `grid`.

### Equipment visuals (CHA-05)

Optional `"visual"` block on equipment JSON; `apply_equipment()` attaches meshes and hides replaced parts.

### Pixel-cell coherence (CHA-06, CHA-07)

Vertex colours from authored voxels; `use_vertex_color` shader path. Height/bulk via discrete manifests and joint offsets, not `Root.scale`.

### Fallback behaviour

Missing manifest logs `push_error` and falls back to box body.

## Work plan

1. **Grid and contract module** — `voxel_grid.gd`, `character-rig.v1.json`. **Done.**
2. **Rig-contract validation** — `diorama_anim_suite._test_rig_contracts`. **Done.**
3. **Converter** — `tools/voxel-import/` + `tools/generate_character_voxels.py`. **Done.**
4. **Shader vertex-colour path** — `use_vertex_color` in `pixel_diorama_surface.gdshader`. **Done.**
5. **Manifest loader** — `build_from_manifest()`. **Done.**
6. **First archetype end to end** — `player_warden`. **Done.**
7. **Enemy archetypes** — `enemy_melee`/`ranged`/`brute` + ten `enemy_biome_*` manifests. **Done.**
8. **Weapon kits** — expanded kits + `unknown` mesh. **Done.**
9. **Equipment visuals** — `apply_equipment()` + helm visuals. **Done.**
10. **Appearance rework** — variants, skin/hair/face, save v5. **Done.**
11. **Default preset** — `480×270`. **Done.**
12. **Comment cleanup** — voxel grid comments. **Done.**
13. **CI** — `voxel-import` job runs pytest + `generate_character_voxels.py` drift check. **Done.**

## Data and schema changes

| Change | File |
|--------|------|
| Character rig manifest schema | `content/schemas/character-rig.v1.json` |
| Manifest instances (19 archetypes) | `content/characters/<archetype>.json` |
| Optional `visual` block on equipment | `content/schemas/item-catalog.v1.json`, `content/items/equipment/*.json` |
| Appearance variant ids | `content/schemas/character-state.v1.json` |
| Save bump | `save_migrator.gd` v4 → v5 |
| Source-art tree | `art-source/characters/**` |
| Runtime voxel meshes | `apps/game/client/assets/characters/**/*.voxels.json` |

## Acceptance criteria

- [x] Every part mesh on the manifest happy path loads from committed `*.voxels.json` via `VoxelMeshBuilder`; no `BoxMesh` on that path.
- [x] Running `tools/generate_character_voxels.py` reproduces committed `.voxels.json` and manifests (CI `voxel-import` job).
- [x] Every authored voxel dimension is an integer multiple of `VoxelGrid.EDGE` (`voxel_grid_suite.gd`).
- [x] Vertex colours snap to `PixelDioramaStyle.PALETTES` (`voxel_grid_suite.gd`).
- [x] Greedy meshes respect triangle budget checks in `voxel_grid_suite.gd` where asserted.
- [x] Animation track paths resolve on built manifest bodies (`diorama_anim_suite._test_rig_contracts`).
- [x] Missing manifest logs error and falls back to box body without crash.
- [x] Ten biome-distinct enemy silhouettes (`enemy_biome_castle` … `enemy_biome_umbral`).
- [x] Items with `"visual"` change the body in one frame via `apply_equipment()`.
- [x] No non-uniform `Root.scale` on manifest bodies (`diorama_anim_suite` / `quality_bar_suite`).

## Validation

| Suite | Assertions |
|-------|------------|
| `diorama_anim_suite.gd` | Required pivots per manifest; animation track paths; uniform scale; leaf meshes are `ArrayMesh` not `BoxMesh`; weapon kit coverage |
| `content_suite.gd` | Manifest schema fields; mesh paths exist; equipment `visual.attach` pivots exist on player rig |
| `voxel_grid_suite.gd` | Vertices on `VoxelGrid.EDGE`; vertex colours on palette (all `assets/characters/**` trees) |
| `quality_bar_suite.gd` | CHA-01–CHA-12 regression guards |

Manual checklist (not automatable): read silhouettes at the `320×180` preset from the third-person boom; confirm first-person arms and a swinging weapon do not clip the near plane.

## Related

- Current state: [`../existing_codebase/character-authoring.md`](../existing_codebase/character-authoring.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-anim-controller.md`](diorama-anim-controller.md)
- [`pixel-style.md`](pixel-style.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md)
- [`character-appearance.md`](character-appearance.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`enemies.md`](enemies.md)
- [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)
