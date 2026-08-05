# Diorama viewmodel

Builds the first-person arms and weapon mount as a child of the player camera. It is reachable and live: `PlayerAnimDirector._build_viewmodel` constructs it unconditionally in `_ready` (`player_anim_director.gd:56`, `:62-82`), and `orbit_camera.gd:59-60` toggles visibility on the `toggle_camera` input action.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/diorama_viewmodel.gd` | 113 lines: builds the `Viewmodel/ViewRoot` hierarchy, arm boxes, mounts, materials |
| `apps/game/client/scripts/player/player_anim_director.gd` | Builds it, registers it as an animation mirror, drives sway and bob, syncs visibility |
| `apps/game/client/scripts/camera/orbit_camera.gd` | Owns the first/third-person toggle and calls back into the director |

## What it renders

`build(camera, theme)` (`:29-72`) creates:

```
Camera3D
└── Viewmodel                      (NODE_NAME, :15)
    └── ViewRoot                   (VIEW_ROOT, :16)
        ├── ArmL                   pos (-0.3, -0.26, -0.18), rot (-0.62, 0, +0.22)
        │   ├── Mesh               BoxMesh 0.16 x 0.46 x 0.16, offset (0, -0.23, 0)
        │   ├── Glove              BoxMesh 0.1792 x 0.12 x 0.1792, offset (0, -0.414, 0)
        │   └── ShieldMount        pos (0, -0.46, 0)
        └── ArmR                   pos (+0.3, -0.26, -0.18), rot (-0.62, 0, -0.22)
            ├── Mesh               BoxMesh 0.16 x 0.46 x 0.16
            ├── Glove              BoxMesh 0.1792 x 0.12 x 0.1792
            └── WeaponMount        pos (0, -0.46, 0)
