# Diorama character skin

Builds every character body in the game — player, all enemies, all bosses, and the training dummy — at runtime out of `BoxMesh` primitives. It is on the live play path: `locomotion.gd:39` builds the player body on `_ready`, `castle_enemy_base.gd:110` builds every enemy body, `training_grunt.gd:37` builds the dummy. There is no authored character art anywhere in the repo: `apps/game/client/assets/` contains only `.tres` materials, `.gdshader` files, `.ogg`/`.wav` audio, six `.res` animation libraries, and `icon.svg`. No sprite, texture, voxel, or mesh asset exists (verified by globbing `apps/game/client` for `*.png,*.jpg,*.jpeg,*.webp,*.svg,*.tga,*.bmp,*.vox,*.gltf,*.glb,*.obj,*.fbx,*.dae,*.aseprite,*.ase` — one hit, `icon.svg`). The "pixel" look is produced entirely by `pixel_diorama_surface.gdshader` shading untextured boxes.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | Profile table, rig assembly, weapon mounting, first-person visibility, rest-pose collection |
| `apps/game/client/scripts/art/characters/diorama_character_rig_player.gd` | Editor-only reference rig; rebuilds the player body and attaches a plain `AnimationPlayer` for clip inspection |
| `apps/game/client/scenes/art/diorama_character_rig_player.tscn` | Three-node scene (`Node3D` + `Facing` + `AnimationPlayer`) that hosts the reference rig |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | `add_box()`, `make_wall_material()`, `make_surface_material()` and the material caches every body part draws with |
| `apps/game/client/scripts/art/props/diorama_weapon_kit.gd` | Hand-held weapon meshes attached to `WeaponMount` |

## What a "mesh" is here

`PixelStyle.add_box(parent, size, position, material, node_name)` (`pixel_diorama_style.gd:422-443`) creates a `MeshInstance3D`, assigns a fresh `BoxMesh` with `box.size = size`, sets `position`, and assigns `material` to `material_override`. That is the entire vocabulary for character geometry — there is no `ArrayMesh`, no `MultiMesh`, no skeleton, no skinning, and no UV authoring. `add_box` also honors the `AUMBRYE_STD_MAT` environment variable (`pixel_diorama_style.gd:438-441`), which replaces the shader material with a flat gray `StandardMaterial3D` for debugging.

Materials come from the caches in `pixel_diorama_style.gd:63-66`. `_body_materials()` (`diorama_character_skin.gd:340-362`) returns:

- `"body"` — `PixelStyle.make_wall_material(theme)`, which is the **shared cached** `ShaderMaterial` for that theme (`pixel_diorama_style.gd:291-292` -> `make_surface_material` -> `_surface_material_cache`). Every body of the same theme references the same instance.
- `"accent"` — a fresh `.duplicate()` of the cached `PROP` surface material with `color_base`, `color_shadow`, and `color_accent` overridden per profile (`diorama_character_skin.gd:343-357`).
- `"theme"` — the integer theme index.

## Node-name contract

Names are a hard contract with `DioramaAnimLibrary`, which keys tracks by part name and resolves them through the path recorded in `collect_rest_pose()`.

### Humanoid rigs (`_build_humanoid`, `diorama_character_skin.gd:365-419`)

```
DioramaVisual                       (Node3D, _make_visual, :477-481)
└── Root                            pivot at (0,0,0), :376
    ├── LegL                        pivot at (-hip_x, leg.y, 0), :379-382
    │   └── Mesh                    BoxMesh size=leg, offset (0,-leg.y/2,0)
    ├── LegR                        pivot at (+hip_x, leg.y, 0)
    │   └── Mesh
    └── Torso                       pivot at (0, leg.y, 0), :384-385
        ├── Mesh                    BoxMesh size=torso, offset (0,+torso.y/2,0)
        ├── Head                    pivot at (0, torso.y, 0), :387-389
        │   ├── Mesh                BoxMesh size=head, offset (0,+head.y/2,0)
        │   └── Visor               only when spec.visor, :390-397
        ├── ArmL                    pivot at (-shoulder_x, torso.y*0.88, 0), :400-403
        │   ├── Mesh                BoxMesh size=arm, offset (0,-arm.y/2,0)
        │   └── ShieldMount         pivot at (0,-arm.y,0), :404-405
        │       └── Shield          only when extras has "shield", :413-417
        │           └── Mesh        BoxMesh 0.12 x 0.58 x 0.46
        └── ArmR                    pivot at (+shoulder_x, torso.y*0.88, 0)
            ├── Mesh
            └── WeaponMount         pivot at (0,-arm.y,0)
                └── Bow             only when extras has "bow", :407-412
                    └── Mesh        BoxMesh 0.07 x 0.62 x 0.07
```

