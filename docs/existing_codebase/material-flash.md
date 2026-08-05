# Material flash

Brief white hit flash on character bodies, driven by the `flash_amount` uniform on `pixel_diorama_surface.gdshader`. It is on the live play path for every damaged character: `Hurtbox._emit_victim_feedback` calls it on every hit that lands with non-zero damage (`hurtbox.gd:136`).

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/material_flash.gd` | 84 lines: `flash`, `restore_all`, per-mesh tween bookkeeping |
| `apps/game/client/assets/shared/pixel_diorama_surface.gdshader` | Declares `flash_amount` and mixes it into `ALBEDO` |
| `apps/game/client/scripts/combat/hurtbox.gd` | Sole trigger |
| `apps/game/client/scripts/player/player_combat_reactions.gd` | Calls `restore_all` on player revive |

## How it works

`flash(node, strength = 1.0)` (`:12-16`) gathers every `MeshInstance3D` in the subtree (`_gather_meshes`, `:19-25`) and calls `_flash_mesh` on each.

`_flash_mesh(mesh, strength)` (`:28-67`):
1. If the mesh already carries the `material_flash_tween` meta and that tween is valid, kill it; otherwise store the current `material_override` under `material_flash_saved_override` (`:29-34`). The saved override is written only on the first flash of a burst, so a re-flash mid-fade does not overwrite the original with a duplicate.
2. Read `mesh.get_active_material(0)`; return if it is not a `ShaderMaterial` or has no `shader` (`:36-41`).
3. `duplicate()` it, assign the duplicate as `material_override`, and set `flash_amount = clamp(strength, 0, 1)` on the duplicate (`:42-44`).
4. Return if `mesh.get_tree()` is null (`:45-47`).
5. Create a `Tween`, record it under `material_flash_tween`, tween `flash_amount` from `strength` to `0.0` over `FLASH_DURATION` (`:48-57`), then in a callback restore the saved override and clear both metas (`:58-67`).

`FLASH_DURATION = 0.25` s, `FLASH_PARAM = &"flash_amount"` (`:6-7`). `META_SAVED_OVERRIDE = &"material_flash_saved_override"`, `META_ACTIVE_TWEEN = &"material_flash_tween"` (`:8-9`).

`restore_all(node)` (`:70-83`) kills any active tween, removes both metas, restores the saved override if present, and otherwise sets `flash_amount = 0.0` on whatever `ShaderMaterial` is currently in `material_override`.

## Does the flash leak color across shared materials?

**No.** `PixelStyle.add_box` assigns the material to `material_override` (`pixel_diorama_style.gd:436-437`), and for character bodies that material is the **shared cached** wall material for the theme (`diorama_character_skin.gd:359` -> `pixel_diorama_style.gd:291-292` -> `_surface_material_cache` at `:250-252`, `:283`). Every body of the same theme therefore points at one `ShaderMaterial` instance, so a script that wrote `flash_amount` onto it directly would whiten every body in the biome at once.

`_flash_mesh` does not do that. It calls `duplicate()` at `:42` and assigns the duplicate to `material_override` at `:43` **before** writing the uniform at `:44`, and the tween mutates only `dup` (`:50-57`). The cached instance is never written during a flash. `MaterialDissolve.dissolve` follows the same pattern (`material_dissolve.gd:25-28`).

Two narrower writes to the shared instance do exist, and both write only the neutral default value:

- `restore_all`, when a mesh has no `material_flash_saved_override` meta, sets `flash_amount = 0.0` on the current `material_override` (`:82-83`). On a freshly built body that is the shared cached material.
- `MaterialDissolve._restore_mesh` does the same for `dissolve_clip = 1.0` and `flash_amount = 0.0` (`material_dissolve.gd:59-62`).

Because `0.0` and `1.0` are the shader defaults (`pixel_diorama_surface.gdshader:22-23`), no visible color leak results today. The path is still a write to a process-wide shared resource from a per-instance restore routine, so it becomes a real leak the moment either helper writes a non-neutral value there.

`PixelDioramaSettings.apply_to_shader_material` never touches `flash_amount` or `dissolve_clip` (`pixel_diorama_settings.gd:401-425`), so a display-settings change cannot cancel a flash in flight; it will, however, walk into the in-flight duplicates through `_apply_materials_recursive` (`pixel_diorama_settings.gd:472-487`) and rewrite their pattern uniforms.

## The shader side

`pixel_diorama_surface.gdshader:22` declares `uniform float flash_amount : hint_range(0.0, 1.0) = 0.0`, applied at `:126` as `col = mix(col, vec3(1.0), flash_amount)` immediately before `ALBEDO = col`. The flash is therefore a pure-white albedo lerp with no tint parameter and no emission component.

`pixel_diorama_emissive.gdshader` declares no `flash_amount` uniform (`:9-16`), so emissive parts never flash. On the training dummy that is the accent material built at `diorama_character_skin.gd:177`.

## Trigger

`Hurtbox.receive_hit` (`hurtbox.gd:34-61`) resolves i-frames and parries first, then applies guard mitigation, backstab, defense, and resistances, applies damage and poise, then calls `_emit_victim_feedback(final_amount, info.direction)` (`:60`).

`_emit_victim_feedback` (`hurtbox.gd:130-142`) returns early only when `damage <= 0.0`, then calls `MaterialFlashScript.flash(body)` where `body` is the owning `CharacterBody3D`. It is always called with the default `strength = 1.0`; no call site anywhere passes a second argument.

Consequences of passing the whole `CharacterBody3D`:
- A blocked hit that still deals chip damage takes the same full-white flash as an unblocked one, because the block branch at `hurtbox.gd:50-51` only emits extra block feedback and then falls through to `:60`.
- `_gather_meshes` walks the entire body subtree. For the player that includes the third-person rig, the equipped weapon kit, the hidden legacy `Facing/MeshInstance3D`, and the first-person `Viewmodel` under `CameraPivot/SpringArm3D/Camera3D`. A default player (visor head, `trim = 1`, sword equipped) is 7 body boxes + `BeltTrim` + 5 sword boxes + 4 viewmodel boxes + 5 viewmodel weapon boxes + the legacy capsule mesh, so roughly 23 `ShaderMaterial` duplications per hit received. For enemies it additionally covers the hidden `MeshInstance3D` and `TelegraphMesh`.

`player_combat_reactions.reset_combat_state` calls `MaterialFlashScript.restore_all(visual)` on the diorama visual after `MaterialDissolve.restore` (`player_combat_reactions.gd:79-80`). No enemy path calls `restore_all`.

## Contracts

- **Meta keys written on meshes** — `material_flash_saved_override`, `material_flash_tween`.
- **Shader uniform required** — `flash_amount` on the material of every mesh that should flash.
- **Ownership rule in force today** — the flash owns `material_override` for the duration of the fade and restores the previous value in the tween callback. Anything else that writes `material_override` during a flash will be overwritten by that callback.
- **Interaction with `MaterialDissolve`** — different meta keys, same `material_override` slot; see [`material-dissolve.md`](material-dissolve.md).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Hit flash fires for both teams on every damaging hit | IMPLEMENTED | `hurtbox.gd:60`, `:130-136` |
| Per-instance material duplication, so no cross-body color leak | IMPLEMENTED | `:42-44` |
| Always called at `strength = 1.0`; a 2-damage chip flashes as hard as a lethal hit | FAKE | `:12`, `hurtbox.gd:136` (no call site passes a strength) |
| Blocked hits with chip damage flash the body as if unblocked | PARTIAL | `hurtbox.gd:50-51`, `:60` |
| `flash(body)` walks the whole `CharacterBody3D`, so about 23 materials are duplicated per player hit, including the first-person arms and hidden legacy meshes | PARTIAL | `:19-25`; `player_anim_director.gd:63-72`, `pixel_diorama_style.gd:970-979` |
| Emissive-shader parts never flash | PARTIAL | `pixel_diorama_emissive.gdshader:9-16`; `diorama_character_skin.gd:177` |
| `restore_all` writes `flash_amount` onto the shared cached material when no saved meta exists (neutral value only) | PARTIAL | `:82-83`; `pixel_diorama_style.gd:250-252` |
| `_flash_mesh` can leave a mesh stuck at full flash: the early returns at `:37`, `:41`, and `:47` happen after `material_flash_saved_override` was written at `:34` and, for the `:47` case, after `material_override` was replaced at `:43` | BROKEN | `:29-47` |
| Flash color is pure white with no damage-type or element tint | PARTIAL | `pixel_diorama_surface.gdshader:126` |
| Fixed 0.25 s fade with linear falloff and no hit-stop coordination | PARTIAL | `:7`, `:50-57` |
| No enemy call site restores flash state on respawn | ABSENT | `castle_enemy_base.gd:226-253`; only `player_combat_reactions.gd:80` calls `restore_all` |
| Registered in the pipeline existence check | IMPLEMENTED | `pixel_pipeline_suite.gd:22`, `:60-77` |

## Related
- Improvement plan: [`../actual_improvements/material-flash.md`](../actual_improvements/material-flash.md)
- [`material-dissolve.md`](material-dissolve.md), [`pixel-style.md`](pixel-style.md), [`hit-feedback.md`](hit-feedback.md), [`vfx-service.md`](vfx-service.md)
- [`hit-hurtboxes.md`](hit-hurtboxes.md), [`combat-core.md`](combat-core.md), [`diorama-character-skin.md`](diorama-character-skin.md)
