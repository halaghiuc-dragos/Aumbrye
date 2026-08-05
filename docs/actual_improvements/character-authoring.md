# Character authoring — improvement plan

## Current state

Characters are not art; they are runtime box assemblies. `DioramaCharacterSkin` builds every player, enemy, boss, NPC, and dummy from 6-9 `BoxMesh` primitives sized by a hardcoded `PROFILES` dictionary, and the pixel appearance comes only from a procedural object-space shader pattern plus an optional low-res render pass. The repository contains **zero** authored character assets in any format. See [`../existing_codebase/character-authoring.md`](../existing_codebase/character-authoring.md) for the verified inventory.

The gap this doc closes: the game reads as a blockout with a pixel filter on it, not as a pixel-art game. Characters should be **authored from voxels** — discrete coloured cells placed by an artist — and rendered as meshes that keep the existing pivot rig, so animation, combat, and camera work continue unchanged.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CHA-01 | P0 | No authored character art exists in any format; all bodies are runtime primitives | `diorama_character_skin.gd:365-451`; zero raster/model/voxel files under `apps/game/client/` |
| CHA-02 | P0 | No import pipeline for authored character assets — no importer, no source-art directory, no naming convention | `apps/game/client/` has no `*.vox`/`*.png` and no plugin under `addons/` other than `godot_mcp` |
| CHA-03 | P0 | Body proportions are hardcoded in GDScript, not content data, so new archetypes require code edits | `diorama_character_skin.gd:32-86` |
| CHA-04 | P0 | Every enemy in the game maps onto one of 6 silhouettes; visual identity is a palette swap keyed off the id prefix | `diorama_character_skin.gd:154-169`, `:199-217` |
| CHA-05 | P0 | Equipped armour has no visual representation; the body never changes when gear changes | No equipment read anywhere in `diorama_character_skin.gd`; `content/items/equipment/*.json` has no visual key |
| CHA-06 | P1 | Pixel cells are computed per-box in object space, so cells do not align between torso, head, and limbs of the same body | `pixel_diorama_surface.gdshader:43-48` |
| CHA-07 | P1 | Appearance `height`/`bulk` apply non-uniform `Root.scale`, which rescales object-space pixel cells and shears child boxes | `diorama_character_skin.gd:107` |
| CHA-08 | P1 | Weapon kit resolves only 6 ids; every other weapon silently renders as a generic sword | `diorama_weapon_kit.gd:37-53` (`_:` branch) |
| CHA-09 | P1 | Customization is 4 axes of box scale/toggle — no face, hair, skin tone, or class-distinct armour | `character_appearance.gd:8-20` |
| CHA-10 | P1 | Chunky pixel look is off by default: the default preset is native 1080p with `pixel_scale: 2.0` | `pixel_diorama_settings.gd:64-75` |
| CHA-11 | P2 | Code and comments claim "voxel" and a "0.02 m grid" that nothing implements or enforces | `diorama_weapon_kit.gd:3,7`; `pixel_diorama_surface.gdshader:40` |
| CHA-12 | P2 | No authoring-side validation: nothing checks that a body satisfies the pivot-name rig contract | `diorama_anim_library.gd` keys tracks by name with no contract assertion |

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

Fix a single global voxel edge of **0.04 m**, declared once as `VoxelGrid.EDGE := 0.04` in a new `apps/game/client/scripts/art/characters/voxel_grid.gd`.

Derivation, using the project's own numbers: `PixelDioramaSettings.camera_snap_step(75.0, 5.0)` is the world height of one rendered pixel at the third-person boom. At the `480 x 270` preset this is `2 * 5 * tan(37.5 deg) / 270 = 0.0284` m. A voxel must be at least one rendered pixel or it cannot be seen, so 0.04 m gives ~1.4 rendered pixels per voxel at the chunkiest playable preset and ~5.6 at native 1080p.

At 0.04 m, the current player proportions become clean voxel counts:

| Part | Current metres | Voxels |
|------|---------------|--------|
| Leg | 0.22 x 0.46 x 0.26 | 6 x 12 x 6 (0.24 x 0.48 x 0.24) |
| Torso | 0.5 x 0.62 x 0.34 | 12 x 16 x 8 (0.48 x 0.64 x 0.32) |
| Head | 0.32 cube | 8 cube (0.32) |
| Arm | 0.2 x 0.52 x 0.2 | 5 x 13 x 5 (0.20 x 0.52 x 0.20) |

Total player height 0.48 + 0.64 + 0.32 = **1.44 m = 36 voxels**. Every authored asset must be an exact multiple of the grid; the importer rejects anything that is not.

### Source art and format

- Source models live in a new tracked directory `art-source/characters/<archetype>/<part>.vox` (MagicaVoxel `.vox`, also written by Goxel and VoxEdit). `.vox` is chosen over per-slice PNG because it stores the palette index per cell natively and is the format every voxel editor exports.
- A build step converts each `.vox` into an optimized `res://assets/characters/<archetype>/<part>.mesh` (`ArrayMesh`) plus a `<archetype>.json` manifest. Godot cannot import `.vox` natively, so conversion happens offline rather than through an editor plugin — this keeps the client free of an addon dependency and makes the output reviewable in git.
- Converter lives at `tools/voxel-import/` (Python, consistent with the existing `tools/` + `pyproject.toml` + `ruff` setup) and is invoked by `scripts/` and by CI.

Converter requirements:

1. **Greedy quad merge** over each axis-aligned slab so a flat 12 x 16 face becomes one quad, not 192. Target under 400 triangles per part after merging.
2. **Interior culling** — never emit a face between two solid voxels.
3. **Vertex colour output**, not a texture. Colours come from the `.vox` palette and are written to `ARRAY_COLOR`. This removes texture memory, UV authoring, and filtering questions entirely, and lets the existing surface shader read `COLOR` instead of a uniform.
4. **Palette snapping** — every source colour must match an entry in the theme palettes defined in `PixelDioramaStyle.PALETTES`, or the converter fails with the offending RGB and the nearest legal colour. This is what keeps authored art on-style.
5. **Deterministic output** so the committed `.mesh` files are byte-stable and diffs are meaningful.
6. **Origin convention** — each part's origin is its joint, matching the current pivot offsets, so `add_box`'s `-size.y * 0.5` offsets disappear.

### Rig manifest

Replace the hardcoded `PROFILES` dictionary with data. New schema `content/schemas/character-rig.v1.json`, instances under `content/characters/<archetype>.json`:

```json
{
  "id": "player_warden",
  "grid": 0.04,
  "profile": "biped",
  "parts": {
    "LegL":  { "mesh": "res://assets/characters/player_warden/leg_l.mesh", "joint": [-3, 12, 0] },
    "LegR":  { "mesh": "res://assets/characters/player_warden/leg_r.mesh", "joint": [3, 12, 0] },
    "Torso": { "mesh": "res://assets/characters/player_warden/torso.mesh", "joint": [0, 12, 0] },
    "Head":  { "mesh": "res://assets/characters/player_warden/head.mesh", "joint": [0, 16, 0], "parent": "Torso" },
    "ArmL":  { "mesh": "res://assets/characters/player_warden/arm_l.mesh", "joint": [-7, 14, 0], "parent": "Torso", "mount": "ShieldMount" },
    "ArmR":  { "mesh": "res://assets/characters/player_warden/arm_r.mesh", "joint": [7, 14, 0], "parent": "Torso", "mount": "WeaponMount" }
  },
  "animationLibrary": "res://assets/animations/diorama/player_locomotion.res",
  "slots": { "head": "Head", "chest": "Torso", "hands": ["ArmL", "ArmR"], "feet": ["LegL", "LegR"] }
}
```

`joint` values are **integer voxel coordinates**, not metres, so authoring and code cannot drift. The loader multiplies by `grid`.

Node names in `parts` are the existing contract (`LegL`, `LegR`, `Torso`, `Head`, `ArmL`, `ArmR`, `WeaponMount`, `ShieldMount`, plus `Tail`, `LegBL`, `LegBR` for `quadruped`), so every existing animation clip keeps working unchanged.

