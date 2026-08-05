# Material flash — improvement plan

## Current state

`MaterialFlash.flash` duplicates each mesh's active material, mounts the duplicate as `material_override`, sets `flash_amount`, and tweens it to zero over 0.25 s; the shader mixes it to pure white at `pixel_diorama_surface.gdshader:126`. `Hurtbox._emit_victim_feedback` is the only trigger and always passes the default `strength = 1.0` on the whole `CharacterBody3D` (`hurtbox.gd:136`). The per-instance duplication is correct — there is no shared-material color leak. See [`../existing_codebase/material-flash.md`](../existing_codebase/material-flash.md).

The problems are that the flash carries no information (every hit is the same full-white frame), that it is applied to the entire body subtree including the first-person arms and hidden legacy meshes, and that three early returns can leave a mesh permanently white.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| FLS-01 | P0 | `_flash_mesh` writes the saved-override meta at `:34` and mounts the full-flash duplicate at `:43` before the guards at `:37`, `:41`, and `:45-47` can return. The `:47` path leaves the mesh mounted at `flash_amount = 1.0` with no tween to bring it down, so it stays pure white indefinitely. The `:37`/`:41` paths leave a stale saved-override meta that a later `restore_all` will reinstate. | `:29-47` |
| FLS-02 | P0 | `strength` is exposed but no call site passes it, so a 2-damage chip and a near-lethal blow produce an identical full-white flash. The flash carries no information about the hit. | `:12`; `hurtbox.gd:136` is the only call site |
| FLS-03 | P1 | A blocked hit that still deals chip damage falls through to `_emit_victim_feedback` and flashes the body exactly as an unblocked hit does, so successful blocking looks like taking a clean hit. | `hurtbox.gd:50-51`, `:60`, `:130-136` |
| FLS-04 | P1 | `flash(body)` walks the entire `CharacterBody3D`. For a default player that is roughly 23 `ShaderMaterial` duplications per hit received, including the hidden legacy `Facing/MeshInstance3D` capsule, the first-person `Viewmodel` arms and their weapon kit, and for enemies the hidden `MeshInstance3D` and `TelegraphMesh`. | `:19-25`; `player_anim_director.gd:63-72`; `pixel_diorama_style.gd:970-979`; `castle_enemy_base.gd:68` |
| FLS-05 | P1 | `pixel_diorama_emissive.gdshader` declares no `flash_amount` uniform, so emissive parts never flash. The training dummy's accent material is exactly that case: the body flashes and the glowing parts do not. | `pixel_diorama_emissive.gdshader:9-16`; `diorama_character_skin.gd:177` |
| FLS-06 | P1 | When a mesh has no saved-override meta, `restore_all` writes `flash_amount` onto whatever is currently in `material_override`, which for a freshly built body is the process-wide cached wall material. The value written is the shader default today, so nothing visibly leaks, but a per-instance restore is writing to a shared resource. | `:82-83`; `pixel_diorama_style.gd:250-252`, `:291-292`; `diorama_character_skin.gd:359` |
| FLS-07 | P1 | The flash is a pure-white albedo mix with no tint parameter and no emission term, so fire, frost, poison, and arcane hits are visually identical and a flash never reads as bright rather than washed out. | `pixel_diorama_surface.gdshader:126` |
| FLS-08 | P1 | Fixed 0.25 s linear falloff with no ramp-in and no coordination with hit-stop, so the flash peak does not coincide with the frame the hit actually registers. | `:7`, `:50-57` |
| FLS-09 | P1 | No enemy path calls `restore_all`. Only the player's revive does, so an enemy respawned at a rest while a flash duplicate is mounted keeps that duplicate. | `castle_enemy_base.gd:226-253`; `player_combat_reactions.gd:80` |
| FLS-10 | P1 | There is no way to cancel a flash, so `MaterialDissolve` cannot take ownership of `material_override` cleanly: it captures the flash duplicate as the "original" and the flash callback later overwrites the dissolve duplicate. | `:29-32` has no public equivalent; `material_dissolve.gd:20-28` |
| FLS-11 | P2 | The flash is uniform across the whole rig. The struck limb, the hit direction, and backstabs are all indistinguishable. | `:15-16` flashes every mesh identically; `hurtbox.gd:64-81` computes a backstab but does not pass it on |

## Target design

### 1. Correct ordering and a single owner of `material_override`

`_flash_mesh` validates before it mutates, and the flash owns the slot through an explicit lease:

```gdscript
static func flash_mesh(mesh: MeshInstance3D, params: Dictionary) -> void:
    var base := mesh.material_override as ShaderMaterial
    if base == null:
        base = mesh.get_active_material(0) as ShaderMaterial
    if base == null or base.shader == null:
        return                                  # nothing mutated
    if not _shader_declares(base.shader, FLASH_PARAM):
        return                                  # nothing mutated
    var tree := mesh.get_tree()
    if tree == null:
        return                                  # nothing mutated
    if mesh.has_meta(META_OWNER) and mesh.get_meta(META_OWNER) != OWNER_FLASH:
        return                                  # dissolve owns this mesh
    cancel(mesh)
    mesh.set_meta(META_SAVED_OVERRIDE, mesh.material_override)
    mesh.set_meta(META_OWNER, OWNER_FLASH)
    ...
```

`_shader_declares` walks `Shader.get_shader_uniform_list()` once per shader and caches the result, since Godot 4 offers no direct uniform-existence query. Every guard now precedes every write, so no path can leave a mesh mounted at full flash. `META_OWNER` is a shared meta key read by both `MaterialFlash` and `MaterialDissolve`, which makes the ownership rule enforceable instead of conventional. `cancel(mesh)` is public: it kills the tween, restores the saved override, and clears both metas, and it is what `MaterialDissolve` calls before taking over. Closes FLS-01 and FLS-10.

`restore_all` stops writing uniforms into materials it did not create: with no saved-override meta it restores `null` and returns. Closes FLS-06.

Rejected alternative: having `MaterialFlash` and `MaterialDissolve` write disjoint uniforms on one shared duplicate rather than each owning the slot. That removes the handoff entirely, but it requires a third party to create and own the duplicate, and the only natural owner is the rig builder, which would then allocate a duplicate for every mesh whether it is ever hit or not.

### 2. The flash carries information

`flash(node, params)` takes a dictionary instead of a bare strength:

```gdscript
{
    "strength": 0.0..1.0,       # derived from damage proportion
    "tint": Color,              # from damage type
    "duration": float,          # scaled with strength
    "blocked": bool,            # halves strength and shifts tint toward the guard color
    "crit": bool,               # backstab or parry punish: adds a 0.04 s hold at peak
}
```

`Hurtbox._emit_victim_feedback` computes them from data it already has:

```gdscript
var proportion := clampf(damage / maxf(1.0, _health.max_health * 0.25), 0.15, 1.0)
var params := {
    "strength": lerpf(0.35, 1.0, proportion),
    "duration": lerpf(0.14, 0.30, proportion),
    "tint": FLASH_TINTS.get(info.damage_type, Color.WHITE),
    "blocked": was_blocked,
    "crit": was_backstab,
}
```

`FLASH_TINTS`: `physical` white, `fire` `(1.0, 0.72, 0.42)`, `frost` `(0.72, 0.90, 1.0)`, `poison` `(0.78, 1.0, 0.62)`, `arcane` `(0.86, 0.72, 1.0)`, `holy` `(1.0, 0.96, 0.76)`. `was_blocked` is threaded from the `modified.get("blocked", false)` branch at `hurtbox.gd:50-51` into `_emit_victim_feedback`, which currently discards it, and halves the strength so a blocked chip reads as a glancing shimmer. Closes FLS-02, FLS-03, and the intensity half of FLS-08.

### 3. Shader support for tint and a real peak

Both shaders gain:

```glsl
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float flash_emission : hint_range(0.0, 4.0) = 0.0;
...
col = mix(col, flash_color, flash_amount);
EMISSION += flash_color * flash_amount * flash_emission;
```

`flash_emission` defaults to `1.6` when set by the flash, so a hit reads as bright in the banded lighting rather than as a washed-out albedo. `pixel_diorama_emissive.gdshader` gets the same three uniforms and the same mix, which closes FLS-05 and gives the training dummy's accent parts a flash. Closes FLS-07.

The tween shape becomes a 0.03 s ramp in, an optional `crit` hold, then a falloff with `Tween.EASE_OUT` and `Tween.TRANS_QUAD`, so the peak lands on the frame after the hit rather than on the hit frame's first sample:

```gdscript
tween.tween_method(setter, 0.0, strength, 0.03)
if params.get("crit", false):
    tween.tween_interval(0.04)
tween.tween_method(setter, strength, 0.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
```

Closes the timing half of FLS-08.

### 4. Flash the rig, not the body