Every pivot is a bare `Node3D` created by `_add_pivot` (`:454-459`); the box always sits offset beneath or above the joint so a limb rotates about the joint rather than about its own center.

### Quadruped rig (`_build_quadruped`, `:422-451`), reached only by `enemy_type`/id resolving to `"hound"`

```
DioramaVisual
└── Root                            pivot at (0,0,0), :425
    ├── Torso                       pivot at (0, 0.3, 0), :429-430
    │   ├── Mesh                    BoxMesh 0.42 x 0.34 x 0.78
    │   ├── Head                    pivot at (0, 0.2, 0.36), :432-435
    │   │   ├── Mesh                BoxMesh 0.30 x 0.26 x 0.34 (accent material)
    │   │   ├── EarL                BoxMesh 0.08 x 0.12 x 0.08  <- mesh, not a pivot
    │   │   └── EarR                BoxMesh 0.08 x 0.12 x 0.08  <- mesh, not a pivot
    │   └── Tail                    pivot at (0, 0.24, -0.38), :437-438
    │       └── Mesh                BoxMesh 0.10 x 0.10 x 0.30
    ├── LegL                        pivot at (-0.16, 0.3, +0.26)   front left
    ├── LegR                        pivot at (+0.16, 0.3, +0.26)   front right
    ├── LegBL                       pivot at (-0.16, 0.3, -0.26)   rear left
    └── LegBR                       pivot at (+0.16, 0.3, -0.26)   rear right
```

The quadruped has **no `ArmL`, `ArmR`, `WeaponMount`, or `ShieldMount`**. `attach_weapon` therefore returns immediately for a hound (`:231-233`).

### Animatable pivots per profile

`collect_rest_pose()` (`:222-227`, `_collect_rest_pose_recursive` `:462-474`) records every `Node3D` child that is **not** a `MeshInstance3D`, keyed by node name, storing `path` (relative to `DioramaVisual`), `position`, and `rotation`. Because it `continue`s on `MeshInstance3D`, meshes and their children are never recorded, so `Mesh`, `Visor`, `Hood`, `BeltTrim`, `Pauldron`, `EarL`, and `EarR` are not animatable.

| Profile | Rest-pose keys | Count |
|---------|----------------|-------|
| `player` | `Root`, `LegL`, `LegR`, `Torso`, `Head`, `ArmL`, `ShieldMount`, `ArmR`, `WeaponMount` | 9 |
| `melee` | same as `player` | 9 |
| `brute` | same as `player` | 9 |
| `dummy` | same as `player` | 9 |
| `ranged` | same as `player` plus `Bow` | 10 |
| `shield` | same as `player` plus `Shield` | 10 |
| `hound` | `Root`, `Torso`, `Head`, `Tail`, `LegL`, `LegR`, `LegBL`, `LegBR` | 8 |

### What breaks when a name is missing

- `DioramaAnimLibrary._compile` skips any clip track whose part name is absent from the rest pose (`diorama_anim_library.gd:530-531`). No warning is logged. A hound therefore silently drops the `ArmL`/`ArmR` tracks from `idle`, `walk`, `run`, `air`, `land`, all four `dash_*`, all three `block_*`, `parry_success`, `guard_break`, `flinch`, `stagger`, and `death`; a biped silently drops `LegBL`, `LegBR`, and `Tail` from `walk` and `run`.
- If **every** track of a clip is dropped, `_compile` returns `null` (`diorama_anim_library.gd:546-547`) and the clip is simply absent from the library. `DioramaAnimController._start_action` and `_play` then return early on the `has_clip()` guard (`diorama_anim_controller.gd:309`, `:321-322`) with no log, so the request evaporates.
- `attach_weapon` returns early if `WeaponMount` is missing (`:231-233`).
- `_apply_player_appearance` returns early if `Root` is missing (`:102-104`).
- `apply_first_person` walks `FIRST_PERSON_HIDDEN_PARTS = ["Torso"]` (`:23`, `:283-286`); renaming `Torso` silently disables first-person body hiding.

## How it works

### Player

