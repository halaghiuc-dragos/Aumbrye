# Diorama viewmodel — improvement plan

## Current state

The first-person viewmodel is four `BoxMesh` primitives — an upper-arm box and a glove box per side — parented to the world `Camera3D`, with two empty mount pivots (`diorama_viewmodel.gd:43-69`). It is live: `PlayerAnimDirector._build_viewmodel` constructs it in `_ready` and registers it as an animation mirror, and `orbit_camera.gd:59-60` toggles it. Because the rig root is named `ViewRoot` rather than `Root`, and because no clip keys `WeaponMount` or `ShieldMount`, the only channels that survive compilation are `ArmL` and `ArmR`. See [`../existing_codebase/diorama-viewmodel.md`](../existing_codebase/diorama-viewmodel.md).

What the arms should ultimately be made of is [`character-authoring.md`](character-authoring.md)'s decision. This plan makes first person a first-class view: its own camera and render pass, its own clip channels, correct theming, a real off-hand, and material ownership that does not depend on the arms being accidentally inside the player body subtree.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| VMD-01 | P0 | The theme is hardcoded to `PaletteTheme.HUB`, so the first-person arms never match the player's chosen appearance theme or the current biome. The third-person body uses `CharacterService.appearance_theme`. | `player_anim_director.gd:66`, `:77`; `diorama_character_skin.gd:94` |
| VMD-02 | P0 | Only the `ArmL` and `ArmR` tracks survive compilation, so landing, dashing, staggering, guard breaks, and death read in first person only as whatever the arms happen to do. No clip keys `WeaponMount` or `ShieldMount`, so the weapon can never lead, trail, or recoil independently of the arm. | rest pose is `ArmL`, `ArmR`, `ShieldMount`, `WeaponMount`; `diorama_anim_library.gd:530-531` |
| VMD-03 | P0 | On death, `MaterialDissolve.dissolve` is applied to `Facing/DioramaVisual` only, so the first-person arms do not dissolve and stay fully opaque on screen through the death sequence. | `player_combat_reactions.gd:116-118` |
| VMD-04 | P1 | `MaterialFlash.flash(body)` walks the whole `CharacterBody3D`, and the camera is inside it, so every hit duplicates and whitens the viewmodel's four arm materials plus its weapon kit — roughly 9 extra material duplicates per hit, and a full-white flash across the screen-space arms. | `material_flash.gd:19-25`; `hurtbox.gd:136`; `player_anim_director.gd:63-72` |
| VMD-05 | P1 | The arms share the world camera and its near plane. The only mitigation is a constant 0.18 m forward offset, so any FOV change, any camera near-plane change, and any long weapon kit can clip. | `:20`, `:29-40` |
| VMD-06 | P1 | The viewmodel is never rebuilt or re-themed after construction. Changing appearance rebinds the third-person visual only, so the arms keep the theme and geometry they were built with at spawn. | `locomotion.gd:51-57`; `player_anim_director.gd:62-82` has no rebuild path |
| VMD-07 | P1 | Arm geometry is a single 0.16 x 0.46 x 0.16 box per side with no forearm, elbow, wrist, or hand, so there is no pose to read in a swing beyond a rigid rotation about the shoulder. Appearance `bulk` and `height` are ignored. | `:21`, `:55-64`; `diorama_character_skin.gd:107` |
| VMD-08 | P1 | Nothing ever attaches to the viewmodel's `ShieldMount`, so blocking in first person shows a bare arm while the third-person body shows a shield. | `diorama_character_skin.gd:230-259` targets `WeaponMount` and the `Bow` pivot only |
| VMD-09 | P1 | Sway and bob overwrite `ViewRoot.rotation` and `ViewRoot.position` wholesale every `_process` frame, so no clip, landing kick, hit shake, or aim offset can ever drive the root. First person has no impact feedback of its own. | `player_anim_director.gd:193`, `:202-204` |
| VMD-10 | P1 | In first person only `Torso` is switched to shadows-only, so the third-person `LegL` and `LegR` continue to render. The player sees legs from a rig posed for a third-person camera while the arms come from a different rig. | `diorama_character_skin.gd:23`, `:277-289` |
| VMD-11 | P2 | The arms use the shared cached `make_wall_material(theme)`, which is the same instance the level walls use, so the arms are literally wall-colored and any mutation of that instance affects the level. | `:110`; `pixel_diorama_style.gd:291-292`, `:250-252` |
| VMD-12 | P2 | The viewmodel controller can never use an authored `.res` library because `_can_use_authored_library` requires a `Root` key, so it recompiles all 17 `CLIPS` entries at spawn for a rig that keeps two tracks of each. | `diorama_anim_library.gd:456-457` |
| VMD-13 | P2 | `remove(camera)` dereferences `camera` without a null check; only `build` guards it. | `:84-88` vs `:30-32` |

