# Diorama character skin

Builds every character body in the game â€” player, all enemies, all bosses, and the training dummy â€” at runtime. The primary path loads authored voxel manifests from `content/characters/` through `CharacterRigCatalog` and assembles `ArrayMesh` rigs via `VoxelMeshBuilder`. When a manifest or mesh is missing, `PROFILES` plus `_build_humanoid` / `_build_quadruped` provide a `BoxMesh` fallback. On the live play path: `locomotion.gd:74` and `:99` call `build_player_body`, `castle_enemy_base.gd:169` builds every enemy body, `training_grunt.gd` builds the dummy.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | Manifest and box builders, appearance, equipment, weapon mount, first-person visibility, rest-pose collection |
| `apps/game/client/scripts/art/characters/character_rig_catalog.gd` | Loads `content/characters/<archetype>.json`, maps player height/bulk and enemy profile/biome to archetype ids |
| `apps/game/client/scripts/art/characters/voxel_grid.gd` | `EDGE` (0.04 m), `REQUIRED_PIVOTS` contract for `biped` and `quadruped` |
| `apps/game/client/scripts/art/characters/voxel_mesh_builder.gd` | Greedy-merge `ArrayMesh` from `.voxels.json` or prebuilt `.mesh` |
| `apps/game/client/scripts/art/characters/diorama_character_rig_player.gd` | Editor-only reference rig |
| `apps/game/client/scenes/art/diorama_character_rig_player.tscn` | Three-node scene hosting the reference rig |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | `add_box()`, material caches, `make_wall_material()`, `make_surface_material()` |
| `apps/game/client/scripts/art/props/diorama_weapon_kit.gd` | Hand-held weapon meshes attached to `WeaponMount` |
| `apps/game/client/scripts/inventory/inventory_service.gd` | `_apply_equipment_visuals` calls `apply_equipment` on the player `DioramaVisual` |
| `content/characters/*.json` | 25 rig manifests (8 player stature variants, 7 enemy archetypes, 10 biome bipeds) |
| `apps/game/client/assets/characters/**/*.voxels.json` | 119 authored voxel part meshes |

## How it works

### Primary path â€” voxel manifests

`build_from_manifest(visual, archetype_id, theme)` (`diorama_character_skin.gd:733-794`):

1. `CharacterRigCatalog.get_manifest(archetype_id)` loads JSON from `content/characters/<id>.json` (`character_rig_catalog.gd:50-62`).
2. Creates `Root` and walks `parts` in dependency order; each part is a pivot with a `Mesh` child built by `VoxelMeshBuilder.load_mesh(mesh_path, theme)` (`:766-783`).
3. Optional `mount` on a part adds a child pivot (`WeaponMount` / `ShieldMount`) at `meshOffset` (`:784-785`).
4. `extras` (appearance toggles such as `Visor`, `Hood`, `BeltTrim`, `Pauldron`, `PauldronR`) attach through `_attach_manifest_extras` (`:793`, `:797-827`). Names in `APPEARANCE_EXTRAS` (`:32`) start `visible = false`.

Manifest shape (example `content/characters/player_warden.json`): `grid` (0.04), `profile` (`"biped"` or `"quadruped"`), `parts` with `mesh`, `joint`, optional `parent`, `meshOffset`, `mount`; `extras` with `mesh`, `parent`, `offset`; optional `animationLibrary` and `slots`.

`VoxelMeshBuilder.load_mesh` (`voxel_mesh_builder.gd:9-32`) accepts `.voxels.json` (parsed and greedy-merged) or a prebuilt `.mesh` `ArrayMesh` (used by equipment items such as `castle_plate.mesh`).

### Fallback path â€” box primitives

When `build_from_manifest` returns `null`, builders log `push_error` and fall back:

- Player: `_build_humanoid(visual, "player", mats)` (`diorama_character_skin.gd:126-128`).
- Enemy: `_build_humanoid` with resolved profile or `_build_quadruped` for `"hound"` (`:366-383`).
- Dummy: `_build_humanoid(visual, "dummy", mats)` (`:394-397`).

`PixelStyle.add_box(parent, size, position, material, node_name)` (`pixel_diorama_style.gd:442-459`) creates a `MeshInstance3D` with a fresh `BoxMesh`. Honors `AUMBRYE_STD_MAT` for flat gray debug shading (`:454-457`).