`build_player_body(facing, theme = -1)` (`:89-98`):
1. `_remove_visual(facing)` frees any existing `DioramaVisual` (`:484-488`).
2. `PixelStyle.hide_legacy_meshes(facing)` hides pre-diorama capsule meshes, skipping the `DioramaVisual`, `DioramaVisuals`, and `Viewmodel` subtrees (`pixel_diorama_style.gd:970-979`).
3. Theme defaults to `CharacterService.appearance_theme`, falling back to `PaletteTheme.HUB`.
4. `CharacterAppearance.from_service()` supplies `height`, `bulk`, `head`, `trim` (`character_appearance.gd:94-97`).
5. `_build_humanoid(visual, "player", _body_materials(theme, "player"))`.
6. `_apply_player_appearance(visual, profile, _body_materials(theme, "player"))` — note `_body_materials` is called a second time, producing a second accent duplicate.

`_apply_player_appearance` (`:101-151`):
- `Root.scale = Vector3(bulk, height, bulk)` (`:107`). `height` is clamped to 0.82-1.18 and `bulk` to 0.82-1.22 by `CharacterAppearance.sanitize` (`character_appearance.gd:63-64`).
- Head style: looks for `head.get_node_or_null("Mesh/Visor")` (`:111`) and `head.get_node_or_null("Hood")` (`:114`). `Hood` is created on demand when the style is `hood` and no hood exists (`:117-126`).
- `trim >= 1` adds a `BeltTrim` box on `Torso` (`:127-139`); `trim >= 2` adds a `Pauldron` box on each of `ArmL` and `ArmR` (`:140-151`).

### Enemies

`build_enemy_body(parent, enemy_type = "melee", theme = CASTLE)` (`:154-169`) lowercases the type; `"hound"` routes to `_build_quadruped`, anything else is looked up in `PROFILES` and falls back to `"melee"` when absent (`:167`).

`profile_for_enemy_data(data)` (`:210-217`) picks the profile string from enemy JSON:
- id contains `hound` -> `"hound"`
- id contains `brute`, `golem`, or `guardian` -> `"brute"`
- otherwise `data["enemy_type"]`, defaulting to `"melee"`

`theme_for_enemy_id(enemy_id)` (`:199-207`) splits the id on the first `_` and matches the prefix: `crystal` -> `CRYSTAL`, `swamp` -> `SWAMP`, `frost` -> `FROZEN`, `cathedral` -> `CATHEDRAL`, `training` -> `CASTLE`, anything else -> `CASTLE`.

### Training dummy

`build_training_dummy(parent)` (`:172-190`) builds the `dummy` profile with `CASTLE` theme, then replaces `mats["accent"]` with `PixelStyle.make_material(ARENA_DUMMY_ACCENT, ARENA_DUMMY_GLOW)` (`:177`). Because the emission argument is non-black, `make_material` routes to `make_glow_material` and the emissive shader (`pixel_diorama_style.gd:404-406`), not the surface shader. A `TargetStripe` box is added across the front of the torso (`:183-189`).

### Weapon attachment

`attach_weapon(visual, weapon_id, theme)` (`:230-259`):
1. Finds `WeaponMount`; returns if absent.
2. Frees every `WeaponMount` child except children named `Bow` or `Shield` (`:236-239`).
3. `WeaponKit.build(weapon_id, theme)` produces the kit; `WeaponKit.resolve_id(weapon_id)` gives the kit id.
4. Kit id `bow`: if a `Bow` pivot exists anywhere in the rig, its children are freed and the kit is parented there instead (`:245-252`).
5. Kit id `spear`: the kit is offset to `(0.04, -0.12, -0.22)` and rotated `(82 deg, 0, 2 deg)` so the shaft points forward (`:253-256`).
6. When the visual is named `ViewRoot` (the first-person viewmodel), shadow casting is disabled on the kit (`:257-258`).

### First-person visibility

`apply_first_person(facing, enabled)` (`:277-289`) resolves `facing/DioramaVisual`, sets the `Torso` subtree to `SHADOW_CASTING_SETTING_SHADOWS_ONLY` when enabled (`_set_shadows_only`, `:329-337`), and calls `_apply_first_person_weapon_shadows` to turn shadow casting off on the `WeaponMount`, `ShieldMount`, and `Bow` subtrees (`:296-302`). When leaving first person it calls `_set_meshes_visible(visual, true)` (`:289`), which sets `visible = true` on **every** `GeometryInstance3D` in the rig.

## Profile table

`PROFILES` (`:32-86`), all values in meters. `hip_x` is half the hip separation, `shoulder_x` half the shoulder separation; shoulder height is always `torso.y * 0.88`.

