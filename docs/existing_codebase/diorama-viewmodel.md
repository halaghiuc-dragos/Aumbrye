# Diorama viewmodel

Builds the first-person arms and weapon mount, composites them through a dedicated `SubViewport` pass, and mirrors the third-person animation controller. It is live on the play path: `PlayerAnimDirector._build_viewmodel` constructs it in `_ready` (`player_anim_director.gd:131`, `:143-179`), `orbit_camera.gd:428-429` calls `sync_camera_mode()` on camera toggle, and biome/hub code retints via `set_viewmodel_theme` (`castle_run.gd:69-77`, `hub.gd:185-194`).

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/diorama_viewmodel.gd` | Builds arm geometry, applies materials, delegates compositing to `diorama_viewmodel_pass.gd` |
| `apps/game/client/scripts/art/characters/diorama_viewmodel_pass.gd` | `SubViewport` + `ViewmodelCamera` composited over the gameplay viewport |
| `apps/game/client/scripts/player/player_anim_director.gd` | Builds the viewmodel, registers it as an animation mirror, drives sway/bob, syncs visibility, retints on theme change |
| `apps/game/client/scripts/camera/orbit_camera.gd` | First/third-person toggle; calls `DioramaCharacterSkin.apply_first_person` then `AnimDirector.sync_camera_mode()` |

## Scene graph

`DioramaViewmodel.build(camera, theme)` (`diorama_viewmodel.gd:25-66`) parents a script holder to the world `Camera3D`, then `ViewmodelPass.setup_pass` moves the rig into a screen-space overlay:

```
Camera3D (gameplay)
â””â”€â”€ Viewmodel                         NODE_NAME, holder with ViewmodelPass script (:30-32, :64-65)

Viewport root (sibling of scene, not under Camera3D)
â””â”€â”€ ViewmodelCanvas                   CanvasLayer layer = 5 (:18-21)
    â””â”€â”€ ViewmodelContainer            full-rect SubViewportContainer (:22-27)
        â””â”€â”€ ViewmodelViewport         transparent_bg = true, own_world_3d = true (:28-34)
            â”œâ”€â”€ ViewmodelCamera       near = 0.01, fov = 60.0, current = true (:35-40)
            â””â”€â”€ ViewRoot                VIEW_ROOT (:16-17, :34-35)
                â”œâ”€â”€ ArmL              pos (-0.3, -0.26, -0.18), rot (-0.62, 0, +0.22) (:42-44)
                â”‚   â”œâ”€â”€ Mesh          BoxMesh 0.16 Ã— 0.46 Ã— 0.16 (:46-48)
                â”‚   â”œâ”€â”€ Glove         BoxMesh 0.1792 Ã— 0.12 Ã— 0.1792 (:49-55)
                â”‚   â””â”€â”€ ShieldMount   pos (0, -0.46, 0) (:57-60)
                â””â”€â”€ ArmR              mirrored, WeaponMount on right (:39-60)
