# Material flash — improvement plan

## Status: FINISHED

## Current state

`MaterialFlash.flash` validates before mutating, owns `material_override` through `material_effect_owner`, supports a `params` dictionary (strength, tint, duration, blocked, crit, epicenter, falloff), tweens with a 0.03 s ramp-in, optional crit hold, and eased falloff. Both pixel shaders declare `flash_amount`, `flash_color`, and `flash_emission`. `Hurtbox._emit_victim_feedback` targets the victim's `DioramaVisual`, derives params from damage proportion and `FLASH_TINTS`, and flashes the player viewmodel at 0.35 strength. `MaterialDissolve` calls `cancel` before taking ownership. Enemy respawn and training-dummy reset call `restore_all`. See [`../existing_codebase/material-flash.md`](../existing_codebase/material-flash.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| FLS-01 | P0 | `_flash_mesh` wrote saved-override meta and mounted duplicates before guards could return, leaving meshes stuck at full flash or stale metas | old `:29-47` | FINISHED |
| FLS-02 | P0 | `strength` exposed but hurtbox always passed default 1.0 — chip and lethal hits looked identical | old `hurtbox.gd:136` | FINISHED |
| FLS-03 | P1 | Blocked chip hits flashed like clean hits | old `hurtbox.gd:50-51`, `:60` | FINISHED |
| FLS-04 | P1 | `flash(body)` walked entire `CharacterBody3D`, duplicating viewmodel and hidden meshes | old `:19-25` | FINISHED |
| FLS-05 | P1 | Emissive shader had no `flash_amount` — accent parts never flashed | old `pixel_diorama_emissive.gdshader:9-16` | FINISHED |
| FLS-06 | P1 | `restore_all` wrote `flash_amount` onto shared cached materials | old `:82-83` | FINISHED |
| FLS-07 | P1 | Pure-white albedo mix with no tint or emission | old `pixel_diorama_surface.gdshader:126` | FINISHED |
| FLS-08 | P1 | Fixed 0.25 s linear fade with no ramp-in or hit-stop alignment | old `:7`, `:50-57` | FINISHED |
| FLS-09 | P1 | No enemy path called `restore_all` on respawn | old `castle_enemy_base.gd:226-253` | FINISHED |
| FLS-10 | P1 | No `cancel` — dissolve captured flash duplicates as originals | old `:29-32`; `material_dissolve.gd:20-28` | FINISHED |
| FLS-11 | P2 | Uniform flash — no epicenter falloff | old `:15-16` | FINISHED |

## Target design

### 1. Correct ordering and a single owner of `material_override`

`_flash_mesh` validates before it mutates. `META_OWNER` (`material_effect_owner`) is shared with `MaterialDissolve`. Public `cancel(mesh)` kills the tween, restores the saved override, and clears metas. Closes FLS-01 and FLS-10.

`restore_all` stops writing uniforms into materials it did not create. Closes FLS-06.

### 2. The flash carries information

`flash(node, params)` dictionary:

```gdscript
{
    "strength": 0.0..1.0,
    "tint": Color,
    "duration": float,
    "blocked": bool,
    "crit": bool,
    "epicenter": Vector3,
    "falloff": float,
}
```

`Hurtbox._emit_victim_feedback` derives strength, duration, and tint from damage proportion and `damage_type`; halves strength when `blocked`. Closes FLS-02 and FLS-03.

### 3. Shader support for tint and a real peak

Both shaders gain `flash_amount`, `flash_color`, `flash_emission`. Tween: 0.03 s ramp in, optional crit hold 0.04 s, `EASE_OUT` / `TRANS_QUAD` falloff. Closes FLS-05, FLS-07, FLS-08.

### 4. Flash the rig, not the body

Target `DioramaVisual` via `get_diorama_visual()`. Skip `SHADOW_CASTING_SETTING_SHADOWS_ONLY`. Player viewmodel flashes at `strength × 0.35` via `AnimDirector.flash_viewmodel`. Closes FLS-04.

### 5. Localized flash

Optional `epicenter` and `falloff` (default 1.2 m) scale per-mesh strength by distance. Closes FLS-11.

### 6. Restore coverage

`castle_enemy_base.respawn_at_rest` and `training_grunt.reset_enemy` call `restore_all`. Closes FLS-09.

## Work plan

1. **Reorder `_flash_mesh`; add `cancel`, ownership meta, shadows-only skip; fix `restore_all`** — FLS-01, FLS-06, FLS-10, FLS-04 (duplication half).
2. **Retarget hurtbox at `DioramaVisual`; add `flash_viewmodel` on player** — FLS-04 remainder.
3. **Add `restore_all` to enemy respawn and training dummy reset** — FLS-09.
4. **Params dictionary; thread `blocked` and backstab from `receive_hit`** — FLS-02, FLS-03.
5. **Add shader uniforms on surface and emissive** — FLS-05, FLS-07.
6. **Ramp, crit hold, eased falloff tween** — FLS-08.
7. **Epicenter falloff from combat anchor** — FLS-11.
8. **`MaterialDissolve` calls `cancel` and sets dissolve owner** — FLS-10.

## Data and schema changes

No `content/` schema changes. `FLASH_TINTS` is keyed on existing `damage_type` values on `DamageInfo`. No save-format change.

## Acceptance criteria

- [x] No mesh left at `flash_amount > 0` with no active tween after guards or tween completion (FLS-01)
- [x] Detached rig: `material_override` unchanged when `get_tree()` is null (FLS-01)
- [x] Chip hit flashes weaker and shorter than a 25% max-health hit (FLS-02)
- [x] Blocked hit flashes at half unblocked strength (FLS-03)
- [x] Fire, frost, poison, arcane tints differ via `FLASH_TINTS` (FLS-07)
- [x] Emissive accent parts flash on training dummy (FLS-05)
- [x] Body flash skips shadows-only geometry and does not walk `Viewmodel` (FLS-04)
- [x] Viewmodel flashes at 0.35 body strength (FLS-04)
- [x] Enemy respawn and training reset leave no flash meta (FLS-09)
- [x] Dissolve calls `cancel` before owning `material_override` (FLS-10)
- [x] Cached wall/accent materials unchanged after flash cycles (FLS-06)
- [x] Epicenter falloff scales local strength (FLS-11)
- [x] Peak occurs after 0.03 s ramp-in, not on first sample (FLS-08)

## Validation

Extended `apps/game/client/scripts/validation/suites/pixel_pipeline_suite.gd`, category `graphics`:

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `flash.shader_uniforms_present` | Both shaders declare `flash_amount`, `flash_color`, `flash_emission` | FLS-05 |
| `flash.no_mutation_on_guard_paths` | `StandardMaterial3D` and out-of-tree nodes unchanged after `flash` | FLS-01 |
| `flash.always_settles` | After tween, `flash_amount == 0`, no flash metas, override restored | FLS-01 |
| `flash.no_cached_material_mutation` | Cached wall/accent identity and `flash_amount` unchanged after 20 flashes | FLS-06 |

Manual checklist:
- Flash reads as a hit landing rather than the body turning white at 480×270 internal resolution.

## Related

- Current behavior: [`../existing_codebase/material-flash.md`](../existing_codebase/material-flash.md)
- [`material-dissolve.md`](material-dissolve.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`hit-feedback.md`](hit-feedback.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`combat-core.md`](combat-core.md), [`pixel-style.md`](pixel-style.md), [`vfx-service.md`](vfx-service.md), [`validation-suites.md`](validation-suites.md)
- [`character-authoring.md`](character-authoring.md)
