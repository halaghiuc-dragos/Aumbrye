# Diorama viewmodel — improvement plan

## Status: FINISHED

## Current state

First-person arms are four `BoxMesh` primitives per side, mirrored to the third-person `DioramaAnimController`, and composited through a dedicated `SubViewport` pass (`diorama_viewmodel.gd:25-66`, `diorama_viewmodel_pass.gd:13-41`). Theme follows `CharacterService.appearance_theme` at spawn and retints on biome change via `set_viewmodel_theme` (`player_anim_director.gd:119-121`, `:187-201`; `castle_run.gd:69-77`). Visibility toggles through `set_pass_visible` (`player_anim_director.gd:209-221`). Because the rig root is `ViewRoot` rather than `Root`, and no clip keys `WeaponMount` or `ShieldMount`, only `ArmL` and `ArmR` tracks survive compilation (`diorama_anim_library.gd:530-531`, `:1969-1973`). See [`../existing_codebase/diorama-viewmodel.md`](../existing_codebase/diorama-viewmodel.md).

What the arms should ultimately be made of is [`character-authoring.md`](character-authoring.md)'s decision. This plan shipped the first-person infrastructure — SubViewport pass, animation mirror, theme retint, material ownership, and visibility — and defers rig geometry, clip channels, combat feedback, and body hiding to the sibling topics named in each gap.

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| VMD-01 | P0 | Theme hardcoded to `PaletteTheme.HUB` | was `player_anim_director.gd:66`; now `CharacterService.appearance_theme` at `:119-121`, `set_viewmodel_theme` at `:187-201` | FINISHED |
| VMD-02 | P0 | Only `ArmL`/`ArmR` tracks survive; no `WeaponMount`/`ShieldMount` clip keys | `diorama_anim_library.gd:530-531`; ANL-09 in [`diorama-anim-library.md`](diorama-anim-library.md) | DEFERRED |
| VMD-03 | P0 | Death dissolve skips viewmodel arms | `player_combat_reactions.gd:237-239`; DIS-09 in [`material-dissolve.md`](material-dissolve.md) | DEFERRED |
| VMD-04 | P1 | Hit flash does not reach viewmodel at reduced strength | `hurtbox.gd:250-252`; FLS-04 in [`material-flash.md`](material-flash.md) | DEFERRED |
| VMD-05 | P1 | Arms shared world camera near plane | `diorama_viewmodel_pass.gd:35-40` SubViewport with `near = 0.01`, `fov = 60.0` | FINISHED |
| VMD-06 | P1 | Viewmodel never rebuilt after appearance change | `locomotion.gd:96-103` rebinds body only; `retint` at `diorama_viewmodel.gd:79-95` handles theme | DEFERRED |
| VMD-07 | P1 | Single box per arm; `bulk`/`height` ignored | `diorama_viewmodel.gd:20-21`; SKN-01 in [`diorama-character-skin.md`](diorama-character-skin.md) | DEFERRED |
| VMD-08 | P1 | Nothing attaches to viewmodel `ShieldMount` | `diorama_character_skin.gd:479-482`; [`diorama-weapon-kit.md`](diorama-weapon-kit.md) | DEFERRED |
| VMD-09 | P1 | Sway/bob overwrite `ViewRoot`; no additive `fp_*` impulses | `player_anim_director.gd:622`, `:640` | DEFERRED |
| VMD-10 | P1 | Only `Torso` hidden in first person; legs still render | `diorama_character_skin.gd:38`, `:508-511` | DEFERRED |
| VMD-11 | P2 | Body slot used shared cached wall material | was `diorama_viewmodel.gd:123`; now `.duplicate()` | FINISHED |
| VMD-12 | P2 | No authored `viewmodel` profile; compiles all clips at spawn | `diorama_anim_library.gd:1969-1973` | DEFERRED |
| VMD-13 | P2 | `remove(camera)` lacked null guard | `diorama_viewmodel.gd:98-100` | FINISHED |

## Target design

### 1. Dedicated viewmodel render pass (shipped)

`DioramaViewmodel.build` attaches a `ViewmodelPass` script to a holder on the gameplay `Camera3D`. `setup_pass` creates `ViewmodelCanvas` / `ViewmodelViewport` / `ViewmodelCamera` on the root viewport (`diorama_viewmodel_pass.gd:13-41`). The chosen implementation is a `SubViewport` composite rather than a render-layer bitmask because the world already renders through the pixel pipeline at 480×270 (`pixel-diorama-pipeline.md`); a second viewport keeps the arms at the same internal resolution without duplicating the world pipeline. Closes VMD-05.