## Target design

### 1. A dedicated viewmodel camera and render layer

`Viewmodel.build` creates its own `Camera3D` rather than parenting geometry to the world camera:

```
CameraPivot/SpringArm3D/Camera3D          world camera, cull_mask excludes layer 12
└── ViewmodelCamera   Camera3D            fov = VIEWMODEL_FOV, near = 0.02, cull_mask = layer 12 only
    └── Viewmodel
        └── ViewRoot
```

`ViewmodelCamera` inherits the world camera's transform by parenting, keeps `environment` null so it shares the world environment, and is set to `CAMERA_PROJECTION_PERSPECTIVE` with `VIEWMODEL_FOV = 65.0` independent of the player's world FOV setting. Every `MeshInstance3D` under `Viewmodel` gets `layers = 1 << 11` (render layer 12) and the world camera's `cull_mask` clears that bit, so the arms are drawn by exactly one camera at a fixed near plane. Closes VMD-05.

Rejected alternative: a `SubViewport` composited over the frame. It gives the strongest isolation, but the game renders at a 480x270 internal resolution through the existing pixel pipeline (`pixel-diorama-pipeline`), and a second viewport would need its own copy of that pipeline to avoid the arms being sharper than the world.

### 2. Theme and appearance driven from the same source as the body

`build(camera, theme, appearance)` takes the appearance dictionary the third-person rig uses. `PlayerAnimDirector._build_viewmodel` reads `CharacterService.appearance_theme` instead of hardcoding `HUB`, exactly as `diorama_character_skin.gd:94` does, and passes `bulk` and `height`:

```gdscript
var theme: int = CharacterSkin.appearance_theme()
var appearance := CharacterSkin.current_appearance()
var holder := Viewmodel.build(camera, theme, appearance)
```

`ARM_SIZE` becomes `ARM_SIZE_BASE * bulk_scale`, `SHOULDER_OFFSET.x` scales with `bulk_scale`, and `SHOULDER_OFFSET.y` scales with `height_scale`, using the same scale derivation the body uses. Closes VMD-01 and the appearance half of VMD-07.

`PlayerAnimDirector` gains `rebuild_viewmodel()`, called from the same place `locomotion.refresh_appearance_visual` rebinds the body (`locomotion.gd:51-57`) and on biome change. It calls `remove_mirror(_viewmodel_anim)`, frees the old controller, and re-runs `_build_viewmodel`. Closes VMD-06.

### 3. Arm rig with an elbow, wrist, and hand

```
ViewRoot
├── ArmL                pos (-0.30 * bulk, -0.26 * height, -0.18), rot (-0.62, 0, +0.22)
│   ├── Mesh            0.16 x 0.26 x 0.16   upper arm
│   ├── ForearmL        pos (0, -0.26, 0), rot (-0.35, 0, 0)
│   │   ├── Mesh        0.14 x 0.24 x 0.14
│   │   └── HandL       pos (0, -0.24, 0)
│   │       ├── Mesh    0.15 x 0.12 x 0.15   glove
│   │       └── ShieldMount  pos (0, -0.06, -0.04)
└── ArmR                mirrored, with ForearmR / HandR / WeaponMount
```

