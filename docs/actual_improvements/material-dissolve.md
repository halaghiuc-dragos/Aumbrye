# Material dissolve — improvement plan

## Current state

`MaterialDissolve.dissolve` duplicates every mesh's active material, sets `dissolve_clip = 1.0` on the duplicate, and tweens it to `0.0` over 0.65 s, which drives the dither discard at `pixel_diorama_surface.gdshader:118-123`. It runs on player death (`player_combat_reactions.gd:118`) and on every enemy and boss death (`castle_enemy_base.gd:322`). See [`../existing_codebase/material-dissolve.md`](../existing_codebase/material-dissolve.md).

Two things are broken rather than merely unpolished: respawned enemies are never restored, and the dither pattern is keyed on world XZ with no Y term so the effect reads as vertical slicing pinned to the floor. This plan fixes those, gives the effect ownership rules that survive interaction with `MaterialFlash`, and turns a linear opacity fade into a directional death.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DIS-01 | P0 | `respawn_at_rest` never calls `restore()` and never undoes the 1.2 m sink, so an enemy respawned at a rest is invisible and below the floor while otherwise fully alive: hurtbox monitoring on, health restored, patrol resumed. | `castle_enemy_base.gd:226-253` vs `:322`, `:325-328`; `run_flow.gd:460-461`; `diorama_anim_controller.gd:396-404` iterates rest-pose keys only, never the `DioramaVisual` node |
| DIS-02 | P0 | The sink is applied as a relative offset (`visual.position.y - 1.2`) and the non-animator fallback writes `scale` and an absolute `position:y = -0.8`. Neither is reset, so repeated death and respawn cycles compound the offset and leave the rig permanently scaled to 20 percent. | `castle_enemy_base.gd:325-333` |
| DIS-03 | P1 | `pixel_diorama_emissive.gdshader` declares no `dissolve_clip` uniform, so emissive parts never dissolve. The training dummy's accent material is exactly that case, and every future glowing part inherits the bug: the body vanishes and the glow stays. | `pixel_diorama_emissive.gdshader:9-16`; `diorama_character_skin.gd:177`; `pixel_diorama_style.gd:404-406` |
| DIS-04 | P1 | The dither hash is keyed on `floor(v_world_pos.xz * pixel_scale * 0.5)` with no Y term, so every fragment in a vertical column shares one value. The dissolve removes vertical columns, is identical for two bodies at the same XZ, and stays pinned to the floor while the death clip moves the body through it. | `pixel_diorama_surface.gdshader:119` |
| DIS-05 | P1 | When no saved-override meta exists, `_restore_mesh` writes `dissolve_clip` and `flash_amount` onto whatever is in `material_override`, which for a freshly built body is the process-wide cached wall material. The values written are the shader defaults today, so nothing is visibly wrong, but a per-instance restore routine is writing to a shared resource. | `:59-62`; `pixel_diorama_style.gd:250-252`, `:291-292`; `diorama_character_skin.gd:359` |
| DIS-06 | P1 | `dissolve` reads `get_active_material(0)`, which returns the `MaterialFlash` duplicate when a flash is mid-fade. That duplicate is saved as the "original" under `material_dissolve_saved_override`, so a restore reinstates a flash duplicate as the permanent material and the flash's own callback then overwrites `material_override` mid-dissolve. | `:20-28`; `material_flash.gd:42-43`, `:58-67` |
| DIS-07 | P1 | If the node is outside the tree, `dissolve` returns after replacing every `material_override` with a duplicate at `dissolve_clip = 1.0` and never creates the tween. `1.0` skips the discard entirely, so the body stays fully visible forever with orphaned duplicate materials. | `:32-34` |
| DIS-08 | P1 | The effect is a uniform linear fade with no per-part stagger, no directional sweep, no relation to the killing blow, and no particle or debris handoff. A 0.65 s crossfade is the entire death of every creature in the game. | `:8`, `:36-45` |
| DIS-09 | P1 | The player's first-person arms are not dissolved. `dissolve` is called on `Facing/DioramaVisual` only, so in first person the arms stay fully opaque through the death sequence. | `player_combat_reactions.gd:116-118`; `player_anim_director.gd:63-72` |
| DIS-10 | P1 | The training dummy never dissolves; its death is the `death` clip alone, so a "killed" dummy stands there intact. | `training_grunt.gd:222-231` |
| DIS-11 | P2 | The `duration` parameter is exposed and no call site passes it, so a 3.5 m boss dissolves in exactly the same 0.65 s as a slime. | `:12`; `player_combat_reactions.gd:118`, `castle_enemy_base.gd:322` |
| DIS-12 | P2 | `PixelDioramaSettings._apply_materials_recursive` walks live materials and rewrites their pattern uniforms, including in-flight dissolve duplicates, so a display-settings change during a death repaints the dissolving body. | `pixel_diorama_settings.gd:472-487` |

