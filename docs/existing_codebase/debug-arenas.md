# Debug arenas

Training and tooling scenes under `scenes/debug/`: the hub-reachable combat sandbox with six `training_grunt` dummies, a headless validation entry scene, a shader/shadow probe, and an unused empty world. On the live play path only via hub arena door â†’ `RunFlow.go_to_arena()` â†’ `combat_arena.tscn`. Player deaths in the arena reset locally and never call `RunFlow.on_player_died` penalties.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/debug/combat_arena.gd` | Training session root: diorama, death reset, hub return, duel reset |
| `apps/game/client/scripts/debug/arena_diorama.gd` | Procedural 30Ã—30 castle floor, walls, hub-return portal dress, four accent lights |
| `apps/game/client/scripts/debug/debug_overlay.gd` | F1/F2/F3 debug HUD; FPS, combat state, seeds, `reset_duel` |
| `apps/game/client/scripts/debug/mcp_validation.gd` | 4-line alias extending `validation_runner.gd` (not used by the scene) |
| `apps/game/client/scripts/validation/validation_runner.gd` | Headless suite orchestrator attached to `mcp_validation.tscn` |
| `apps/game/client/scripts/validation/suites/arena_suite.gd` | Seven behavioral assertions for the training arena |
| `apps/game/client/scenes/debug/combat_arena.tscn` | Player, six authored `training_grunt` instances, `HubReturn`, `DebugOverlay`, `CombatHUD` |
| `apps/game/client/scenes/debug/mcp_validation.tscn` | Headless runner root (`validation_runner.gd`) |
| `apps/game/client/scenes/debug/shadow_probe.tscn` | Shader/shadow grid probe (`shadow_probe.gd`) |
| `apps/game/client/scenes/debug/empty_world.tscn` | Bare 40Ã—40 floor + player; no script, no code references |

## How it works

### Hub entry

`hub.gd` maps `"arena_door"` â†’ `_enter_arena` (`hub.gd:15`, `hub.gd:330-334`). Without Shift held, `RunFlow.go_to_arena()` runs; with Shift, `open_loadout()` opens the loadout UI instead.

`RunFlow.go_to_arena()` (`run_flow.gd:386-387`) calls `_goto_scene(ARENA_SCENE)` where `ARENA_SCENE` is `res://scenes/debug/combat_arena.tscn` (`run_scene_router.gd:9`, `run_flow.gd:24`). It does **not** set `_run_active`, does **not** write `LocalSave.activeRun`, and does **not** change `run_mode` (stays whatever it was, default `"castle"` from `run_flow.gd:40`).

### Combat arena lifecycle

`combat_arena.gd:_ready` (`:27-42`):

1. `add_to_group("training_arena")`
2. `PixelDioramaBootstrap.prime()` and `ArenaDioramaScript.apply(self)`
3. `PixelDioramaBootstrap.attach_deferred(self)`
4. Wire `overlay_path` and `hub_return_area_path` (default `HubReturn/InteractArea`)
5. Deferred player orientation and death wiring
6. `PlayerControls.sync_player_loadout()`

**Player death** â€” `CombatReactions.player_died` â†’ `_on_training_player_died` (`:56-62`): 0.55 s delay, then `reset_training_player()`. No XP, loot, or durability loss.

**Dummy death** â€” `Health.died` on each `training_dummy` â†’ `_on_dummy_died` (`:106-111`): `AchievementService.notify("arena_won")`, 0.8 s delay, then `reset_enemy()` on that dummy.

**Session reset** â€” `reset_training_session()` (`:65-67`) calls `reset_training_player()` then `reset_training_dummies()`. Player respawns at `PLAYER_SPAWN` `Vector3(-0.02, 0.0, 9.50)` facing `PLAYER_SPAWN_LOOK_DIR` `Vector3(0.0, -0.10, -1.0)` (`:13-14`, `:70-88`). Dummies reset via `reset_enemy()` and zero velocity (`:91-96`).

**Hub return** â€” player enters `HubReturn/InteractArea` (`collision_mask = 2`), presses `interact` â†’ `RunFlow.return_to_hub("Returned from the training arena.")` (`:136-146`).

**Duel reset input** â€” `reset_duel` action (R key, `project.godot:237-240`) forwarded to overlay `reset_duel` (`:137-138`).

### Dummy layout