`PROFILES` (`diorama_character_skin.gd:53-113`) holds six humanoid box profiles: `player`, `melee`, `ranged`, `shield`, `brute`, `dummy`. Quadruped dimensions are hardcoded in `_build_quadruped` (`:654-693`).

### Player build

`build_player_body(facing, theme = -1)` (`:116-131`):

1. `_remove_visual`, `PixelStyle.hide_legacy_meshes`, `_make_visual`.
2. `CharacterAppearance.from_service()` supplies the profile; theme defaults from `profile["theme"]` when `theme < 0`.
3. `CharacterRigCatalog.archetype_for_player(profile)` picks `player_warden`, `player_warden_compact`, `player_warden_tall`, or compound `_lean` / `_heavy` suffixes (`character_rig_catalog.gd:65-87`).
4. `build_from_manifest` or box fallback, then `_apply_player_appearance`.

`build_preview_body(parent, profile)` (`:134-149`) is the same pipeline against an explicit profile dict (creation screen / hub mirror).

`_apply_player_appearance` (`:170-197`):

- Resets `Root` scale/position (stature is manifest-driven, not root scale).
- Toggles `Visor` / `Hood` visibility from `profile["head"]` via `head.get_node_or_null(PART_VISOR)` (`:179-184`) â€” extras must exist on the manifest.
- Toggles `BeltTrim`, `Pauldron`, `PauldronR` from `trim` (`:185-194`).
- `_apply_skin_tone` sets `skin_tint` on the head `Mesh` shader (`:220-229`).
- `_apply_hair` loads `hair_<style>.voxels.json` when present (`:232-254`).
- `_apply_face` adds accent boxes for `stern` / `kind` faces (`:257-296`).
- `_apply_class_armor` adds a `ClassArmor` box per `CharacterService.class_id` (`:299-351`).

`_apply_bulk_joint_offsets` shifts `LegL`/`LegR`/`ArmL`/`ArmR` by one `VoxelGrid.EDGE` for lean/heavy bulk (`:200-217`).

### Enemy build

`build_enemy_body(parent, enemy_type, theme, enemy_id, enemy_data)` (`:354-384`):

1. `profile_for_enemy_data(data)` (`:434-441`): id contains `hound` â†’ `"hound"`; `brute`/`golem`/`guardian` â†’ `"brute"`; else `data["enemy_type"]` (default `"melee"`). A `"boss"` type is returned verbatim and is **not** in `PROFILES`.
2. `CharacterRigCatalog.archetype_for_enemy(enemy_id, data)` (`character_rig_catalog.gd:90-104`): `hound` â†’ `enemy_hound`; `ranged` â†’ `enemy_ranged`; `shield` â†’ `enemy_shield`; `brute` â†’ `enemy_brute`; `dummy` â†’ `enemy_dummy`; otherwise `BIOME_ARCHETYPE_IDS[theme_for_enemy_id(enemy_id)]` (e.g. `enemy_biome_frost`).
3. `build_from_manifest` or box/quadruped fallback.

`theme_for_enemy_id(enemy_id)` (`:407-431`) splits on the first `_` and maps prefix to `PaletteTheme`: `crystal`, `swamp`, `frost`, `cathedral`, `iron`/`vault`, `prism`, `venom`/`mire`, `glacial`/`hollow`, `umbral`/`dark`, `training`/`castle`/`forgotten` â†’ `CASTLE`; unknown â†’ `CASTLE`. Prefixes `boss` and `miniboss` therefore resolve to `CASTLE`.

### Training dummy

`build_training_dummy` (`:387-397`) prefers manifest `enemy_dummy`; accent material uses `make_material(ARENA_DUMMY_ACCENT, ARENA_DUMMY_GLOW)` on fallback. Manifest includes a `TargetStripe` extra.

### Equipment visuals

`apply_equipment(visual, equipped, theme)` (`:852-867`) clears prior `EquipVisual_*` nodes, then for each equipped slot reads `ItemCatalog.get_definition(item_id)["visual"]` and calls `_apply_equipment_visual`. Visual dict keys: `attach` (pivot name), `mesh` (`.voxels.json` or `.mesh`), `hide` (array of pivot names to set invisible). Wired from `inventory_service.gd:399-409`. Only `castle_helm`, `castle_plate`, and `iron_helm` ship a `visual` block today.

### Weapon attachment

`attach_weapon(visual, weapon_id, theme)` (`:454-484`): finds `WeaponMount`; frees children except `Bow`/`Shield` pivots on that mount (`:459-462`); `WeaponKit.build` parents the kit; `bow` kits route to a `Bow` pivot; `spear` gets a fixed offset/rotation; `ViewRoot` disables shadow casting.