```

That is the whole viewmodel: **four boxes**, two per arm. There is no hand, no forearm break, no elbow joint, no separate wrist. `SHOULDER_OFFSET = Vector3(0.3, -0.26, -0.18)` and `ARM_SIZE = Vector3(0.16, 0.46, 0.16)` (`:20-21`); the rest rotation `ARM_REST_ROTATION = Vector3(-0.62, 0, 0)` with `ARM_REST_ROLL = 0.22` applied as roll mirrored per side (`:25-26`, `:50-52`) is what brings the arms into frame, because clips are stored as offsets from rest.

`_disable_shadows(holder)` (`:71`, `:93-97`) sets `SHADOW_CASTING_SETTING_OFF` on every `GeometryInstance3D` under the holder, since the viewmodel sits inside the near plane.

`_materials(theme)` (`:100-112`) returns `"body"` = the shared cached `make_wall_material(theme)` and `"accent"` = a duplicate of the cached `PROP` surface material with `color_base` set to the palette `ACCENT` slot and `color_shadow` to `ACCENT` darkened by 0.25.

`get_root(camera)` (`:75-81`) returns `Viewmodel/ViewRoot` or `null`. `remove(camera)` (`:84-88`) frees the holder.

## How it is wired

`PlayerAnimDirector._build_viewmodel` (`player_anim_director.gd:62-82`):
1. Resolves `CameraPivot/SpringArm3D/Camera3D` (`CAMERA_PATH`, `:12`); returns if absent.
2. Hardcodes `theme = PixelStyle.PaletteTheme.HUB` (`:66`).
3. `Viewmodel.build(camera, theme)`, then `Viewmodel.get_root(camera)`.
4. Creates a second bare `DioramaAnimController` named `ViewmodelAnim` as a child of the director (`:73-75`).
5. `set_profile("player")`, `set_theme(HUB)`, and `set_weapon(get_archetype())` if a `WeaponController` exists (`:76-79`).
6. `bind(_viewmodel_root)`, then `add_mirror(_viewmodel_anim)` so every gameplay animation call reaches both rigs (`:80-81`).

`sync_camera_mode()` (`player_anim_director.gd:86-94`) reads `SpringArm3D.is_first_person()` and sets the `Viewmodel` holder's `visible` to that value; it always forces the third-person `_visual.visible = true`. `orbit_camera._update_body_visibility` (`orbit_camera.gd:258-263`) calls `DioramaCharacterSkin.apply_first_person(_facing, _first_person)` and then `sync_camera_mode()` on the director. `revive()` re-runs both (`player_anim_director.gd:308-314`).

`_update_viewmodel_sway(delta)` (`player_anim_director.gd:170-204`) runs every `_process` frame and is purely additive on top of whatever clip the mirror is playing:
- Camera yaw/pitch deltas are converted to a target sway of `clamp(-yaw_delta * 1.6, +/-0.09)` and `clamp(-pitch_delta * 1.4, +/-0.07)` (`SWAY_YAW_LIMIT`, `SWAY_PITCH_LIMIT`, `:21-22`), lerped at `SWAY_RESPONSE = 9.0` per second (`:20`).
- `ViewRoot.rotation = Vector3(sway.y, sway.x, sway.x * 0.4)`.
- Bob phase advances at `delta * horizontal_speed * 2.2` and drives `ViewRoot.position` with amplitude `BOB_HEIGHT = 0.014` m (`:23`, `:202-204`).

## Which clips actually drive it

`bind` collects the rest pose from `ViewRoot`, which yields four keys: `ArmL`, `ArmR`, `ShieldMount`, `WeaponMount`. Because there is no `Root` key, `DioramaAnimLibrary._can_use_authored_library` returns `false` (`diorama_anim_library.gd:456-457`) and the library is compiled per rig instead of loaded from `player_locomotion.res`.

`_compile` then drops every track whose part is absent (`diorama_anim_library.gd:530-531`). No clip in `CLIPS` or `ATTACKS` keys `ShieldMount` or `WeaponMount`, so **only the `ArmL` and `ArmR` tracks survive**. All 17 `CLIPS` entries and all 10 `ATTACKS` entries key at least one arm, so every clip still compiles and none returns `null`; but a whole-body lunge, a leg step, or a root drop is invisible in first person. `RESET` keys all four pivots because `_compile_reset` iterates the rest pose directly (`diorama_anim_library.gd:604`).

`_resolve_events_path` returns `""` for the viewmodel controller because `ViewRoot` is not an ancestor of `ViewmodelAnim` (`diorama_anim_controller.gd:116`), so the viewmodel has no method tracks. This matches the intent stated in the comment at `diorama_anim_controller.gd:114-115`, but it is the same condition that also strips method tracks from every third-person rig.

## Weapon in first person

`set_weapon` on the mirror routes to `DioramaCharacterSkin.attach_weapon(_visual, weapon_id, _theme)` (`diorama_anim_controller.gd:139-140`). `attach_weapon` finds `WeaponMount` under `ArmR`, and because the visual is named `ViewRoot` it calls `_disable_cast_shadows(weapon)` on the kit (`diorama_character_skin.gd:257-258`). Nothing ever attaches anything to the viewmodel's `ShieldMount`.

`player_anim_director._sync_first_person_weapon_shadows` (`:300-305`) applies to the **third-person** visual only, turning off shadow casting on its `WeaponMount`, `ShieldMount`, and `Bow` subtrees while in first person (`diorama_character_skin.gd:292-302`).

## Contracts

- **Node names** — `Viewmodel`, `ViewRoot`, `ArmL`, `ArmR`, `ShieldMount`, `WeaponMount`. `ArmL`/`ArmR` and the two mount names are deliberately identical to the third-person rig so the same clip tables drive both (`:44`, `:67`). `ViewRoot` is deliberately **not** `Root`, which is what suppresses body and root-motion tracks (`:8-10`) and what makes `_can_use_authored_library` fail.
- **Constants exported** — `NODE_NAME`, `VIEW_ROOT`, `SHOULDER_OFFSET`, `ARM_SIZE`, `ARM_REST_ROTATION`, `ARM_REST_ROLL`.
- **`ViewRoot` transform is owned by `player_anim_director`** — sway writes `rotation` and bob writes `position` every frame, so nothing else may drive those two properties.
- **`Viewmodel` is skipped by `PixelStyle.hide_legacy_meshes`** (`pixel_diorama_style.gd:972`).
- **Depends on** — `PixelDioramaStyle.add_box`, `.get_palette`, `.make_surface_material`, `.make_wall_material`; `DioramaCharacterSkin.SHIELD_MOUNT`, `.WEAPON_MOUNT`.
- **Input** — visibility is toggled by the `toggle_camera` action, persisted through `LocalSave.set_first_person_camera` (`orbit_camera.gd:59-60`, `:233-235`, `:43-44`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| First-person arms are four `BoxMesh` primitives with no hand or elbow | PLACEHOLDER | `:43-69` |
| Reachable and toggled in play | IMPLEMENTED | `player_anim_director.gd:56`, `orbit_camera.gd:59-60`, `:258-263` |
| Only `ArmL`/`ArmR` tracks survive compilation; every other clip channel is discarded | PARTIAL | rest pose is `ArmL`, `ArmR`, `ShieldMount`, `WeaponMount`; `diorama_anim_library.gd:530-531` |
| No clip keys `WeaponMount` or `ShieldMount` | ABSENT | full track listing in [`diorama-anim-library.md`](diorama-anim-library.md) |
| Theme is hardcoded to `PaletteTheme.HUB`, so the arms never match the biome or the player's chosen appearance theme | FAKE | `player_anim_director.gd:66`; the third-person body uses `CharacterService.appearance_theme` (`diorama_character_skin.gd:94`) |
| Nothing attaches to the viewmodel `ShieldMount`; there is no first-person shield | ABSENT | `diorama_character_skin.gd:230-259` targets `WeaponMount` and the `Bow` pivot only |
| The viewmodel is never rebuilt on appearance change; `refresh_appearance_visual` rebinds only the third-person visual | PARTIAL | `locomotion.gd:51-57` |
| Arm geometry ignores `bulk`/`height` from the appearance profile | PARTIAL | `:21` is a constant; `diorama_character_skin.gd:107` scales the third-person `Root` |
| No separate viewmodel FOV or render pass; the arms share the world camera and its near plane | ABSENT | `:29-40` parents the holder straight to the `Camera3D`; the only mitigation is the constant 0.18 m forward offset at `:20` |
| Shadow casting disabled on the whole viewmodel | IMPLEMENTED | `:71`, `:93-97` |
| Sway and bob are procedural, additive, and frame-rate compensated | IMPLEMENTED | `player_anim_director.gd:170-204` |
| The viewmodel is inside the player `CharacterBody3D` subtree, so `MaterialFlash.flash(body)` also duplicates and flashes its materials | PARTIAL | `material_flash.gd:19-25`, `hurtbox.gd:136`; `Camera3D` is a descendant of the player body |
| No first-person specific clips (aim, draw, reload, sheathe, interact) | ABSENT | `DioramaAnimLibrary.CLIPS`/`ATTACKS` contain no such entries |

## Related
- Improvement plan: [`../actual_improvements/diorama-viewmodel.md`](../actual_improvements/diorama-viewmodel.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`orbit-camera.md`](orbit-camera.md), [`player-anim-director.md`](player-anim-director.md), [`pixel-style.md`](pixel-style.md)
- Cross-cutting decision on authored character and arm assets: [`character-authoring.md`](character-authoring.md)