`Hurtbox._emit_victim_feedback` targets the character's `DioramaVisual` instead of the `CharacterBody3D`, resolved through a new `get_diorama_visual()` on the victim (`castle_enemy_base.gd:140-141` already has one; the player gets the same accessor). That excludes the hidden legacy capsule, the telegraph mesh, and the first-person arms, cutting a player hit from roughly 23 duplications to roughly 13.

`PlayerAnimDirector` then flashes the viewmodel deliberately at `strength * 0.35` with the same tint, so first person registers the hit without a full-screen white frame. Closes FLS-04, and the viewmodel half of the same problem in [`diorama-viewmodel.md`](diorama-viewmodel.md).

`flash` also skips meshes whose `cast_shadow` is `SHADOW_CASTING_SETTING_SHADOWS_ONLY`, which is how first person hides the third-person torso (`diorama_character_skin.gd:283-287`), so invisible geometry is never duplicated.

### 5. Localized flash

`flash(node, params)` accepts an optional `"epicenter": Vector3` in world space and a `"falloff": float` (default 1.2 m). Each mesh's strength is scaled by `clampf(1.0 - distance / falloff, 0.35, 1.0)`, so the struck limb flashes hardest and the rest of the body reads as a softer sympathetic flash. `Hurtbox` passes the hitbox contact position it already resolves through `VfxService.resolve_combat_anchor` and the direction from `DamageInfo.direction`. Closes FLS-11.

### 6. Restore coverage

`castle_enemy_base.respawn_at_rest` calls `MaterialFlash.restore_all(_diorama_visual)` alongside the `reset_death_visual` call from [`material-dissolve.md`](material-dissolve.md) step 1, so no enemy can come back mid-flash. `training_grunt` does the same on reset. Closes FLS-09.

### 7. Material ownership rules, stated once

These are the rules this script and `MaterialDissolve` both obey, matching [`diorama-character-skin.md`](diorama-character-skin.md) section 5:

1. **Cached materials from `PixelDioramaStyle` are read-only.** Nothing outside `PixelDioramaStyle` may write a uniform on an instance returned by `make_*_material`.
2. **Character bodies own per-instance duplicates** of both their body and accent materials, marked with the `owned_materials` meta on the `DioramaVisual`.
3. **`material_override` has exactly one runtime owner at a time**, recorded in the `material_effect_owner` meta. A second effect must call the current owner's `cancel` first.
4. **Every effect that mounts a duplicate must restore the saved value**, and must validate everything it needs before it mounts anything.
5. **An effect never writes a uniform into a material it did not create.** With no saved value recorded, the correct restore is `material_override = null`.

## Work plan

1. **Reorder `_flash_mesh` so all guards precede all writes; add the public `cancel(mesh)`, the `material_effect_owner` meta, and the shadows-only skip; make `restore_all` stop writing into foreign materials** — closes FLS-01, FLS-06, FLS-10, and the duplication half of FLS-04.
2. **Retarget `Hurtbox._emit_victim_feedback` at the victim's `DioramaVisual`; add `get_diorama_visual()` to the player; flash the viewmodel separately at 0.35 strength** — closes the rest of FLS-04.
3. **Add `restore_all` to `respawn_at_rest` and to the training dummy reset** — closes FLS-09.
4. **Replace the bare `strength` argument with the `params` dictionary; thread `blocked` and the backstab flag out of `receive_hit`; derive strength, duration, and tint from the damage** — closes FLS-02 and FLS-03.
5. **Add `flash_color` and `flash_emission` to both shaders and apply them; add `flash_amount` to the emissive shader** — closes FLS-05 and FLS-07.
6. **Change the tween shape to ramp, optional crit hold, eased falloff** — closes FLS-08.
7. **Add `epicenter` and `falloff` and pass the contact position from `Hurtbox`** — closes FLS-11.

Steps 1-3 are pure correctness and leave the flash looking identical. Steps 4-7 are additive: `flash(node)` with no params keeps the current full-white 0.25 s behavior.

## Data and schema changes

No `content/` schema changes: `damage_type` already exists on `DamageInfo` and on weapon and enemy definitions, and `FLASH_TINTS` is a code-side lookup keyed on those existing values. No save-format change and no `save_migrator.gd` version bump.

## Acceptance criteria

