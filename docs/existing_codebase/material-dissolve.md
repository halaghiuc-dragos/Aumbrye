# Material dissolve

Death dissolve for character bodies, driven by the `dissolve_clip` uniform on `pixel_diorama_surface.gdshader`. It is on the live play path for both teams: `player_combat_reactions.gd:118` dissolves the player body on death, `castle_enemy_base.gd:322` dissolves every enemy and boss body.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/material_dissolve.gd` | 72 lines: `dissolve`, `restore`, mesh gathering |
| `apps/game/client/assets/shared/pixel_diorama_surface.gdshader` | Declares `dissolve_clip` and performs the dither discard |
| `apps/game/client/scripts/player/player_combat_reactions.gd` | Player death and revive |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | Enemy and boss death |

## How it works

`dissolve(node, duration = DISSOLVE_DURATION)` (`:12-45`):
1. `_gather_meshes(node)` recursively collects every `MeshInstance3D` in the subtree (`:65-71`); returns if empty.
2. For each mesh: stores `mesh.material_override` under the meta key `material_dissolve_saved_override` if not already stored (`:20-21`), reads `mesh.get_active_material(0)`, skips the mesh unless that is a `ShaderMaterial`, `duplicate()`s it, sets `dissolve_clip = 1.0` and `flash_amount = 0.0` on the duplicate, and assigns the duplicate as the new `material_override` (`:22-29`).
3. Creates one parallel `Tween` and, per duplicate, tweens `dissolve_clip` from `1.0` to `0.0` over `duration` (`:35-45`).

`DISSOLVE_DURATION = 0.65`, annotated as matching `VfxService.DEATH_BURST_LIFETIME` (`:8`). `DISSOLVE_PARAM = &"dissolve_clip"`, `FLASH_PARAM = &"flash_amount"` (`:6-7`).

`restore(node)` (`:48-52`) calls `_restore_mesh` per mesh (`:55-62`): if the saved-override meta exists, it is put back and the meta removed; otherwise, if the current `material_override` is a `ShaderMaterial`, `dissolve_clip` is set to `1.0` and `flash_amount` to `0.0` **on that material directly**.

## The shader side

`pixel_diorama_surface.gdshader:23` declares `uniform float dissolve_clip : hint_range(0.0, 1.0) = 1.0`. The discard is at `:118-123`:

```
if (dissolve_clip < 0.999) {
    float dither = cell_hash(floor(v_world_pos.xz * pixel_scale * 0.5));
    if (dither > dissolve_clip) { discard; }
}
```

The hash is keyed on **world XZ only**, with no Y term. Every fragment in a vertical column shares one hash value, so the dissolve removes vertical columns of the body rather than scattered cells, and two bodies standing at the same XZ dissolve with an identical pattern. Because the coordinate is world space rather than object space, the pattern also stays fixed to the floor while the death clip moves the body through it.

`pixel_diorama_emissive.gdshader` declares no `dissolve_clip` uniform (uniform list at `:9-16`: `color_core`, `color_edge`, `pixel_scale`, `color_levels`, `emission_energy`, `grain_strength`, `pulse_speed`, `pulse_amount`). Setting the parameter on an emissive material is a silent no-op, so any body part built with an emissive material never dissolves. The training dummy's accent material is exactly that case: `diorama_character_skin.gd:177` calls `PixelStyle.make_material(ARENA_DUMMY_ACCENT, ARENA_DUMMY_GLOW)`, and a non-black emission argument routes `make_material` to `make_glow_material` and the emissive shader (`pixel_diorama_style.gd:404-406`).

## Call sites

### Player

`player_combat_reactions._on_died` (`:111-122`) breaks lock-on, sets `is_dead`, emits `player_died`, plays the death VFX, then resolves `Facing/DioramaVisual` and calls `MaterialDissolveScript.dissolve(visual)`. If the diorama visual is missing it falls back to scaling the legacy `Facing/MeshInstance3D` down over 0.35 s (`:119-121`).

`player_combat_reactions.reset_combat_state` (`:70-83`) sets `visual.visible = true`, then `MaterialDissolveScript.restore(visual)` followed by `MaterialFlashScript.restore_all(visual)` (`:79-80`), then `AnimDirector.revive()`.

### Enemies and bosses

`castle_enemy_base._play_death_visual` (`:317-333`) plays the death VFX, picks `_diorama_visual` (falling back to the legacy `_mesh`), calls `MaterialDissolveScript.dissolve(visual)`, and — when the animator is bound — starts a tween that waits 0.45 s and then lowers `visual.position:y` by 1.2 m (`:325-328`).

`castle_enemy_base.respawn_at_rest` (`:226-253`), invoked from `run_flow.gd:460-461` on a rest, restores health, poise, hitbox, telegraph, hurtbox, and health bar, and calls `_animator.revive()`. It does **not** call `MaterialDissolveScript.restore`, and it does not reset `_diorama_visual.position.y`. `_animator.revive()` -> `_apply_rest_pose()` (`diorama_anim_controller.gd:396-404`) iterates only the collected rest-pose keys (`Root`, `Torso`, and so on), never the `DioramaVisual` node itself, so the 1.2 m sink persists as well.

`training_grunt` never calls dissolve at all; its death is the `death` clip only (`training_grunt.gd:222-231`).

## Contracts

- **Meta key written on meshes** — `material_dissolve_saved_override`, holding the pre-dissolve `material_override` (which may be `null`).
- **Shader uniforms required** — `dissolve_clip` and `flash_amount` on the material of every mesh that should dissolve.
- **Interaction with `MaterialFlash`** — both scripts swap `material_override` and both key their saved override on a different meta name (`material_flash_saved_override`, `material_flash.gd:8`). `dissolve()` reads `get_active_material(0)`, which returns the flash duplicate if a flash is mid-flight, so the value it saves as "original" can itself be a flash duplicate.
- **Requires the node to be in the tree** — `node.get_tree()` must be non-null for the tween to be created (`:32-34`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Player death dissolve | IMPLEMENTED | `player_combat_reactions.gd:116-118` |
| Enemy and boss death dissolve | IMPLEMENTED | `castle_enemy_base.gd:317-322` |
| Enemies are never restored after a rest respawn: no `restore()` call and the 1.2 m sink is not undone, so a respawned enemy is invisible and below the floor | BROKEN | `castle_enemy_base.gd:226-253` vs `:322`, `:325-328`; `run_flow.gd:460-461`; `diorama_anim_controller.gd:396-404` |
| Dissolve dither is keyed on world XZ with no Y term, so it reads as vertical slicing rather than crumbling and is identical for co-located bodies | PARTIAL | `pixel_diorama_surface.gdshader:119` |
| Emissive-shader parts never dissolve (no `dissolve_clip` uniform) | PARTIAL | `pixel_diorama_emissive.gdshader:9-16`; `diorama_character_skin.gd:177` |
| `restore()` writes `dissolve_clip`/`flash_amount` onto the material currently in `material_override` when no saved meta exists — for a freshly built body that is the shared cached wall material | PARTIAL | `material_dissolve.gd:59-62`; `pixel_diorama_style.gd:250-252`, `:291-292`; `diorama_character_skin.gd:359` |
| A flash in flight when death lands is captured as the "saved" original | PARTIAL | `:22-28` reads `get_active_material(0)`; `material_flash.gd:42-43` |
| Fixed 0.65 s linear fade, no directional sweep, no per-part stagger, no ash or particle handoff | PLACEHOLDER | `:8`, `:38-45` |
| Duration parameter is exposed but every call site uses the default | PARTIAL | `:12`; `player_combat_reactions.gd:118`, `castle_enemy_base.gd:322` |
| `dissolve()` returns without a tween when the node is outside the tree, leaving duplicated materials in place | PARTIAL | `:32-34` |
| `training_grunt` never dissolves | ABSENT | `training_grunt.gd:222-231` |
| Registered in the pipeline existence check | IMPLEMENTED | `pixel_pipeline_suite.gd:23`, `:60-77` |

## Related
- Improvement plan: [`../actual_improvements/material-dissolve.md`](../actual_improvements/material-dissolve.md)
- [`material-flash.md`](material-flash.md), [`pixel-style.md`](pixel-style.md), [`vfx-service.md`](vfx-service.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-anim-controller.md`](diorama-anim-controller.md), [`enemies.md`](enemies.md), [`player-combat-reactions.md`](player-combat-reactions.md)