### Equipment visuals (CHA-05)

Add an optional `"visual"` block to equipment JSON:

```json
{ "visual": { "attach": "Head", "mesh": "res://assets/characters/equipment/iron_helm.mesh", "hide": ["Head"] } }
```

`DioramaCharacterSkin` gains `apply_equipment(visual: Node3D, equipped: Dictionary)`, called by `InventoryService`'s equipment-changed signal. Attach adds a child mesh at the named pivot; `hide` suppresses the base part it replaces. Items without a `"visual"` block render nothing, so this ships incrementally.

### Pixel-cell coherence (CHA-06, CHA-07)

- Because colour now comes from `ARRAY_COLOR`, character cells stop being a procedural pattern and the alignment problem disappears at the source. `pixel_diorama_surface.gdshader` gains a `use_vertex_color` uniform; when set, `ALBEDO` takes `COLOR.rgb` and the `shade_prop` pattern is skipped. Banded `light()`, `flash_amount`, and `dissolve_clip` are retained — they are what makes the look cohere with the environment.
- `height`/`bulk` stop being `Root.scale`. Replace with **discrete authored variants** (`_compact`, `_standard`, `_tall` meshes for the affected parts) plus integer joint offsets in the manifest. Non-uniform scale on voxel art always reads as broken; a 36-voxel body has enough resolution for three real height variants.

### Fallback behaviour

`DioramaCharacterSkin` keeps the current box builder as a **named fallback**, not a default. If a manifest or mesh is missing, log `push_error` with the archetype id and build the box body so the game still runs. `PixelDioramaStyle.add_box` stays for architecture and props, which are legitimately blockout geometry.

## Work plan

1. **Grid and contract module** — add `apps/game/client/scripts/art/characters/voxel_grid.gd` with `EDGE := 0.04`, voxel-to-metre helpers, and `REQUIRED_PIVOTS` per profile. Add `content/schemas/character-rig.v1.json`. No behaviour change yet.
2. **Rig-contract validation** — extend `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd` to assert that every body `DioramaCharacterSkin` can build exposes every pivot the corresponding animation library keys. This catches CHA-12 before any art exists and guards the migration.
3. **Converter** — build `tools/voxel-import/` with greedy meshing, interior culling, vertex colours, palette snapping against `PixelDioramaStyle.PALETTES`, and deterministic output. Ship with unit tests on a fixture `.vox`.
4. **Shader vertex-colour path** — add `use_vertex_color` to `pixel_diorama_surface.gdshader`; verify `MaterialFlash` and `MaterialDissolve` still work on the new path.
5. **Manifest loader** — `DioramaCharacterSkin.build_from_manifest(parent, archetype_id)`: reads `content/characters/<id>.json`, instantiates pivots at `joint * grid`, sets imported meshes, falls back to the box builder with `push_error` on any failure. Keep every existing public function signature.
6. **First archetype end to end** — author `player_warden` (6 parts), convert, wire, and confirm all existing player clips, first-person hiding, weapon mounting, floor snap, and hit flash behave identically.
7. **Enemy archetypes** — author distinct voxel bodies for the archetypes named in [`enemies.md`](enemies.md), replacing the 6-profile palette-swap approach (CHA-04). Prioritise one per biome so each biome reads differently.
8. **Weapon kits** — author a voxel mesh per weapon id present in `content/weapons/` and per weapon-class item in `content/items/equipment/`; remove the `_:` sword fallback in favour of an explicit `unknown` mesh plus `push_warning` (CHA-08).
9. **Equipment visuals** — add the `"visual"` block to the item schema, implement `apply_equipment`, and author head/chest/hand/feet meshes for the tier-representative items (CHA-05).
10. **Appearance rework** — replace `Root.scale` with authored height/bulk variants and manifest joint offsets; extend `character_appearance.gd` and `character_create_ui.gd` with the new axes (CHA-07, CHA-09). Bump the save schema.
11. **Default preset** — re-evaluate the default resolution preset now that characters carry authored detail; the chunky presets are the point of the art direction (CHA-10).
12. **Comment cleanup** — correct the "voxel" and "0.02 m grid" claims in `diorama_weapon_kit.gd` and `pixel_diorama_surface.gdshader` (CHA-11).
13. **CI** — add a job that runs the converter over `art-source/` and fails if any committed `.mesh` differs from a fresh conversion, and that validates every `content/characters/*.json` against the schema.