## Target design

### 1. Death visual state is a single reversible operation

The scattered writes in `_play_death_visual` become one call with an explicit inverse. `MaterialDissolve` gains a companion that owns the transform as well as the materials:

```gdscript
static func play_death_visual(visual: Node3D, opts: Dictionary = {}) -> void
static func reset_death_visual(visual: Node3D) -> void
```

`play_death_visual` records `visual.position`, `visual.scale`, and each mesh's `material_override` under a single meta dictionary `death_visual_state` on the `DioramaVisual` node, then runs the dissolve and the sink. `reset_death_visual` restores everything from that dictionary and removes the meta, so the operation is idempotent and repeat cycles cannot compound. `castle_enemy_base.respawn_at_rest` calls it; so does `player_combat_reactions.reset_combat_state`. Closes DIS-01 and DIS-02.

Rejected alternative: adding a `MaterialDissolveScript.restore(visual)` call plus a `visual.position.y += 1.2` line to `respawn_at_rest`. That fixes the symptom in two lines but leaves the inverse of the death visual spread across two files with no guarantee they stay in step, and leaves the fallback scale path unfixed.

### 2. Object-space, height-driven dither

The shader change that makes the dissolve read as disintegration rather than slicing:

```glsl
uniform float dissolve_clip : hint_range(0.0, 1.0) = 1.0;
uniform vec3 dissolve_origin = vec3(0.0);   // object-space sweep origin
uniform vec3 dissolve_dir = vec3(0.0, 1.0, 0.0);
uniform float dissolve_sweep : hint_range(0.0, 1.0) = 0.6;

if (dissolve_clip < 0.999) {
    vec3 cell3 = floor(v_object_pos * pixel_scale * 0.5);
    float dither = cell_hash(cell3.xz + vec2(cell3.y * 17.0, cell3.y * 31.0));
    float sweep = clamp(dot(normalize(v_object_pos - dissolve_origin), dissolve_dir), -1.0, 1.0);
    float threshold = dissolve_clip - dissolve_sweep * (0.5 - sweep * 0.5);
    if (dither > threshold) { discard; }
}
```

Keying on object space rather than world space fixes both the pinned-to-floor artifact and the two-bodies-identical artifact; folding `cell3.y` into the hash gives per-height variation so cells fall out individually. `dissolve_sweep` biases the dissolve to start at the feet and travel up by default, or from the killing blow's direction when the caller supplies one. `v_object_pos` is a new varying; the shader already has `v_world_pos` at the same cost. Closes DIS-04.

### 3. Emissive parity

`pixel_diorama_emissive.gdshader` gains `dissolve_clip` and `flash_amount` uniforms with the same discard block and the same albedo mix, so an emissive part dissolves and flashes exactly like a surface part. A shared include is not available in Godot 4 shaders without `#include`, so the block is duplicated with a comment naming the surface shader as the source of truth, and the validation suite asserts both files declare the same uniform set. Closes DIS-03 and the emissive half of the equivalent flash gap in [`material-flash.md`](material-flash.md).

### 4. Material ownership

The rule from [`diorama-character-skin.md`](diorama-character-skin.md) section 5 applies here as the contract this script relies on: **bodies own per-instance duplicates of their materials; cached materials are read-only.** Given that:

- `dissolve` asserts the target carries the `owned_materials` meta and `push_warning`s when it does not, so a caller pointing it at shared level geometry is caught.
- `_restore_mesh` never writes uniforms into a material it did not create. If the saved-override meta is absent, it restores `null` and warns, rather than writing defaults into whatever is currently mounted. Closes DIS-05.
- `dissolve` reads the mesh's own `material_override` when present and only falls back to `get_active_material(0)` when there is none, and it refuses to save a material carrying `MaterialFlash`'s `material_flash_saved_override` sibling meta. Instead it reads the flash's saved value as the original, and calls `MaterialFlash.cancel(mesh)` so exactly one effect owns the slot. Closes DIS-06.
- `dissolve` bails **before** mutating anything when `node.get_tree() == null`, rather than after replacing every override. Closes DIS-07.
- `PixelDioramaSettings._apply_materials_recursive` skips meshes carrying `material_dissolve_saved_override`. Closes DIS-12.

