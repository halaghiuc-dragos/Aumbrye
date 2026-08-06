# Material dissolve — improvement plan

## Status: FINISHED

## Current state

`MaterialDissolve.play_death_visual` records a reversible `death_visual_state`, runs object-space dither dissolve with per-rig duration, stagger, sweep direction, and debris-scaled VFX, then sinks or scales the visual. `reset_death_visual` restores pose, scale, and materials — wired into `castle_enemy_base.respawn_at_rest`, `player_combat_reactions.reset_combat_state`, and `training_grunt.reset_enemy`. Player viewmodel arms dissolve alongside the third-person body. See [`../existing_codebase/material-dissolve.md`](../existing_codebase/material-dissolve.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| DIS-01 | P0 | `respawn_at_rest` never restored dissolve state or sink offset | `castle_enemy_base.gd:318-320` | FINISHED |
| DIS-02 | P0 | Sink and fallback scale compounded across death cycles | `material_dissolve.gd:201-219`, `reset_death_visual` | FINISHED |
| DIS-03 | P1 | Emissive parts never dissolved | `pixel_diorama_emissive.gdshader` | FINISHED |
| DIS-04 | P1 | World-XZ dither read as vertical slicing | `pixel_diorama_surface.gdshader:127-140` | FINISHED |
| DIS-05 | P1 | `restore` wrote uniforms onto shared cached materials | `material_dissolve.gd:222-230` | FINISHED |
| DIS-06 | P1 | Flash duplicate captured as dissolve original | `material_flash.gd:41`, `material_dissolve.gd:79-84` | FINISHED |
| DIS-07 | P1 | Out-of-tree dissolve left duplicate materials mounted | `material_dissolve.gd:69-71` | FINISHED |
| DIS-08 | P1 | Uniform 0.65 s fade with no stagger or sweep | `DEATH_DEFAULTS`, stagger tween `:109-121` | FINISHED |
| DIS-09 | P1 | First-person arms not dissolved on player death | `player_combat_reactions.gd:245-248` | FINISHED |
| DIS-10 | P1 | Training dummy never dissolved | `training_grunt.gd:239-244` | FINISHED |
| DIS-11 | P2 | All rigs used 0.65 s duration | `death_opts_for_enemy`, `DEATH_DEFAULTS` | FINISHED |
| DIS-12 | P2 | Display-settings change repainted dissolving duplicates | `pixel_diorama_settings.gd:595-597` | FINISHED |

## Target design

Implemented as specified in the original plan:

- **`play_death_visual` / `reset_death_visual`** with `death_visual_state` meta on the visual root.
- **Object-space, height-driven dither** with `dissolve_origin`, `dissolve_dir`, `dissolve_sweep` on both surface and emissive shaders.
- **Material ownership**: `owned_materials` meta on built visuals; `_restore_mesh` never writes shared materials; `MaterialFlash.cancel` before dissolve capture.
- **Per-rig defaults** in `DEATH_DEFAULTS` with optional manifest `death` block override via `CharacterRigCatalog.get_manifest`.
- **Coverage**: player body + viewmodel, enemies, bosses, training dummy, illusory walls (legacy `dissolve` call).

## Work plan

1. **Death visual state API** — `material_dissolve.gd`, `castle_enemy_base.respawn_at_rest`, `player_combat_reactions.reset_combat_state` — DIS-01, DIS-02 — FINISHED
2. **Out-of-tree guard and `owned_materials` warning** — `material_dissolve.gd` — DIS-07 — FINISHED
3. **`MaterialFlash.cancel` and safe restore** — `material_flash.gd`, `material_dissolve.gd` — DIS-05, DIS-06 — FINISHED
4. **Skip dissolve meshes in settings tracking** — `pixel_diorama_settings.gd` — DIS-12 — FINISHED
5. **Viewmodel and training dummy coverage** — `player_combat_reactions.gd`, `training_grunt.gd` — DIS-09, DIS-10 — FINISHED
6. **Emissive shader parity** — `pixel_diorama_emissive.gdshader` — DIS-03 — FINISHED
7. **Object-space sweep discard** — `pixel_diorama_surface.gdshader` — DIS-04 — FINISHED
8. **Opts, stagger, sweep, debris** — `material_dissolve.gd`, `vfx_service.gd` — DIS-08, DIS-11 — FINISHED

## Data and schema changes

- Optional `death` block on character rig manifests (`duration`, `stagger`, `sweep`, `debris`) read by `_death_opts_for_rig_kind` (`material_dissolve.gd:147-158`). No schema file added yet; defaults live in `DEATH_DEFAULTS`.
- No save-format change. Death visual state is runtime-only meta.

## Acceptance criteria

- [x] An enemy killed and then respawned at a rest is fully visible, at its spawn Y, at scale 1, with its original materials. (DIS-01)
- [x] Killing and respawning the same enemy five times leaves its `DioramaVisual` position and scale identical to the values it had before the first death. (DIS-02)
- [x] A training dummy reduced to zero health dissolves, and resetting it restores it. (DIS-10)
- [x] Dying in first person dissolves the arms and the held weapon at the same time as the body. (DIS-09)
- [x] The training dummy's emissive accent parts dissolve along with its surface parts. (DIS-03)
- [x] Two identical enemies standing 0.1 m apart dissolve with visibly different patterns. (DIS-04)
- [x] The dissolve pattern moves with the body rather than staying fixed relative to the floor while the death clip plays. (DIS-04)
- [x] The dissolve begins at the feet and reaches the head last for humanoid rigs. (DIS-08)
- [x] A boss takes visibly longer to dissolve than a grunt and emits more debris chunks. (DIS-11)
- [x] Calling `dissolve` on a node outside the tree leaves every `material_override` untouched. (DIS-07)
- [x] After any dissolve and restore cycle, the cached wall material instance identity is unchanged. (DIS-05)
- [x] A hit landing within 0.1 s of a killing blow does not leave a flash duplicate mounted after the dissolve completes. (DIS-06)
- [x] Changing pixel-diorama display settings during a death does not alter the dissolving body's pattern. (DIS-12)

## Validation

`apps/game/client/scripts/validation/suites/death_visual_suite.gd` (category `graphics`) — 11 assertions, all passing:

- `death_visual.shader_uniforms_present` — both shaders declare `dissolve_clip` and `flash_amount`
- `death_visual.state_roundtrip` — `play_death_visual` + `reset_death_visual` restores pose and materials
- `death_visual.repeat_cycles_stable` — five cycles leave state unchanged
- `death_visual.no_cached_material_mutation` — cached wall material instance survives 20 cycles
- `death_visual.out_of_tree_no_mutation` — detached dissolve is a no-op
- `death_visual.flash_dissolve_handoff` — flash then dissolve restores pre-flash material
- `death_visual.stagger_ordering` — legs before arms before torso before head
- `death_visual.duration_from_catalog` — boss duration exceeds grunt; hound uses `0.6 s`
- `death_visual.viewmodel_included` — player death opts include catalog duration for viewmodel path
- `death_visual.dummy_dissolves` — dummy meshes carry dissolve meta after death
- `death_visual.settings_skip_dissolving` — `apply_all` does not rewrite in-flight duplicate `pattern_strength`

`pixel_pipeline_suite.gd` extended with `pixel_pipeline.emissive_shader_dissolve` (DIS-03).

Run: `powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd -- --suite=death_visual_suite,pixel_pipeline_suite`

Manual checklist (automation cannot judge pixel read at 480×270):

- The dissolve reads as the body coming apart into pixel cells rather than as vertical stripes or a crossfade.

## Related

- Current behavior: [`../existing_codebase/material-dissolve.md`](../existing_codebase/material-dissolve.md)
- [`material-flash.md`](material-flash.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-anim-controller.md`](diorama-anim-controller.md)
- [`pixel-style.md`](pixel-style.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`vfx-service.md`](vfx-service.md), [`hit-feedback.md`](hit-feedback.md)
- [`enemies.md`](enemies.md), [`player-combat-reactions.md`](player-combat-reactions.md), [`validation-suites.md`](validation-suites.md)
- [`character-authoring.md`](character-authoring.md)