`DUMMY_SPAWNS` (`combat_arena.gd:5-12`) lists six `Vector3` positions but is **never read** at runtime. Dummies are authored in `combat_arena.tscn` under `TrainingDummies/`:

| Node | Position (x, y, z) |
|------|-------------------|
| `TrainingGruntA` | (7.0, 0.0, -4.5) |
| `TrainingGruntB` | (9.5, 0.0, 0.0) |
| `TrainingGruntC` | (7.0, 0.0, 4.5) |
| `TrainingGruntD` | (-7.0, 0.0, -4.5) |
| `TrainingGruntE` | (-9.5, 0.0, 0.0) |
| `TrainingGruntF` | (-7.0, 0.0, 4.5) |

These match `DUMMY_SPAWNS` exactly today, but nothing enforces that parity. Each grunt sets `player_path = NodePath("../../Player")` in the scene.

`training_grunt.gd` adds groups `"training_dummy"`, `"lockable"`, `"enemy"` (`training_grunt.gd:36-37`, `:47-48`) and builds a procedural diorama mesh via `CharacterSkin.build_training_dummy`.

`enemy_path` on both `CombatArena` and `DebugOverlay` points at `TrainingDummies/TrainingGruntA` (`combat_arena.tscn:29`, `:105`).

### Arena diorama

`ArenaDiorama.apply` (`arena_diorama.gd:12-18`) calls `VisualLighting.apply_arena`, hides the legacy `Floor` mesh, builds a `DioramaTiles` checkerboard (30Ã—30, `TILE_SIZE = 2.0`), center-lane accent boxes, four perimeter wall meshes with `ArenaWalls/WallCollision` (`WallCollision` holds four `CollisionShape3D` children), hub-return portal architecture at `HUB_RETURN_Z = -6.0`, and four corner accent lights.

`arena_suite.gd` instantiates the scene and calls `ArenaDioramaScript.apply` again in `_test_training_arena` because `_ready` does not run in headless instantiation without entering the tree fully.

### Debug overlay

Attached on `combat_arena.tscn`, `castle_run.tscn`, and `hub.tscn`. In the arena it reads `player_path` and `enemy_path` exports.

**Input actions** (`debug_overlay.gd:47-55`, `project.godot:222-244`):

| Action | Key | Effect |
|--------|-----|--------|
| `debug_toggle` | F1 | Toggle overlay visibility |
| `debug_hitboxes` | F2 | Toggle `combat_hitbox` / `combat_hurtbox` debug meshes |
| `toggle_damage_numbers` | F3 | Toggle `HitFeedback.show_damage_numbers` |
| `reset_duel` | R | Reset player + all dummies (via arena or fallback) |

**Per-frame readouts** (`debug_overlay.gd:58-169`): FPS, dodge i-frames, guard/parry/block, player HP/stamina/speed breakdown, camera mode and lock-on tuning, **one** enemy HP line from `_enemy` (`enemy_path`, `:131-134`), training-dummy count when `> 1` (`:135-137`), hitbox draw counts, weapon debug state, `run_seed` / `tier_generation_seed` root metas, combat reaction state.

**Room label** (`:199-211`): resolves `castle_run.player_room_id`, hub as `"Aumbrye Tower"`, or `current_scene.name`.

`reset_duel` (`:257-294`) prefers `arena.reset_training_session()`; otherwise resets player to `CombatArenaScript.PLAYER_SPAWN` and all `training_dummy` group members.

### Run-flow death bypass

`RunFlow.on_player_died()` (`run_flow.gd:474-476`) returns immediately when any node is in group `"training_arena"`. All other death penalties (XP fraction, loot removal, durability, results screen) are skipped in the arena.

### MCP validation entry

Two documented entry paths (`validation_runner.gd:4-8`):

1. **CI / script:** `Godot --path . --headless --script res://scripts/validation/validation_main.gd -- --report=...`
2. **Scene:** `Godot --path . --headless res://scenes/debug/mcp_validation.tscn`

`mcp_validation.tscn` attaches `validation_runner.gd` directly (`mcp_validation.tscn:3-6`). `mcp_validation.gd` extends the same script with a back-compat comment (`mcp_validation.gd:1-3`) but is **not** the scene script.

`harness_suite.gd:_test_entrypoint_scene` (`:97-109`) asserts the scene script path equals `res://scripts/validation/validation_runner.gd`.

Report output defaults to `user://mcp_validation.json` (`test_context.gd:6`).