Pivot names `ForearmL`, `ForearmR`, `HandL`, `HandR` are added to the third-person rig by [`diorama-character-skin.md`](diorama-character-skin.md) under the same names, so a single clip channel set drives both views, which is the existing design intent stated at `:6-10`. `ShieldMount` and `WeaponMount` move from the shoulder to the hand, which is where they belong once an elbow exists. Closes the geometry half of VMD-07.

### 4. Clip channels that reach first person

The library gains channels the viewmodel can actually use, all of which are also correct for the third-person rig:

- `WeaponMount` rotation on all attack clips: 0.06-0.10 rad of lead into the swing and an equal trail out, so the blade is not welded to the hand.
- `ForearmL`/`ForearmR` on all attack, block, parry, and flinch clips.
- `HandL`/`HandR` on `block_start`, `block_hold`, `block_hit`, `parry_success`, and `attack_shoot` (the draw).
- A first-person-only additive clip set, compiled only for the `viewmodel` anim profile: `fp_land` (0.24 s), `fp_hit` (0.18 s), `fp_dash` (0.3 s), `fp_death` (0.9 s). These key `ViewRoot` position and rotation, and are played on a second `AnimationPlayer` in `ANIMATION_MIXING_MODE_ADD` so they layer over the arm clips instead of replacing them.

`DioramaAnimLibrary` gains `"viewmodel"` as a profile whose `build_library` filters `CLIPS` to those that key at least one arm channel plus the `fp_*` set, which also removes the 27-clip recompile at spawn (VMD-12) by giving the exporter a `viewmodel_locomotion.res` to bake. Closes VMD-02 and VMD-12.

### 5. `ViewRoot` transform as an accumulator

Sway and bob stop writing `ViewRoot` directly. `PlayerAnimDirector` composes contributions:

```gdscript
var offset_pos := _bob_offset() + _kick_pos
var offset_rot := Vector3(_sway.y, _sway.x, _sway.x * 0.4) + _kick_rot
_viewmodel_root.position = _viewmodel_rest_position + offset_pos
_viewmodel_root.rotation = _viewmodel_rest_rotation + offset_rot
```

`_kick_pos` and `_kick_rot` are driven by the `fp_*` additive layer plus explicit impulses: landing adds `(0, -0.05, 0)` and `(-0.12, 0, 0)` decaying at 12/s, a received hit adds a random `+/-0.04` rad roll decaying at 16/s, and a heavy attack adds `(0, 0, 0.06)`. All decays are frame-rate compensated with the existing `clampf(delta * response, 0, 1)` pattern. Closes VMD-09.

### 6. Off-hand in first person

`attach_offhand` from [`diorama-weapon-kit.md`](diorama-weapon-kit.md) step 6 is called for the viewmodel as well as the body, mounting `buckler` or `shield` to the viewmodel's `ShieldMount`. The viewmodel's copy is built with the render layer from section 1 and shadow casting off. Closes VMD-08.

### 7. Which rig owns which pixels in first person

`FIRST_PERSON_HIDDEN_PARTS` becomes rig data rather than a constant, and covers everything the viewmodel replaces:

```gdscript
const FIRST_PERSON_HIDDEN_PARTS := ["Torso", "LegL", "LegR"]
```

with `_set_shadows_only` applied to all three, so the third-person body contributes only its shadow while first person is active and the entire visible silhouette comes from one rig. A `first_person_legs` display setting can re-enable the legs later; the default is off because the third-person legs are posed for a camera that is not there. Closes VMD-10.

### 8. Material ownership

`_materials(theme)` stops returning the shared cached wall material. Both slots are per-instance duplicates, and the holder is marked so the effect helpers can reason about it:

```gdscript
static func _materials(theme: int) -> Dictionary:
    var body := PixelStyle.make_wall_material(theme).duplicate() as ShaderMaterial
    var accent := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.PROP, theme, 0.3).duplicate() as ShaderMaterial
    ...
```

and `holder.set_meta("owned_materials", true)`, matching the rule in [`diorama-character-skin.md`](diorama-character-skin.md) section 5: cached materials are read-only; anything mutated at runtime is per-instance. Closes VMD-11.

