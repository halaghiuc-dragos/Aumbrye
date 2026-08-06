# Material flash

Brief tinted hit flash on character diorama rigs, driven by `flash_amount`, `flash_color`, and `flash_emission` on `pixel_diorama_surface.gdshader` and `pixel_diorama_emissive.gdshader`. It is on the live play path for every damaged character: `Hurtbox._emit_victim_feedback` builds flash params from damage proportion, damage type, block state, and backstab, then flashes the victim's `DioramaVisual` (`hurtbox.gd:242-276`).

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/material_flash.gd` | `flash`, `cancel`, `restore_all`, per-mesh tween and ownership bookkeeping |
| `apps/game/client/assets/shared/pixel_diorama_surface.gdshader` | Surface flash uniforms and albedo/emission mix |
| `apps/game/client/assets/shared/pixel_diorama_emissive.gdshader` | Same flash uniforms on emissive parts |
| `apps/game/client/scripts/combat/hurtbox.gd` | Primary trigger: computes params and flashes victim visual |
| `apps/game/client/scripts/combat/hit_feedback.gd` | Parry, block, and attacker-hit flashes via `_flash_diorama_body` |
| `apps/game/client/scripts/player/player_combat_reactions.gd` | Stagger, parry, guard-break flashes; `restore_all` on revive |
| `apps/game/client/scripts/player/player_anim_director.gd` | `flash_viewmodel` for first-person arms at 0.35 body strength |
| `apps/game/client/scripts/player/player_heal.gd` | Heal-commit flash at strength 0.85 |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | `restore_all` on `respawn_at_rest` |
| `apps/game/client/scripts/enemies/training_grunt.gd` | `get_diorama_visual`, `restore_all` on `reset_enemy` |

## How it works

`flash(node, params)` (`material_flash.gd:34-39`) normalizes `params` (null â†’ defaults, float â†’ strength only, `Dictionary` â†’ merged defaults via `:64-83`), gathers every `MeshInstance3D` under `node` (`:86-92`), and calls `_flash_mesh` per mesh.

`_flash_mesh(mesh, params)` (`:95-171`):
1. Skips meshes with `cast_shadow == SHADOW_CASTING_SETTING_SHADOWS_ONLY` (`:96-97`).
2. Resolves a `ShaderMaterial` from `material_override` or `get_active_material(0)`; returns with no writes if missing, not a `ShaderMaterial`, shader is null, or shader lacks `flash_amount` (`:99-105`, `_shader_declares` at `:173-186`).
3. Returns with no writes if `mesh.get_tree()` is null (`:107-109`) or another effect owns `material_effect_owner` (`:111-112`).
4. Calls `cancel(mesh)` (`:114`), then scales strength for `blocked` (Ã—0.5, `:117-118`) and optional `epicenter`/`falloff` distance falloff (`:119-123`, min local strength `0.35`, falloff default `1.2` m).
5. Stores `material_flash_saved_override` and sets `material_effect_owner` to `flash` (`:131-132`), duplicates the base material, sets `flash_color` and `flash_emission` (`1.6` default, `:137-140`), tweens `flash_amount` from `0` â†’ strength over `0.03` s (`RAMP_IN`, `:145-151`), optional `crit` hold `0.04` s (`:152-153`), then strength â†’ `0` over `duration` with `EASE_OUT` / `TRANS_QUAD` (`:154-161`), and restores the saved override in the tween callback (`:162-170`).

`FLASH_TINTS` (`:21-28`) maps damage types to tint colors: `physical` white, `fire` `(1.0, 0.72, 0.42)`, `frost` `(0.72, 0.90, 1.0)`, `poison` `(0.78, 1.0, 0.62)`, `arcane` `(0.86, 0.72, 1.0)`, `holy` `(1.0, 0.96, 0.76)`.

`cancel(mesh)` (`:42-54`) kills the active tween, restores the saved override, and clears flash ownership metas.

`restore_all(node)` (`:57-61`) calls `cancel` on every mesh in the subtree.

## Does the flash leak color across shared materials?

**No** for active flashes. `_flash_mesh` duplicates before writing uniforms (`:134-140`) and tweens only the duplicate. Cached `PixelStyle` wall materials are never written during a flash.

`restore_all` / `cancel` restore `material_override` from saved meta or set `null` equivalent â€” they no longer write `flash_amount` onto foreign materials when no saved meta exists (`:42-54` vs the old `:82-83` path).

`MaterialDissolve` calls `MaterialFlash.cancel` before taking ownership and records `material_effect_owner = dissolve` (`material_dissolve.gd:27-28`, `:35`).

## The shader side

`pixel_diorama_surface.gdshader:22-24` declares `flash_amount`, `flash_color`, and `flash_emission`. At `:131-132` the fragment pass mixes albedo toward `flash_color` and adds emission: `EMISSION += flash_color * flash_amount * flash_emission`.

`pixel_diorama_emissive.gdshader:17-19` declares the same three uniforms. At `:44-47` quantized albedo is mixed toward `flash_color` and emission includes the flash term, so accent/emissive body parts flash with surface parts.

## Triggers

### `Hurtbox._emit_victim_feedback` (all victims)

`hurtbox.gd:242-276`. Resolves visual via `get_diorama_visual()` when present, else `Facing/DioramaVisual`. Computes:

- `proportion = clampf(damage / max(1, max_health Ã— 0.25), 0.15, 1.0)`
- `strength = lerpf(0.35, 1.0, proportion)`
- `duration = lerpf(0.14, 0.30, proportion)`
- `tint` from `FLASH_TINTS[damage_type]`
- `epicenter` from `VfxService.resolve_combat_anchor(body)[0]`
- `blocked` and `crit` (backstab) from `DamageResolution` (`hurtbox.gd:131`)

For the player, `AnimDirector.flash_viewmodel` runs the same params at `strength Ã— 0.35` (`hurtbox.gd:272-276`, `player_anim_director.gd:207-209`).

### `HitFeedback` (player-only node)

| Call | Strength / tint | Evidence |
|------|-----------------|----------|
| `on_hit` (attacker landed) | default 1.0 white on target visual | `hit_feedback.gd:80`, `:220-232` |
| `on_hit_blocked` | 0.65, `COLOR_BLOCK` | `hit_feedback.gd:114-116` |
| Parry success | 1.0, `COLOR_PARRY` | `hit_feedback.gd:133` |
| `on_hit_received` | no flash â€” victim flash is owned by `Hurtbox` | `hit_feedback.gd:97-108` |

### Player combat reactions

Parry `strength 1.0 / duration 0.10`, guard break `0.9 / 0.16`, stagger `0.85 / 0.12` (`player_combat_reactions.gd:251-271`).

### Heal

`player_heal.gd:128` flashes the diorama visual at strength `0.85` on heal commit.

### Restore

`player_combat_reactions.reset_combat_state` calls `restore_all` on the diorama visual after dissolve restore (`player_combat_reactions.gd:155-156`). `castle_enemy_base.respawn_at_rest` and `training_grunt.reset_enemy` call `restore_all` on the enemy visual (`castle_enemy_base.gd:317-319`, `training_grunt.gd:277-278`).

## Contracts

- **Meta keys on meshes** â€” `material_flash_saved_override`, `material_flash_tween`, `material_effect_owner` (shared with `MaterialDissolve`).
- **Owner values** â€” `flash` (`MaterialFlash.OWNER_FLASH`), `dissolve` (`material_dissolve.gd:11`).
- **Shader uniforms** â€” `flash_amount` required; `flash_color` and `flash_emission` applied when declared.
- **Ownership rule** â€” exactly one runtime owner of `material_override`; a second effect must `cancel` the current owner first.
- **Skip rule** â€” `SHADOW_CASTING_SETTING_SHADOWS_ONLY` meshes are never flashed.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Hit flash on every damaging hit for both teams | IMPLEMENTED | `hurtbox.gd:131`, `:242-276` |
| Per-instance duplication â€” no cross-body color leak | IMPLEMENTED | `material_flash.gd:134-140` |
| Strength and duration scale with damage proportion | IMPLEMENTED | `hurtbox.gd:262-265` |
| Blocked hits flash at half strength | IMPLEMENTED | `material_flash.gd:117-118`; `hurtbox.gd:271` |
| Damage-type tints via `FLASH_TINTS` | IMPLEMENTED | `material_flash.gd:21-28`; `hurtbox.gd:266` |
| Emissive shader parts flash | IMPLEMENTED | `pixel_diorama_emissive.gdshader:17-19`, `:44-47` |
| Flashes `DioramaVisual` only, not whole `CharacterBody3D` | IMPLEMENTED | `hurtbox.gd:254-258` |
| Skips shadows-only geometry | IMPLEMENTED | `material_flash.gd:96-97`; `diorama_character_skin.gd:554-559` |
| First-person viewmodel flash at 0.35 body strength | IMPLEMENTED | `hurtbox.gd:272-276`; `player_anim_director.gd:207-209` |
| Epicenter distance falloff (1.2 m, min 0.35) | IMPLEMENTED | `material_flash.gd:119-123`; `hurtbox.gd:267-270` |
| Ramp-in 0.03 s, crit hold 0.04 s, eased falloff | IMPLEMENTED | `material_flash.gd:145-161` |
| Guards precede all writes â€” no stuck full flash | IMPLEMENTED | `material_flash.gd:99-114` |
| `cancel` for dissolve handoff | IMPLEMENTED | `material_flash.gd:42-54`; `material_dissolve.gd:27-28` |
| `restore_all` does not write foreign cached materials | IMPLEMENTED | `material_flash.gd:42-54` |
| Enemy respawn and training dummy reset restore flash state | IMPLEMENTED | `castle_enemy_base.gd:317-319`; `training_grunt.gd:277-278` |
| Pipeline validation for shader uniforms and guard paths | IMPLEMENTED | `pixel_pipeline_suite.gd:318-410` |

## Related
- Improvement plan: [`../actual_improvements/material-flash.md`](../actual_improvements/material-flash.md) - **FINISHED**
- [`material-dissolve.md`](material-dissolve.md), [`hit-feedback.md`](hit-feedback.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`combat-core.md`](combat-core.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`pixel-style.md`](pixel-style.md), [`vfx-service.md`](vfx-service.md)
- [`validation-suites.md`](validation-suites.md)