| Profile | leg | torso | head | arm | hip_x | shoulder_x | Extras | Box count |
|---------|-----|-------|------|-----|-------|-----------|--------|-----------|
| `player` | 0.22 x 0.46 x 0.26 | 0.50 x 0.62 x 0.34 | 0.32 | 0.20 x 0.52 x 0.20 | 0.13 | 0.30 | `visor: true` | 7 (+1 `BeltTrim` at trim>=1, +2 `Pauldron` at trim>=2, +1 `Hood` for hood style) |
| `melee` | 0.24 x 0.48 x 0.28 | 0.55 x 0.64 x 0.38 | 0.36 | 0.22 x 0.54 x 0.22 | 0.14 | 0.33 | `head_accent: true` | 7 |
| `ranged` | 0.18 x 0.44 x 0.24 | 0.42 x 0.56 x 0.30 | 0.28 | 0.16 x 0.48 x 0.16 | 0.11 | 0.25 | `extras: ["bow"]` | 8 |
| `shield` | 0.24 x 0.46 x 0.30 | 0.64 x 0.68 x 0.44 | 0.34 | 0.22 x 0.52 x 0.22 | 0.15 | 0.36 | `extras: ["shield"]` | 8 |
| `brute` | 0.28 x 0.50 x 0.32 | 0.78 x 0.82 x 0.50 | 0.42 | 0.30 x 0.66 x 0.30 | 0.18 | 0.46 | `head_accent: true` | 7 |
| `dummy` | 0.24 x 0.46 x 0.30 | 0.55 x 0.66 x 0.38 | 0.38 | 0.24 x 0.54 x 0.24 | 0.15 | 0.32 | none | 7 (+1 `TargetStripe`) |
| `hound` | not in `PROFILES`; hardcoded in `_build_quadruped` | 0.42 x 0.34 x 0.78 | 0.30 x 0.26 x 0.34 | none | 0.16 | none | ears, tail, 4 legs | 9 |

The `head_accent` flag swaps the head material from `body` to `accent` (`:388`). `visor` adds the `Visor` box (`:390-397`).

## Profile coverage of shipped content

Every one of the 30 files in `content/enemies/` and 11 in `content/bosses/` maps onto the seven rigs above.

| Resolved profile | Enemy/boss ids |
|------------------|----------------|
| `hound` (quadruped) | `castle_hound`, `frost_hound` |
| `brute` | `crystal_guardian`, `miniboss_crystal_guardian`, `crystal_golem` |
| `ranged` | `castle_archer`, `crystal_bat`, `crystal_shade`, `crystal_spitter`, `crystal_wisp`, `cathedral_acolyte`, `frost_archer`, `swamp_spitter`, `swamp_witch` |
| `shield` | `castle_shield` |
| `melee` | `castle_grunt`, `cathedral_shade`, `cathedral_warden`, `crystal_crawler`, `crystal_slime`, `frost_knight`, `frost_raider`, `swamp_bogling`, `swamp_brute`, `swamp_leech`, `swamp_slasher`, `swamp_swarm`, `swamp_toad` |
| `"boss"` -> falls back to `melee` geometry at `:167` | `boss_castle_knight`, `boss_cathedral_hollow`, `boss_crystal_sovereign`, `boss_frost_warlord`, `boss_swamp_devourer`, `crystal_sovereign`, `final_boss_forgotten_castle`, `miniboss_castle_captain`, `miniboss_cathedral_bell`, `swamp_hag`, `swamp_hydra` |

`crystal_bat`, `crystal_wisp`, `crystal_slime`, `swamp_leech`, `swamp_swarm`, and `swamp_toad` are all rendered as upright box humanoids. `crystal_bat` and `crystal_wisp` additionally carry the `ranged` profile's `Bow` pivot and are given the `bow` kit by `castle_enemy_base._default_weapon_for_profile()` (`castle_enemy_base.gd:124-132`).

## Contracts