Rejected alternative: parenting geometry directly to the world `Camera3D` with a forward offset only. Any FOV or near-plane change on the gameplay camera clips long weapon kits.

### 2. Theme from the same source as the body (shipped)

`_viewmodel_theme` seeds from `CharacterService.appearance_theme` (`player_anim_director.gd:119-121`). `set_viewmodel_theme` updates the mirror controller and calls `DioramaViewmodel.retint` (`:187-201`). `castle_run.gd:69-77` and `hub.gd:185-194` push biome theme on run entry. Closes VMD-01.

### 3. Material ownership (shipped)

`_materials` duplicates both the wall and accent slots (`diorama_viewmodel.gd:112-125`). Closes VMD-11.

### 4. Null-safe teardown (shipped)

`remove(null)` returns early (`diorama_viewmodel.gd:98-100`). Closes VMD-13.

### 5. Visibility toggle (shipped)

`sync_camera_mode` resolves the `Viewmodel` holder on the gameplay camera and calls `set_pass_visible(first_person)` (`player_anim_director.gd:209-221`).

### 6. Arm rig with elbow, wrist, and hand (deferred)

Split `ArmL`/`ArmR` into `Forearm*` / `Hand*` pivots with mounts on the hands, in both viewmodel and third-person rig. Depends on [`diorama-character-skin.md`](diorama-character-skin.md). Closes VMD-07.

### 7. Clip channels that reach first person (deferred)

Add `WeaponMount`, `Forearm*`, `Hand*`, and viewmodel-only additive `fp_*` clips. Add `"viewmodel"` anim profile and `viewmodel_locomotion.res`. Depends on [`diorama-anim-library.md`](diorama-anim-library.md). Closes VMD-02 and VMD-12.

### 8. Combat feedback parity (deferred)

Dissolve and flash the viewmodel deliberately at reduced strength. Depends on [`material-dissolve.md`](material-dissolve.md) DIS-09 and [`material-flash.md`](material-flash.md) FLS-04. Closes VMD-03 and VMD-04.

### 9. First-person body hiding and off-hand (deferred)

Extend `FIRST_PERSON_HIDDEN_PARTS` to `["Torso", "LegL", "LegR"]` and attach off-hand kit to viewmodel `ShieldMount`. Depends on [`diorama-character-skin.md`](diorama-character-skin.md) and [`diorama-weapon-kit.md`](diorama-weapon-kit.md). Closes VMD-08 and VMD-10.

### 10. `ViewRoot` as transform accumulator (deferred)

Layer sway/bob with decaying landing, hit, dash, and heavy-attack impulses via a second additive `AnimationPlayer`. Closes VMD-09.

### 11. Appearance rebuild (deferred)

`rebuild_viewmodel()` frees the mirror, rebuilds geometry from `bulk`/`height`, and rebinds. Call from `locomotion.refresh_appearance_visual`. Closes VMD-06.

## Work plan

1. **Theme from `CharacterService` and `set_viewmodel_theme` for biome retint** — FINISHED (VMD-01).
2. **Duplicate viewmodel materials per instance** — FINISHED (VMD-11).
3. **SubViewport pass with dedicated camera** — FINISHED (VMD-05).
4. **`set_pass_visible` wired from `sync_camera_mode`** — FINISHED (visibility fix).
5. **`remove(null)` guard** — FINISHED (VMD-13).
6. **Forearm/hand rig and appearance scaling** — deferred to [`diorama-character-skin.md`](diorama-character-skin.md) (VMD-07).
7. **`WeaponMount`/`ShieldMount` clip channels and `viewmodel` profile** — deferred to [`diorama-anim-library.md`](diorama-anim-library.md) (VMD-02, VMD-12).
8. **Dissolve and split flash** — deferred to [`material-dissolve.md`](material-dissolve.md) / [`material-flash.md`](material-flash.md) (VMD-03, VMD-04).
9. **Hide legs and attach off-hand** — deferred to [`diorama-character-skin.md`](diorama-character-skin.md) / [`diorama-weapon-kit.md`](diorama-weapon-kit.md) (VMD-08, VMD-10).
10. **`ViewRoot` accumulator and `fp_*` additive layer** — follow-up (VMD-09).
11. **`rebuild_viewmodel` on appearance change** — follow-up (VMD-06).