Steps 1-5 land with no visible change. Step 6 is the first visible milestone. Steps 7-10 are per-asset and independently shippable.

## Data and schema changes

| Change | File |
|--------|------|
| New character rig manifest schema | `content/schemas/character-rig.v1.json` |
| New manifest instances | `content/characters/<archetype>.json` |
| Optional `visual` block on equipment | `content/schemas/item-catalog.v1.json`, `content/items/equipment/*.json` |
| Appearance gains variant ids instead of scale floats | `content/schemas/character-state.v1.json` |
| Save bump for the appearance change | `save_migrator.gd` `CURRENT_VERSION` 4 to 5, migrating `appearance.height`/`.bulk` floats to the nearest variant id |
| New source-art tree | `art-source/characters/**` (tracked), converter output `apps/game/client/assets/characters/**` (tracked) |

## Acceptance criteria

- [ ] Every part mesh loaded at runtime came from a committed `.mesh` produced by `tools/voxel-import/`; no character part is a `BoxMesh` on the happy path.
- [ ] Running the converter over `art-source/` reproduces the committed `.mesh` files byte for byte.
- [ ] Every authored voxel dimension is an exact integer multiple of `VoxelGrid.EDGE`; the converter fails otherwise.
- [ ] Every source colour resolves to an entry in `PixelDioramaStyle.PALETTES`; the converter fails otherwise.
- [ ] No part mesh exceeds 400 triangles after greedy merge.
- [ ] Every animation clip that played before the migration plays after it, with no missing-track warnings.
- [ ] Deleting a manifest logs an error and falls back to the box body without crashing.
- [ ] The 10 biomes present at least 10 visually distinct enemy silhouettes, verifiable by differing part meshes rather than palette alone.
- [ ] Equipping any item that declares a `"visual"` block changes the body within one frame; items without one change nothing.
- [ ] No character uses non-uniform node scale anywhere in the rig.

## Validation

Extend `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd`:

- For every archetype in `content/characters/`, build the body and assert every pivot in `VoxelGrid.REQUIRED_PIVOTS[profile]` exists.
- Assert every animation track path in the archetype's animation library resolves to a node in the built body.
- Assert no node in the built body has non-uniform `scale`.
- Assert every leaf `Mesh` node's `mesh` is an `ArrayMesh`, not a `BoxMesh`, when a manifest was found.

Extend `apps/game/client/scripts/validation/suites/content_suite.gd`:

- Every `content/characters/*.json` validates against `character-rig.v1.json`.
- Every `mesh` path in every manifest exists via `ResourceLoader.exists()`.
- Every `content/weapons/*.json` id resolves to a weapon kit mesh (no fallback hit).
- Every equipment `visual.attach` names a pivot that exists in the referenced archetypes.

New suite `apps/game/client/scripts/validation/suites/voxel_grid_suite.gd`:

- Every vertex of every committed part mesh lies on a `VoxelGrid.EDGE` boundary within `1e-4`.
- Every vertex colour matches a palette entry.

Manual checklist (not automatable): read silhouettes at the `320 x 180` preset from the third-person boom and confirm each archetype is identifiable; confirm first-person arms and a swinging weapon do not clip the near plane.

## Related

- Current state: [`../existing_codebase/character-authoring.md`](../existing_codebase/character-authoring.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-anim-controller.md`](diorama-anim-controller.md)
- [`pixel-style.md`](pixel-style.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md)
- [`character-appearance.md`](character-appearance.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`enemies.md`](enemies.md)
- [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)