The effect helpers stop reaching the viewmodel by accident and reach it deliberately instead:
- `Hurtbox._emit_victim_feedback` flashes the character's `DioramaVisual` rather than the whole body, and `PlayerAnimDirector` separately flashes the viewmodel at a reduced strength (0.35) so first person registers the hit without a full-screen white frame. See [`material-flash.md`](material-flash.md).
- `player_combat_reactions._on_died` dissolves both the third-person visual and `Viewmodel/ViewRoot`, and `reset_combat_state` restores both. Closes VMD-03 and VMD-04.

### 9. Null-safety

`remove(camera)` returns early when `camera == null`, matching `build` and `get_root`. Closes VMD-13.

## Work plan

1. **Read the theme and appearance from `CharacterService` and pass them into `build`; add `rebuild_viewmodel()` and call it from the appearance-refresh path** — closes VMD-01 and VMD-06. Also add the `camera == null` guard in `remove`, closing VMD-13.
2. **Duplicate the viewmodel materials per instance and set the `owned_materials` meta** — closes VMD-11.
3. **Dissolve and restore the viewmodel alongside the body on death and revive; flash the viewmodel separately at 0.35 strength and stop flashing the whole body subtree** — closes VMD-03 and VMD-04. Coordinated with [`material-flash.md`](material-flash.md) step 1 and [`material-dissolve.md`](material-dissolve.md).
4. **Add `ViewmodelCamera` with its own FOV, near plane, and render layer; move the arm meshes onto that layer and clear the bit from the world camera's `cull_mask`** — closes VMD-05.
5. **Hide `LegL`/`LegR` as shadows-only in first person** — closes VMD-10.
6. **Split the arms into `Arm* / Forearm* / Hand*` and move the mounts to the hands, in both the viewmodel and the third-person rig** — closes the geometry half of VMD-07. Depends on the third-person pivot rename in [`diorama-character-skin.md`](diorama-character-skin.md).
7. **Scale arm geometry by appearance `bulk` and `height`** — closes the rest of VMD-07.
8. **Add `WeaponMount`, `Forearm*`, and `Hand*` channels to the clip tables; add the `viewmodel` anim profile and export `viewmodel_locomotion.res`** — closes VMD-02 and VMD-12. Depends on [`diorama-anim-library.md`](diorama-anim-library.md).
9. **Convert `ViewRoot` to an accumulator and add the additive `fp_*` layer with landing, hit, dash, and heavy-attack impulses** — closes VMD-09.
10. **Attach the off-hand kit to the viewmodel `ShieldMount`** — closes VMD-08. Depends on [`diorama-weapon-kit.md`](diorama-weapon-kit.md) step 6.

Steps 1-5 are independent and each leaves first person playable. Steps 6-8 land together for the rig contract change; step 8 degrades to the current two-channel behavior if the clip channels are not yet present.

## Data and schema changes

- New display setting `first_person_legs` (boolean, default `false`) alongside the existing pixel-diorama settings, persisted through `LocalSave` in the same block as `first_person_camera` (`orbit_camera.gd:233-235`). This adds a key to the settings dictionary, not to the character save, so no `save_migrator.gd` version bump is required.
- New `.res` file `apps/game/client/assets/animations/diorama/viewmodel_locomotion.res`, produced by the exporter's new `viewmodel` profile entry.
- No `content/` schema changes.

## Acceptance criteria