### Shadow probe

`shadow_probe.gd` builds a runtime test grid in `_ready` (`:23-55`):

- Directional light with optional `PROBE_TUNE` shadow settings (`:28-32`)
- Camera at `(0, 9, 14)` looking down
- `WorldEnvironment` with dark background and low ambient (`:41-49`)
- Material from `_project_material()` (pixel diorama shader `res://assets/shared/pixel_diorama_surface.gdshader`) unless `PROBE_STD` is set (`:51`, `:58-65`)
- Grid size `25Ã—20` when `PROBE_WIDE`, else `3Ã—8` (`:52-54`)
- Tiles skip shadow casting when `PROBE_NOCAST` (`:93-94`)

No script, suite, or CI job references `shadow_probe.tscn`. Launch manually from the editor or `godot --path apps/game/client res://scenes/debug/shadow_probe.tscn`.

### Empty world

`empty_world.tscn`: `Node3D` root, directional light, 40Ã—40 floor `StaticBody3D`, instanced `player.tscn` at `(0, 1, 0)`. No script on the root. Grep under `apps/game/client` finds **zero** references. **ABSENT** from play and tooling paths.

### Not this system

`castle_arena.tscn` under `scenes/rooms/castle/` is an in-dungeon room template, not the debug training arena.

## Contracts

| Contract | Detail |
|----------|--------|
| Group | `"training_arena"` on `CombatArena` root |
| Dummy group | `"training_dummy"` on each `training_grunt` |
| Entry | `RunFlow.go_to_arena` â†’ `res://scenes/debug/combat_arena.tscn` |
| Hub interact | `"arena_door"` â†’ `_enter_arena`; Shift opens loadout |
| Death | `CombatReactions.player_died` â†’ local reset only; `RunFlow.on_player_died` no-op when `"training_arena"` present |
| Overlay inputs | F1 / F2 / F3 / R (`debug_toggle`, `debug_hitboxes`, `toggle_damage_numbers`, `reset_duel`) |
| Validation output | `user://mcp_validation.json` (default), schema v3 |
| Arena suite ids | `arena.training_grunt_present`, `arena.grunt_hp_bar`, `arena.hub_return_area`, `arena.wall_collision`, `arena.reset_duel_api`, `arena.training_death_reset`, `arena.global_player_controls` |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Hub â†’ combat arena loop | IMPLEMENTED | `hub.gd:330-334`, `go_to_arena`, local death reset, hub return |
| Arena diorama | IMPLEMENTED | `arena_diorama.gd:12-18` |
| Debug overlay (arena) | IMPLEMENTED | F-keys, combat readouts, `reset_duel` |
| Six training dummies | IMPLEMENTED | `combat_arena.tscn:51-73`; `arena_suite.gd:29-35` |
| `DUMMY_SPAWNS` const | STUB | Defined `combat_arena.gd:5-12`, never referenced |
| Overlay enemy HP detail | PARTIAL | Single `enemy_path` / `TrainingGruntA` only (`debug_overlay.gd:131-134`) |
| `mcp_validation.gd` alias | PLACEHOLDER | Scene uses `validation_runner.gd` (`mcp_validation.tscn:3-6`) |
| `empty_world.tscn` | ABSENT from play/tooling path | No script references under `apps/game/client` |
| `shadow_probe` | PLACEHOLDER | Manual/env probe; not in `validation_runner.gd` `SUITE_PATHS` |
| Sandbox run marker | ABSENT | `go_to_arena` sets no `run_mode` or sandbox flag (`run_flow.gd:386-387`) |

## Related

- Improvement plan: [`../actual_improvements/debug-arenas.md`](../actual_improvements/debug-arenas.md) - **FINISHED**
- [`run-flow.md`](run-flow.md) â€” `go_to_arena`, death bypass
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md) â€” headless runner and `arena_suite.gd`
- [`tools-scripts.md`](tools-scripts.md) â€” CI Godot entry via `validation_main.gd`
- [`enemies.md`](enemies.md) â€” `training_grunt`
- [`hit-hurtboxes.md`](hit-hurtboxes.md) â€” F2 debug draw
- [`lock-on.md`](lock-on.md) â€” dummies are `lockable`
- [`floor-shell.md`](floor-shell.md) â€” `ArenaDiorama` floor dressing
- [`portal-ellipse-shader.md`](portal-ellipse-shader.md) â€” hub-return portal dress