### First-person visibility

`apply_first_person(facing, enabled)` (`:502-514`): `Torso` subtree â†’ `SHADOW_CASTING_SETTING_SHADOWS_ONLY`; weapon mounts hidden from shadow cast when enabled. On disable, `_set_meshes_visible(visual, true)` re-shows every `GeometryInstance3D`, which can override appearance-driven `visible` on `Visor`/`Hood` (`:513-514` vs `:179-184`).

### Rest pose

`collect_rest_pose(visual)` (`:446-451`, `:704-716`) records every child `Node3D` that is not a `MeshInstance3D`, keyed by name with `path`, `position`, `rotation`. `Mesh`, `Visor`, `Hood`, and equipment overlays are not animatable.

| Archetype family | Rest-pose keys (typical) | Count |
|------------------|--------------------------|-------|
| Biped manifests (`profile: "biped"`) | `Root`, `LegL`, `LegR`, `Torso`, `Head`, `ArmL`, `ArmR`, `ShieldMount`, `WeaponMount` | 9 |
| `enemy_ranged` | above + `Bow` | 10 |
| `enemy_shield` | above + `Shield` | 10 |
| `enemy_hound` (`profile: "quadruped"`) | `Root`, `Torso`, `Head`, `Tail`, `LegL`, `LegR`, `LegBL`, `LegBR` | 8 |

`VoxelGrid.REQUIRED_PIVOTS` (`voxel_grid.gd:8-29`) defines the contract validated by `diorama_anim_suite.gd:303-345`.

## Node-name contract

```
DioramaVisual                       (_make_visual, :719-723)
â””â”€â”€ Root                            (:749)
    â”œâ”€â”€ LegL / LegR                 biped legs
    â”œâ”€â”€ Torso
    â”‚   â”œâ”€â”€ Mesh                    ArrayMesh (voxel) or BoxMesh (fallback)
    â”‚   â”œâ”€â”€ Head
    â”‚   â”‚   â”œâ”€â”€ Mesh
    â”‚   â”‚   â”œâ”€â”€ Visor / Hood / Hair / FaceAccent*   extras or runtime
    â”‚   â”œâ”€â”€ ArmL                    + ShieldMount
    â”‚   â””â”€â”€ ArmR                    + WeaponMount [+ Bow]
    â””â”€â”€ (quadruped) Torso â†’ Head, Tail; LegL/R/BL/BR at root
```

Missing pivot names cause `DioramaAnimLibrary._compile` to drop tracks silently (`diorama_anim_library.gd:530-531`); if every track drops, the clip is absent (`:546-547`).

## Profile coverage of shipped content

30 files in `content/enemies/` and 11 in `content/bosses/` resolve through `profile_for_enemy_data` + `archetype_for_enemy`:

| Resolved profile | Archetype manifest | Example ids |
|------------------|-------------------|-------------|
| `hound` | `enemy_hound` | `castle_hound`, `frost_hound` |
| `brute` | `enemy_brute` | `crystal_guardian`, `crystal_golem` |
| `ranged` | `enemy_ranged` | `castle_archer`, `crystal_bat`, `crystal_wisp`, `swamp_witch` |
| `shield` | `enemy_shield` | `castle_shield` |
| `melee` | `enemy_biome_<theme>` | `castle_grunt`, `frost_knight`, `swamp_slasher` |
| `boss` (not in `PROFILES`) | `enemy_biome_<theme>` â€” same biped as melee | `boss_frost_warlord`, `swamp_hydra`, `miniboss_cathedral_bell` |

`crystal_bat`, `crystal_wisp`, `crystal_slime`, `swamp_leech`, `swamp_swarm`, and `swamp_toad` still render as biped humanoids (ranged or melee archetype). No per-enemy-id silhouette exists beyond the seven archetype families and ten biome palette variants.

## Contracts