- [ ] No mesh can be left mounted at `flash_amount > 0` with no active tween, including a mesh whose material has no `flash_amount` uniform, a mesh with a `StandardMaterial3D`, and a mesh outside the tree.
- [ ] Calling `flash` on a detached rig leaves every `material_override` instance-identical to what it was before.
- [ ] A 2-damage chip hit flashes visibly weaker and shorter than a hit for a quarter of max health.
- [ ] A blocked hit flashes at half the strength of the same hit unblocked.
- [ ] Fire, frost, poison, and arcane hits produce visibly different flash colors.
- [ ] Emissive body parts flash along with surface parts on the training dummy.
- [ ] A player hit duplicates no material belonging to the hidden legacy capsule mesh, the telegraph mesh, or any shadows-only geometry.
- [ ] The first-person arms flash at 0.35 of the third-person body's strength.
- [ ] Killing an enemy within 0.1 s of a flash and then respawning it at a rest leaves no flash duplicate mounted and no flash meta on any mesh.
- [ ] Starting a dissolve during a flash results in exactly one effect owning `material_override`, and after both complete the original material is restored.
- [ ] After 100 flash cycles, `PixelStyle.make_wall_material(theme)` has `flash_amount == 0.0` and is the same instance it was before.
- [ ] The mesh nearest the hit contact point flashes at full strength while a mesh 1.2 m away flashes at 0.35.
- [ ] The flash peak occurs 0.03 s after the hit rather than on the first sampled frame.

## Validation

Extend `apps/game/client/scripts/validation/suites/pixel_pipeline_suite.gd` (which already asserts the script exists, `:22`, `:60-77`) and add assertions to the new `death_visual_suite.gd` from [`material-dissolve.md`](material-dissolve.md), or a sibling `hit_feedback_suite.gd`, category `graphics`:

- `flash.shader_uniforms_present` — assert `pixel_diorama_surface.gdshader` and `pixel_diorama_emissive.gdshader` both declare `flash_amount`, `flash_color`, and `flash_emission`. Fails today for the emissive shader on all three.
- `flash.no_mutation_on_guard_paths` — for a mesh with a `StandardMaterial3D`, a mesh whose shader lacks `flash_amount`, and a mesh outside the tree, call `flash` and assert `material_override` and the meta set are unchanged. Fails today for the out-of-tree case.
- `flash.always_settles` — flash 50 meshes, advance past the longest duration, and assert every mesh has `flash_amount == 0.0`, no `material_flash_tween` meta, and its original `material_override` restored.
- `flash.no_cached_material_mutation` — record `flash_amount` and instance identity on the cached wall and accent materials, run 100 flash cycles, and assert both unchanged.
- `flash.strength_scales_with_damage` — assert the peak `flash_amount` for a hit worth 2 percent of max health is below 0.5 and for a hit worth 25 percent is 1.0.
- `flash.blocked_is_weaker` — assert the peak for a blocked hit is half that of the same unblocked hit.
- `flash.tint_per_damage_type` — for each key in `FLASH_TINTS`, assert the mounted duplicate's `flash_color` equals the table value.
- `flash.excludes_hidden_geometry` — flash a player in first person and assert no mesh with `SHADOW_CASTING_SETTING_SHADOWS_ONLY`, and no mesh under `Viewmodel`, received a duplicate from the body flash.
- `flash.duplication_count_bounded` — flash a default player rig and assert the number of created duplicates equals the number of visible `MeshInstance3D` nodes under `DioramaVisual`, with no extras.
- `flash.owner_handoff` — flash a mesh, start a dissolve 0.1 s later, and assert `material_effect_owner` reads the dissolve owner, exactly one tween is live, and after both complete the pre-flash material is restored.
- `flash.epicenter_falloff` — flash a rig with an epicenter at the head and assert the head's peak is 1.0 and a foot mesh 1.2 m away is 0.35.
- `flash.peak_timing` — sample `flash_amount` per frame and assert the maximum occurs between 0.02 s and 0.05 s after the call.
- `flash.enemy_respawn_restores` — flash an enemy, kill it, respawn it at a rest, and assert no flash meta remains.

Manual checklist:
- The flash reads as a hit landing rather than as the body turning white, at the 480x270 internal resolution.

## Related
- Current behavior: [`../existing_codebase/material-flash.md`](../existing_codebase/material-flash.md)
- [`material-dissolve.md`](material-dissolve.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`hit-feedback.md`](hit-feedback.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`combat-core.md`](combat-core.md), [`pixel-style.md`](pixel-style.md), [`vfx-service.md`](vfx-service.md), [`validation-suites.md`](validation-suites.md)
- Authored character and hit-feedback asset decision: [`character-authoring.md`](character-authoring.md)