- **Node names** — `DioramaVisual`, `Root`, `Torso`, `Head`, `ArmL`, `ArmR`, `LegL`, `LegR`, `LegBL`, `LegBR`, `Tail`, `WeaponMount`, `ShieldMount`, `Bow`, `Shield`. Consumed by `DioramaAnimLibrary.CLIPS`/`ATTACKS` track keys, `DioramaAnimController.get_weapon_mount()` (`diorama_anim_controller.gd:390-393`), `DioramaViewmodel` (which deliberately reuses `ArmL`, `ArmR`, `WeaponMount`, `ShieldMount`, `diorama_viewmodel.gd:44`, `:67`), and `export_diorama_anim_libraries.gd:10-71`.
- **Constants exported for other systems** — `VISUAL_NAME`, `ROOT_NAME`, `WEAPON_MOUNT`, `SHIELD_MOUNT`, `FIRST_PERSON_HIDDEN_PARTS`.
- **Autoload dependencies** — `CharacterService.appearance_theme` (`:94`), `CharacterAppearance.from_service()` (`:95`), `PixelDioramaSettings` indirectly through `PixelStyle.make_surface_material`.
- **JSON keys read** — `enemy_type` and `id` from enemy/boss definitions (`:211-212`); `height`, `bulk`, `head`, `trim` from the appearance profile (`:105-127`).
- **Save keys** — none written here; appearance is persisted by `character_appearance.gd`.
- **Collision layers** — none; this module builds visuals only. Collision stays on the host `CharacterBody3D`.
- **`feet_local_y(profile)`** returns `0.0` for every profile (`:195-196`); `character_floor_snap.gd:29-30` calls it and then sets `visual.position.y = -body.position.y - feet_y`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| All character geometry is `BoxMesh` primitives sized from a hardcoded dictionary | PLACEHOLDER | `diorama_character_skin.gd:32-86`, `365-451`, `pixel_diorama_style.gd:422-443` |
| No authored character asset of any kind in the repo | ABSENT | globbed `apps/game/client` for sprite/texture/voxel/mesh extensions; only `icon.svg` |
| Six humanoid profiles + one quadruped cover 41 enemy/boss definitions and the player | PLACEHOLDER | table above |
| 11 of 13 `enemy_type: "boss"` definitions render as the `melee` grunt silhouette | BROKEN | `:210-217`, `:167`, `content/bosses/boss_castle_knight.json:22` |
| Head style `open` vs `visor` are identical; `hood` shows hood **and** visor | BROKEN | `:111` looks up `Mesh/Visor`, but `:391-397` builds the node at `Head/Visor`, so the lookup always returns `null` |
| Leaving first person re-shows meshes that appearance hid | BROKEN | `:289` `_set_meshes_visible(visual, true)` overrides the `Visor`/`Hood` visibility set at `:113`, `:116` |
| `theme_for_enemy_id` prefix match sends every `boss_*` and `miniboss_*` id to `CASTLE` | BROKEN | `:200-207`; `boss_frost_warlord` -> prefix `boss` -> `CASTLE` |
| `feet_local_y` returns a constant `0.0` for all profiles | STUB | `:195-196` |
| `"body"` material is the shared cached wall material for the theme | IMPLEMENTED | `:359`, `pixel_diorama_style.gd:250-252` |
| `PixelDioramaSettings.apply_all()` clears the material caches, orphaning already-built bodies | PARTIAL | `pixel_diorama_settings.gd:183`, `pixel_diorama_style.gd:69-73` |
| `_body_materials` called twice per player build, duplicating the accent material twice | PARTIAL | `:96-97`, `:352-354` |
| `attach_weapon`'s `"Shield"` preservation guard is unreachable (`Shield` is a `ShieldMount` child, the loop scans `WeaponMount`) | STUB | `:236-239`, `:413-417` |
| Hound `EarL`/`EarR` are `MeshInstance3D`, so no clip can animate them | PARTIAL | `:434-435`, `:462-468` |
| Quadruped reuses the biped `LegL`/`LegR` clip tables | PLACEHOLDER | `:442-449`, `diorama_anim_library.gd:59-66`, `81-88` |
| `diorama_character_rig_player.tscn` is an editor authoring aid, not on the play path | IMPLEMENTED | `diorama_character_rig_player.gd:10-35`; no other scene references it except `pixel_pipeline_suite.gd:25` |

## Related
- Improvement plan: [`../actual_improvements/diorama-character-skin.md`](../actual_improvements/diorama-character-skin.md)
- Cross-cutting decision on replacing box rigs with authored characters: [`character-authoring.md`](character-authoring.md) and [`../actual_improvements/character-authoring.md`](../actual_improvements/character-authoring.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`pixel-style.md`](pixel-style.md), [`character-appearance.md`](character-appearance.md), [`character-floor-snap.md`](character-floor-snap.md), [`enemies.md`](enemies.md), [`bosses.md`](bosses.md)