- **Node names** â€” `DioramaVisual`, `Root`, `Torso`, `Head`, `ArmL`, `ArmR`, `LegL`, `LegR`, `LegBL`, `LegBR`, `Tail`, `WeaponMount`, `ShieldMount`, `Bow`, `Shield`. Consumed by `DioramaAnimLibrary`, `DioramaAnimController.get_weapon_mount()`, `DioramaViewmodel`, `export_diorama_anim_libraries.gd`.
- **Constants** â€” `VISUAL_NAME`, `ROOT_NAME`, `WEAPON_MOUNT`, `SHIELD_MOUNT`, `FIRST_PERSON_HIDDEN_PARTS`, `APPEARANCE_EXTRAS`, `EQUIP_VISUAL_PREFIX`.
- **Autoload dependencies** â€” `CharacterService` (theme, class, appearance profile), `ItemCatalog` (equipment `visual`), `PixelDioramaSettings` (shader parameters on cached materials).
- **JSON keys read** â€” manifest `parts`/`extras`; enemy `enemy_type`, `id`; appearance `head`, `trim`, `skinTone`, `hair`, `face`, `heightVariant`, `bulkVariant`, `theme`; equipment `visual.attach`, `visual.mesh`, `visual.hide`.
- **Save keys** â€” none written here.
- **`feet_local_y(profile)`** â€” returns `0.0` for every profile (`:403-404`); `character_floor_snap.gd` uses it for visual Y placement.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Primary character geometry is authored voxel `ArrayMesh` from manifests | IMPLEMENTED | `build_from_manifest` `:733-794`; 25 manifests; 119 `.voxels.json` under `assets/characters/` |
| Box-mesh fallback when manifest or mesh load fails | IMPLEMENTED | `:126-128`, `:379-383`, `:591-693` |
| Player stature via manifest variants (compact/tall/lean/heavy) | IMPLEMENTED | `character_rig_catalog.gd:65-87`; 8 `player_warden*` manifests |
| Enemy silhouette vocabulary is seven archetypes + ten biome bipeds | PLACEHOLDER | `archetype_for_enemy` `:90-104`; profile table above |
| `enemy_type: "boss"` renders as biome biped, not a distinct boss rig | PARTIAL | `:434-441`, `character_rig_catalog.gd:103-104` |
| Head style visor/hood toggle on manifest extras | IMPLEMENTED | `_apply_player_appearance` `:179-184`; `player_warden.json` extras |
| Leaving first person re-shows appearance-hidden meshes | BROKEN | `apply_first_person` `:513-514` vs `:179-184` |
| `theme_for_enemy_id` sends `boss_*` / `miniboss_*` to `CASTLE` | BROKEN | `:407-431`; prefix `boss` unmatched â†’ default `CASTLE` |
| `feet_local_y` is a constant stub | STUB | `:403-404` |
| Manifest pivot contract validated in CI | IMPLEMENTED | `diorama_anim_suite.gd:303-345` (`diorama_anim.rig_contract`) |
| Runtime `validate_rig` + bind-time warnings | ABSENT | no symbol in `diorama_character_skin.gd`; `_finish_bind` has no check |
| Hound voxel manifest has no ear pivots; box fallback ears are meshes | PARTIAL | `enemy_hound.json` parts; `_build_quadruped` `:670-675` |
| Quadruped uses biped `LegL`/`LegR` clip amplitudes | PLACEHOLDER | `diorama_anim_library.gd` shared leg tracks |
| Equipment visuals wired but sparse content | PARTIAL | `apply_equipment` `:852-913`; 3 of 78 equipment JSON files have `visual` |
| Box fallback `"body"` material is shared cached wall material | PARTIAL | `_body_materials` `:585`; voxel path uses per-build `_make_voxel_material` duplicate `:842-849` |
| `clear_material_caches` exists but has no call sites | IMPLEMENTED | `pixel_diorama_style.gd:69-73`; `apply_all` uses `restamp_tracked` instead (`pixel_diorama_settings.gd:255-276`) |
| `attach_weapon` `Bow`/`Shield` preservation on `WeaponMount` only | IMPLEMENTED | `:459-462`; `Shield` lives under `ShieldMount`, not scanned here |

## Related
- Improvement plan: [`../actual_improvements/diorama-character-skin.md`](../actual_improvements/diorama-character-skin.md) - **FINISHED**
- [`character-authoring.md`](character-authoring.md), [`../actual_improvements/character-authoring.md`](../actual_improvements/character-authoring.md)
- [`character-appearance.md`](character-appearance.md), [`character-floor-snap.md`](character-floor-snap.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`pixel-style.md`](pixel-style.md), [`enemies.md`](enemies.md), [`bosses.md`](bosses.md)
- Rollups: [`ARCHITECTURE.md`](../ARCHITECTURE.md), [`00-GAME-LOOP.md`](00-GAME-LOOP.md), [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)