### 5. A death that reads

Defaults, all data-driven per rig kind through the catalog from [`diorama-character-skin.md`](diorama-character-skin.md):

| Rig kind | `duration` | Per-part stagger | Sweep | Debris |
|----------|-----------|------------------|-------|--------|
| humanoid | 0.65 s | 0.0-0.12 s, limbs before torso, head last | feet upward | 6 chunks |
| quadruped | 0.6 s | 0.0-0.10 s, legs first | feet upward | 5 chunks |
| blob | 0.45 s | none, plus a squash to 0.6 height over the first 0.15 s | center outward | 4 chunks |
| flyer | 0.5 s | wings first | downward | 3 chunks |
| boss_humanoid | 1.4 s | 0.0-0.35 s | feet upward | 14 chunks |
| construct | 1.1 s | 0.0-0.4 s, segments bottom to top | feet upward | 10 chunks |

`dissolve(node, opts)` takes `{duration, stagger, sweep_dir, debris}`. Per-part stagger is implemented by offsetting each mesh's tween with `tween.tween_interval(stagger_for(mesh))` inside the existing parallel tween, keyed on the pivot the mesh sits under. `debris` count is forwarded to `VfxService.play_death` so a boss produces more chunks than a slime. Closes DIS-08 and DIS-11.

`sweep_dir` is supplied by the caller from the killing hit's direction, which both `Hurtbox` and `castle_enemy_base` already have in hand, so a body dissolves away from the blow.

### 6. Coverage

- `training_grunt` calls `play_death_visual` on its own visual with `duration = 0.4` and `reset_death_visual` on reset, so a downed dummy visibly goes away and comes back. Closes DIS-10.
- `player_combat_reactions._on_died` dissolves `Viewmodel/ViewRoot` alongside the third-person visual, and `reset_combat_state` restores both. Closes DIS-09. Coordinated with [`diorama-viewmodel.md`](diorama-viewmodel.md) step 3.

## Work plan

1. **Add `play_death_visual` / `reset_death_visual` with the `death_visual_state` meta; move the sink and the fallback scale into them; call `reset_death_visual` from `castle_enemy_base.respawn_at_rest` and `player_combat_reactions.reset_combat_state`** — closes DIS-01 and DIS-02. This is the fix that makes rest respawns work at all.
2. **Make `dissolve` bail before mutating when the node is out of the tree, and add the `owned_materials` warning** — closes DIS-07.
3. **Add `MaterialFlash.cancel(mesh)` and have `dissolve` call it and read the flash's saved original; make `_restore_mesh` stop writing into materials it did not create** — closes DIS-05 and DIS-06. Coordinated with [`material-flash.md`](material-flash.md) step 2.
4. **Skip dissolve-owned meshes in `PixelDioramaSettings._apply_materials_recursive`** — closes DIS-12.
5. **Dissolve the viewmodel with the body; dissolve the training dummy** — closes DIS-09 and DIS-10.
6. **Add `dissolve_clip` and `flash_amount` to `pixel_diorama_emissive.gdshader`** — closes DIS-03.
7. **Rewrite the surface shader discard to object space with a height term and a sweep, add `v_object_pos`, `dissolve_origin`, and `dissolve_sweep`** — closes DIS-04.
8. **Add `opts` to `dissolve`, per-rig-kind defaults in the rig catalog, per-part stagger, sweep direction from the killing blow, and the debris count handoff to `VfxService.play_death`** — closes DIS-08 and DIS-11.

Steps 1-6 are independent and each leaves death working. Steps 7 and 8 are visual changes with no API break; step 8 falls back to the current uniform 0.65 s fade when `opts` is empty.

## Data and schema changes

- `content/characters/rigs/<profile>.json` (introduced in [`diorama-character-skin.md`](diorama-character-skin.md)) gains an optional `death` block: `{"duration": float, "stagger": float, "sweep": "up"|"down"|"out", "debris": int}`. Update `content/schemas/character_rig.schema.json`.
- No save-format change. Death visual state is runtime-only meta and is never persisted, so no `save_migrator.gd` version bump is required.

## Acceptance criteria