- [ ] The first-person arms use the player's appearance theme, and changing appearance in the hub updates them without a scene reload.
- [ ] The arms are drawn by `ViewmodelCamera` only, and the world camera's `cull_mask` excludes their render layer, verified by disabling `ViewmodelCamera` and observing no arms.
- [ ] A 1.9 m weapon kit at the extreme of its swing arc does not clip the near plane at any world FOV the display settings allow.
- [ ] In first person the visible silhouette contains no geometry from the third-person rig: `Torso`, `LegL`, and `LegR` are all shadows-only.
- [ ] Every attack clip rotates `WeaponMount` relative to the hand, so the blade leads into the swing and trails out of it.
- [ ] Blocking in first person shows the equipped off-hand item on the left arm.
- [ ] Landing, taking a hit, dashing, and swinging a heavy weapon each produce a visible `ViewRoot` impulse that decays, and sway and bob continue underneath them without being overwritten.
- [ ] Dying in first person dissolves the arms and the held weapon along with the body, and reviving restores both.
- [ ] Taking a hit in first person flashes the arms at a visibly lower intensity than the third-person body.
- [ ] Building the viewmodel allocates exactly two `ShaderMaterial` instances, neither of which is the instance returned by `PixelStyle.make_wall_material(theme)`.
- [ ] The viewmodel controller loads `viewmodel_locomotion.res` rather than compiling clips at spawn.
- [ ] `DioramaViewmodel.remove(null)` returns without error.

## Validation

Extend `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd` and the new `character_rig_suite.gd` from [`diorama-character-skin.md`](diorama-character-skin.md). Assertions:

- `viewmodel.pivot_contract` — build a viewmodel and assert `validate_rig(view_root, "viewmodel")` returns an empty array, against the `REQUIRED_PIVOTS["viewmodel"]` row extended to `ArmL`, `ArmR`, `ForearmL`, `ForearmR`, `HandL`, `HandR`, `ShieldMount`, `WeaponMount`.
- `viewmodel.theme_matches_body` — build both rigs from the same appearance and assert the viewmodel's `body` material `color_base` equals the third-person body's.
- `viewmodel.materials_owned` — assert neither viewmodel material is instance-identical to `PixelStyle.make_wall_material(theme)` or `make_surface_material(PROP, theme, 0.3)`.
- `viewmodel.render_layer_isolated` — assert every `MeshInstance3D` under `Viewmodel` has exactly the viewmodel layer bit set, and that the world camera's `cull_mask` has that bit clear.
- `viewmodel.no_near_plane_clip` — for each kit id, mount it, sample the attack clip at 12 points, and assert the kit's AABB stays at least 0.01 m beyond `ViewmodelCamera.near` in view space.
- `viewmodel.clip_channel_coverage` — for each clip in the `viewmodel` anim profile, assert the compiled animation has a non-zero track count and that every attack clip includes a `WeaponMount` track.
- `viewmodel.authored_library_used` — bind a viewmodel and assert the library came from `viewmodel_locomotion.res` rather than runtime compilation.
- `viewmodel.first_person_hides_body` — apply first person and assert `Torso`, `LegL`, and `LegR` are all in shadows-only mode and no other rig part is visible.
- `viewmodel.offhand_mounts` — equip `castle_buckler` and assert a kit node exists under the viewmodel's `ShieldMount`.
- `viewmodel.dissolve_covers_viewmodel` — trigger player death and assert every `MeshInstance3D` under `Viewmodel` carries the dissolve saved-override meta; after revive, assert none do.
- `viewmodel.flash_strength_split` — trigger a hit and assert the viewmodel materials' `flash_amount` peak is 0.35 while the body's is 1.0.
- `viewmodel.root_accumulator` — drive one frame of sway plus a landing impulse and assert `ViewRoot.rotation` equals the sum of both contributions rather than either alone.
- `viewmodel.remove_null_safe` — `DioramaViewmodel.remove(null)` returns without error.

Manual checklist:
- Looking straight down in first person shows nothing from the third-person rig.
- A fast mouse flick throws the arms without detaching them from the screen edge.

## Related
- Current behavior: [`../existing_codebase/diorama-viewmodel.md`](../existing_codebase/diorama-viewmodel.md)
- Authored arm and weapon asset decision: [`character-authoring.md`](character-authoring.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`material-flash.md`](material-flash.md), [`material-dissolve.md`](material-dissolve.md), [`orbit-camera.md`](orbit-camera.md), [`player-anim-director.md`](player-anim-director.md), [`pixel-style.md`](pixel-style.md), [`display_settings.md`](ui/display_settings.md)