## Data and schema changes

Shipped work required no schema or save-format changes.

Deferred items:

- Display setting `first_person_legs` (boolean, default `false`) alongside `first_person_camera` in `orbit_camera.gd` / `LocalSave` — no `save_migrator.gd` bump (settings dictionary only).
- Authored `apps/game/client/assets/animations/diorama/viewmodel_locomotion.res` from a `viewmodel` exporter profile.

## Acceptance criteria

- [x] First-person arms use `CharacterService.appearance_theme` at spawn, and biome entry retints via `set_viewmodel_theme` without a scene reload. (VMD-01)
- [x] Arms render through `ViewmodelViewport` with `ViewmodelCamera.near = 0.01` and `fov = 60.0`, isolated from the gameplay camera near plane. (VMD-05)
- [x] Toggling out of first person hides `ViewmodelCanvas` via `set_pass_visible(false)`. (visibility)
- [x] Building the viewmodel allocates a duplicated `ShaderMaterial` for the body slot, not the cached `make_wall_material` instance. (VMD-11)
- [x] `DioramaViewmodel.remove(null)` returns without error. (VMD-13)
- [ ] Every attack clip rotates `WeaponMount` relative to the hand. (VMD-02, deferred)
- [ ] Blocking in first person shows the equipped off-hand on `ShieldMount`. (VMD-08, deferred)
- [ ] In first person, `Torso`, `LegL`, and `LegR` are shadows-only. (VMD-10, deferred)
- [ ] Dying in first person dissolves viewmodel arms along with the body. (VMD-03, deferred)
- [ ] Hit flash reaches the viewmodel at visibly lower strength than the body. (VMD-04, deferred)
- [ ] Changing appearance `bulk`/`height` rebuilds viewmodel geometry. (VMD-06, deferred)
- [ ] Viewmodel loads `viewmodel_locomotion.res` instead of compiling at spawn. (VMD-12, deferred)

## Validation

Run `diorama_anim_suite` (rig contracts, authored libraries) and `pixel_pipeline_suite` (world SubViewport pass) via:

```powershell
powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd -- --suite=diorama_anim_suite
powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd -- --suite=pixel_pipeline_suite
```

Shipped assertions covered by existing suites:

- `diorama_anim.rig_contract` — manifest rigs satisfy `VoxelGrid.REQUIRED_PIVOTS` (`diorama_anim_suite.gd:303-345`).
- `diorama_anim.authored_libraries` — six `.res` libraries present for full-body profiles (`diorama_anim_suite.gd:28-46`).
- `pixel_pipeline.*` — autoload attach, internal resolution, camera mirror (`pixel_pipeline_suite.gd`).

Follow-up assertions to add when deferred gaps land:

- `viewmodel.pivot_contract` — `validate_rig(view_root, "viewmodel")` empty for `ArmL`, `ArmR`, `ForearmL`, `ForearmR`, `HandL`, `HandR`, `ShieldMount`, `WeaponMount`.
- `viewmodel.theme_matches_body` — same appearance → equal `color_base` on body materials.
- `viewmodel.materials_owned` — neither slot instance-identical to cached factory materials.
- `viewmodel.pass_hidden_in_third_person` — `set_pass_visible(false)` hides `ViewmodelCanvas`.
- `viewmodel.offhand_mounts` — `castle_buckler` exists under viewmodel `ShieldMount`.
- `viewmodel.remove_null_safe` — `DioramaViewmodel.remove(null)` returns without error.

Manual checklist:

- Toggle first person: arms appear; toggle third person: overlay disappears.
- Enter a frost dungeon: arm palette matches biome after `set_viewmodel_theme`.
- Fast mouse flick: arms lag slightly without detaching from screen edge.

## Related

- Current behavior: [`../existing_codebase/diorama-viewmodel.md`](../existing_codebase/diorama-viewmodel.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md)
- [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`material-flash.md`](material-flash.md), [`material-dissolve.md`](material-dissolve.md), [`orbit-camera.md`](orbit-camera.md), [`player-anim-director.md`](player-anim-director.md)
- Authored arm asset decision: [`character-authoring.md`](character-authoring.md)