- [ ] An enemy killed and then respawned at a rest is fully visible, at its spawn Y, at scale 1, with its original materials.
- [ ] Killing and respawning the same enemy five times leaves its `DioramaVisual` position and scale identical to the values it had before the first death.
- [ ] A training dummy reduced to zero health dissolves, and resetting it restores it.
- [ ] Dying in first person dissolves the arms and the held weapon at the same time as the body.
- [ ] The training dummy's emissive accent parts dissolve along with its surface parts.
- [ ] Two identical enemies standing 0.1 m apart dissolve with visibly different patterns.
- [ ] The dissolve pattern moves with the body rather than staying fixed relative to the floor while the death clip plays.
- [ ] The dissolve begins at the feet and reaches the head last for humanoid rigs.
- [ ] A boss takes visibly longer to dissolve than a grunt and emits more debris chunks.
- [ ] Calling `dissolve` on a node outside the tree leaves every `material_override` untouched.
- [ ] After any dissolve and restore cycle, `PixelStyle.make_wall_material(theme)` has `dissolve_clip == 1.0` and `flash_amount == 0.0` and is the same instance it was before.
- [ ] A hit landing within 0.1 s of a killing blow does not leave a flash duplicate mounted after the dissolve completes.
- [ ] Changing pixel-diorama display settings during a death does not alter the dissolving body's pattern.

## Validation

Extend `apps/game/client/scripts/validation/suites/pixel_pipeline_suite.gd`, which already asserts both scripts exist (`:22-23`, `:60-77`), with behavior assertions. Add a new `apps/game/client/scripts/validation/suites/death_visual_suite.gd`, category `graphics`:

- `death_visual.shader_uniforms_present` — assert both `pixel_diorama_surface.gdshader` and `pixel_diorama_emissive.gdshader` declare `dissolve_clip` and `flash_amount`. Fails today for the emissive shader.
- `death_visual.state_roundtrip` — build an enemy rig, record `position`, `scale`, and every `material_override` by instance, run `play_death_visual`, advance past the sink, run `reset_death_visual`, and assert all three match the recorded values exactly.
- `death_visual.repeat_cycles_stable` — run the roundtrip five times and assert the final state equals the initial state.
- `death_visual.respawn_restores` — call the enemy's death path, then `respawn_at_rest`, and assert the visual is visible, at `_spawn_origin` height, at scale 1, with no `material_dissolve_saved_override` meta remaining on any mesh.
- `death_visual.no_cached_material_mutation` — record `dissolve_clip` and `flash_amount` on `PixelStyle.make_wall_material(theme)`, run 20 dissolve and restore cycles, and assert both are unchanged and the instance identity is unchanged.
- `death_visual.out_of_tree_no_mutation` — build a detached rig, call `dissolve`, and assert every `material_override` is instance-identical to what it was before.
- `death_visual.flash_dissolve_handoff` — flash a mesh, then dissolve it 0.1 s later, let both complete, and assert the final `material_override` equals the pre-flash value and no flash duplicate remains.
- `death_visual.stagger_ordering` — for a humanoid rig, assert the tween start offsets are ordered legs and arms before torso before head, and that the maximum offset does not exceed the configured stagger.
- `death_visual.duration_from_catalog` — for each rig kind, assert the dissolve duration equals the catalog `death.duration` value.
- `death_visual.viewmodel_included` — trigger player death and assert every `MeshInstance3D` under `Viewmodel` carries the dissolve meta.
- `death_visual.dummy_dissolves` — reduce the training dummy to zero health and assert its meshes carry the dissolve meta.
- `death_visual.settings_skip_dissolving` — start a dissolve, call `PixelDioramaSettings.apply_all()`, and assert the in-flight duplicate's `pattern_strength` is unchanged.

Manual checklist, only where automation is genuinely impossible:
- The dissolve reads as the body coming apart into pixel cells rather than as vertical stripes or a crossfade, at the 480x270 internal resolution.

## Related
- Current behavior: [`../existing_codebase/material-dissolve.md`](../existing_codebase/material-dissolve.md)
- [`material-flash.md`](material-flash.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-anim-controller.md`](diorama-anim-controller.md)
- [`pixel-style.md`](pixel-style.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`vfx-service.md`](vfx-service.md), [`hit-feedback.md`](hit-feedback.md), [`enemies.md`](enemies.md), [`player-combat-reactions.md`](player-combat-reactions.md), [`validation-suites.md`](validation-suites.md)
- Authored character and death-asset decision: [`character-authoring.md`](character-authoring.md)
