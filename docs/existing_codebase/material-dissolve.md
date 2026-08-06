# Material dissolve

Death dissolve for character bodies, driven by `dissolve_clip` on `pixel_diorama_surface.gdshader` and `pixel_diorama_emissive.gdshader`. On the live play path for player death, enemy and boss death, training dummy death, and illusory walls.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/material_dissolve.gd` | `play_death_visual`, `reset_death_visual`, `dissolve`, `restore`, rig-kind defaults |
| `apps/game/client/assets/shared/pixel_diorama_surface.gdshader` | Object-space dither discard with sweep |
| `apps/game/client/assets/shared/pixel_diorama_emissive.gdshader` | Matching `dissolve_clip` / `flash_amount` discard |
| `apps/game/client/scripts/art/characters/material_flash.gd` | `cancel(mesh)` for flash handoff |
| `apps/game/client/scripts/player/player_combat_reactions.gd` | Player body and viewmodel death |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | Enemy death and `respawn_at_rest` restore |
| `apps/game/client/scripts/enemies/training_grunt.gd` | Dummy death and `reset_enemy` restore |
| `apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd` | Skips dissolve-owned meshes when tracking materials |
| `apps/game/client/scripts/art/vfx/vfx_service.gd` | `play_death` with optional `debris_count` scaling |

## How it works

### `play_death_visual(visual, opts)` (`material_dissolve.gd:47-56`)

1. Merges `opts` with rig-kind defaults from `DEATH_DEFAULTS` or manifest `death` block (`:147-158`).
2. Records `position`, `scale`, and every mesh `material_override` under meta `death_visual_state` on the visual (`:175-186`).
3. Calls `VfxService.play_death` when `opts` contains `vfx_position` (`:51-54`).
4. Calls `dissolve(visual, merged)` (`:55`).
5. Applies sink or fallback scale via `_apply_sink_and_scale` (`:201-219`): animator-bound rigs sink 1.2 m after 0.45 s; legacy rigs scale to `(0.2, 0.05, 0.2)` and move to `y = -0.8`; blob rigs squash height to 60% over 0.15 s.

### `reset_death_visual(visual)` (`:59-63`)

Calls `restore(visual)` then restores pose and materials from `death_visual_state` and removes the meta (`:189-200`).

### `dissolve(node, opts)` (`:66-121`)

1. Returns immediately when the node is not inside the tree (`:69-71`) â€” no `material_override` mutation.
2. For each mesh: calls `MaterialFlash.cancel(mesh)`, saves pre-dissolve override under `material_dissolve_saved_override`, duplicates the active `ShaderMaterial`, sets `dissolve_clip = 1.0`, `flash_amount = 0.0`, sweep uniforms, and tweens `dissolve_clip` from `1.0` to `0.0` over `opts.duration` with per-part stagger (`:79-121`).

Per-part stagger offsets (`_stagger_for_mesh`, `:265-279`): legs `0.0`, arms `35%` of max stagger, torso/tail `55%`, head `100%`.

Rig-kind defaults (`DEATH_DEFAULTS`, `:22-29`): humanoid `0.65 s / 0.12 stagger / 6 debris`; quadruped `0.6 / 0.10 / 5`; blob `0.45 / 0 / 4`; flyer `0.5 / 0 / 3`; boss_humanoid `1.4 / 0.35 / 14`; construct `1.1 / 0.4 / 10`.

### `restore(node)` / `_restore_mesh` (`:124-128`, `:222-230`)

Restores `material_dissolve_saved_override` when present; otherwise warns and does not write shader uniforms onto shared materials.

### Shader discard (`pixel_diorama_surface.gdshader:127-140`)

Object-space cell hash with Y term: `cell3 = floor(v_local_pos * pixel_scale * 0.5)`, dither from `cell3.xz` plus Y offsets. Sweep via `dissolve_dir`, `dissolve_origin`, `dissolve_sweep` biases discard from feet upward by default. Emissive shader duplicates the same block (`pixel_diorama_emissive.gdshader`).

## Call sites

**Player** â€” `player_combat_reactions._run_death_sequence` (`:234-248`) builds opts from `death_opts_for_profile("player")`, passes killing-blow `sweep_dir`, calls `play_death_visual` on `Facing/DioramaVisual` and `Viewmodel/ViewRoot` (viewmodel opts omit `vfx_position` to avoid double burst). `reset_combat_state` (`:152-161`) calls `reset_death_visual` on both.

**Enemies** â€” `castle_enemy_base._play_death_visual` (`:384-398`) uses `death_opts_for_enemy` with archetype manifest, boss flag, and `_last_hit_direction`. `respawn_at_rest` (`:318-320`) calls `reset_death_visual` before `MaterialFlash.restore_all`.

**Training dummy** â€” `training_grunt._on_died` (`:239-244`) calls `play_death_visual` with `duration = 0.4`. `reset_enemy` calls `reset_death_visual`.

## Contracts

- Meta keys: `material_dissolve_saved_override` on meshes during dissolve; `death_visual_state` on visual root during death.
- `owned_materials` meta on `DioramaVisual` and viewmodel holder (`diorama_character_skin.gd:747`, `diorama_viewmodel.gd:31`); dissolve warns when absent.
- `MaterialFlash.cancel` must run before dissolve captures the saved override.
- `PixelDioramaSettings._track_materials_recursive` skips meshes carrying `material_dissolve_saved_override` (`pixel_diorama_settings.gd:595-597`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Player third-person death dissolve | IMPLEMENTED | `player_combat_reactions.gd:241-248` |
| Player viewmodel death dissolve | IMPLEMENTED | `player_combat_reactions.gd:245-248` |
| Enemy and boss death dissolve | IMPLEMENTED | `castle_enemy_base.gd:384-398` |
| Rest respawn restores visual | IMPLEMENTED | `castle_enemy_base.gd:318-320` |
| Training dummy dissolve and reset | IMPLEMENTED | `training_grunt.gd:239-244`, `:269` |
| Object-space height-aware dither | IMPLEMENTED | `pixel_diorama_surface.gdshader:127-140` |
| Emissive shader parity | IMPLEMENTED | `pixel_diorama_emissive.gdshader` |
| Per-rig duration, stagger, debris | IMPLEMENTED | `material_dissolve.gd:22-29`, `death_opts_for_enemy` |
| Flash dissolve handoff | IMPLEMENTED | `material_flash.gd:41`, `material_dissolve.gd:79-84` |
| Out-of-tree dissolve is a no-op | IMPLEMENTED | `material_dissolve.gd:69-71` |
| Settings skip in-flight duplicates | IMPLEMENTED | `pixel_diorama_settings.gd:595-597` |
| Validation suite | IMPLEMENTED | `death_visual_suite.gd`, `pixel_pipeline_suite.gd` |

## Related
- Improvement plan: [`../actual_improvements/material-dissolve.md`](../actual_improvements/material-dissolve.md) - **FINISHED**
- [`material-flash.md`](material-flash.md), [`pixel-style.md`](pixel-style.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`vfx-service.md`](vfx-service.md)
- [`enemies.md`](enemies.md), [`player-combat-reactions.md`](player-combat-reactions.md), [`validation-suites.md`](validation-suites.md)