```

`ViewmodelCamera` copies the gameplay camera basis each `_process` frame with position zeroed (`diorama_viewmodel_pass.gd:53-57`), so the arms stay screen-locked while inheriting look direction. The gameplay camera keeps its own FOV and near plane (`orbit_camera.gd:443-445`); the viewmodel pass uses fixed `fov = 60.0` and `near = 0.01` (`diorama_viewmodel_pass.gd:37-38`).

Arm rest pose uses `SHOULDER_OFFSET = Vector3(0.3, -0.26, -0.18)`, `ARM_SIZE = Vector3(0.16, 0.46, 0.16)`, `ARM_REST_ROTATION = Vector3(-0.62, 0, 0)`, `ARM_REST_ROLL = 0.22` (`diorama_viewmodel.gd:19-22`). There is no forearm, elbow, wrist, or separate hand pivot â€” four boxes total.

## How it is wired

**Construction** (`player_anim_director.gd:143-179`):

1. Resolves `CameraPivot/SpringArm3D/Camera3D` (`CAMERA_PATH`); returns if absent.
2. Seeds `_viewmodel_theme` from `CharacterService.appearance_theme` in `_ready` (`:119-121`).
3. `DioramaViewmodel.build(camera, _viewmodel_theme)` then `get_root(camera)` for `ViewRoot`.
4. Spawns a child `DioramaAnimController` named `ViewmodelAnim`, `set_profile("player")`, `set_theme(_viewmodel_theme)`, `set_weapon` from `WeaponController.get_archetype` when present.
5. `bind(_viewmodel_root)` and `add_mirror(_viewmodel_anim)` so every gameplay animation call reaches both rigs.

**Theme changes** (`player_anim_director.gd:187-201`):

- `set_viewmodel_theme(theme)` updates `_viewmodel_theme`, the third-person `set_theme`, the mirror controller, and `DioramaViewmodel.retint(camera, theme)`.
- `retint` walks `ViewRoot` and swaps `Mesh`/`Glove` material overrides (`diorama_viewmodel.gd:79-95`).
- `castle_run.gd:69-77` and `hub.gd:185-194` call `set_viewmodel_theme` on biome load and hub entry. Appearance bulk/height changes rebind only the third-person body (`locomotion.gd:96-103`); the viewmodel geometry is not rebuilt.

**Visibility** (`player_anim_director.gd:209-225`):

- `sync_camera_mode()` reads `SpringArm3D.is_first_person()` and calls `set_pass_visible` on the `Viewmodel` holder attached to the gameplay camera (`player_anim_director.gd:209-221`, `diorama_viewmodel_pass.gd:44-46`).

**Sway and bob** (`player_anim_director.gd:580-640`):

- Camera yaw/pitch deltas target sway clamped to `SWAY_YAW_LIMIT = 0.09` and `SWAY_PITCH_LIMIT = 0.07`, lerped at `SWAY_RESPONSE = 9.0`.
- `ViewRoot.rotation = Vector3(sway.y, sway.x, sway.x * 0.4)` and bob on `ViewRoot.position` with `BOB_HEIGHT = 0.014` m overwrite the transform every frame; no additive impulse layer exists.

## Which clips drive it

`bind` collects rest pose keys `ArmL`, `ArmR`, `ShieldMount`, `WeaponMount`. Because there is no `Root` key, `_can_use_authored_library` returns `false` (`diorama_anim_library.gd:1969-1973`) and clips compile per rig instead of loading `player_locomotion.res`.

`_compile` drops tracks whose part is absent from the rest pose (`diorama_anim_library.gd:530-531`). No clip in `CLIPS` or `ATTACKS` keys `ShieldMount` or `WeaponMount`, so only `ArmL` and `ArmR` tracks survive. Whole-body motion (root drop, leg step, torso lean) is invisible in first person.

The viewmodel controller resolves `events_path = ""` because `ViewRoot` is not an ancestor of `ViewmodelAnim` (`diorama_anim_controller.gd:116-126`), so it receives no method tracks.

## Weapon in first person

`DioramaAnimController.set_weapon` propagates to mirrors (`diorama_anim_controller.gd:191-198`). Each mirror binds its own `ViewRoot` and calls `DioramaCharacterSkin.attach_weapon` on that visual, mounting the kit under `WeaponMount` (`diorama_character_skin.gd:479-482`). Nothing attaches to the viewmodel `ShieldMount`; blocking in first person shows a bare left arm.

`DioramaCharacterSkin.apply_first_person` hides only `Torso` as shadows-only (`FIRST_PERSON_HIDDEN_PARTS := ["Torso"]` at `diorama_character_skin.gd:38`, `:502-511`). `LegL` and `LegR` continue to render in first person.

## Materials and effects

`_materials(theme)` (`diorama_viewmodel.gd:112-125`) returns `"body"` = a duplicate of `PixelStyle.make_wall_material(theme)` and `"accent"` = a duplicate of the cached `PROP` surface material with palette `ACCENT` tints.

`Hurtbox._emit_victim_feedback` flashes `Facing/DioramaVisual` only (`hurtbox.gd:250-252`). The viewmodel lives in a separate `SubViewport` and is not flashed. `player_combat_reactions._run_death_sequence` dissolves `Facing/DioramaVisual` only (`player_combat_reactions.gd:237-239`); viewmodel arms stay opaque through death in first person.

`_disable_shadows` sets `SHADOW_CASTING_SETTING_OFF` on every `GeometryInstance3D` under `ViewRoot` (`diorama_viewmodel.gd:62`, `:105-109`). `PixelStyle.hide_legacy_meshes` skips subtrees named `Viewmodel` (`pixel_diorama_style.gd:1027`).

## Contracts

- **Node names** â€” `Viewmodel`, `ViewRoot`, `ArmL`, `ArmR`, `ShieldMount`, `WeaponMount`. `ViewRoot` is deliberately not `Root`, suppressing body and root-motion tracks (`diorama_viewmodel.gd:6-10`, `diorama_anim_library.gd:1970-1972`).
- **Public API** â€” `build(camera, theme)`, `get_root(camera)`, `retint(camera, theme)`, `remove(camera)`.
- **`ViewRoot` transform** â€” owned by `PlayerAnimDirector._update_viewmodel_sway` for sway/bob; clips write shoulder pivots only.
- **Input** â€” first-person toggle is action `toggle_camera`, persisted via `LocalSave.set_first_person_camera` (`orbit_camera.gd:400-401`, `local_save.gd:58-62`).
- **Depends on** â€” `PixelDioramaStyle.add_box`, `.get_palette`, `.make_surface_material`, `.make_wall_material`; `DioramaCharacterSkin.SHIELD_MOUNT`, `.WEAPON_MOUNT`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| First-person arms are four `BoxMesh` primitives with no hand or elbow | PLACEHOLDER | `diorama_viewmodel.gd:46-55` |
| Reachable, built at spawn, mirrored to gameplay anim | IMPLEMENTED | `player_anim_director.gd:131`, `:177-179` |
| Dedicated SubViewport pass with isolated near plane | IMPLEMENTED | `diorama_viewmodel_pass.gd:28-40` |
| Theme from `CharacterService`; biome retint via `set_viewmodel_theme` | IMPLEMENTED | `player_anim_director.gd:119-121`, `:187-201`; `castle_run.gd:69-77` |
| First/third-person visibility via `set_pass_visible` | IMPLEMENTED | `player_anim_director.gd:209-221`; `diorama_viewmodel_pass.gd:44-46` |
| Per-instance body material duplicate | IMPLEMENTED | `diorama_viewmodel.gd:123` |
| `remove(null)` returns without error | IMPLEMENTED | `diorama_viewmodel.gd:98-100` |
| Only `ArmL`/`ArmR` tracks survive compilation | PARTIAL | `diorama_anim_library.gd:530-531`; no `WeaponMount`/`ShieldMount` clip keys |
| Appearance `bulk`/`height` ignored; no rebuild on appearance change | PARTIAL | `diorama_viewmodel.gd:20-21`; `locomotion.gd:96-103` rebinds body only |
| No first-person shield on `ShieldMount` | ABSENT | `diorama_character_skin.gd:479-482` targets `WeaponMount` only |
| Third-person `LegL`/`LegR` visible in first person | PARTIAL | `diorama_character_skin.gd:38`, `:508-511` hides `Torso` only |
| Death dissolve and hit flash skip the viewmodel | PARTIAL | `player_combat_reactions.gd:237-239`; `hurtbox.gd:250-252` |
| Compiles all clips at spawn (no authored viewmodel library) | PARTIAL | `diorama_anim_library.gd:1969-1973` |
| Sway and bob overwrite `ViewRoot` transform each frame | IMPLEMENTED | `player_anim_director.gd:622`, `:640` |

## Related

- Improvement plan: [`../actual_improvements/diorama-viewmodel.md`](../actual_improvements/diorama-viewmodel.md) — **FINISHED**
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) â€” world render pass; viewmodel uses a second `SubViewport` with `own_world_3d = true`
- [`orbit-camera.md`](orbit-camera.md), [`player-anim-director.md`](player-anim-director.md), [`material-flash.md`](material-flash.md), [`material-dissolve.md`](material-dissolve.md)
- Cross-cutting decision on authored character assets: [`character-authoring.md`](character-authoring.md)
