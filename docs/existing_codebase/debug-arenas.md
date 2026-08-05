# Debug arenas

Training and tooling scenes under `scenes/debug/`: the hub-reachable combat arena with six dummies, a headless validation entry scene, a shadow/shader probe, and an unused empty world. On the live path only via hub arena entry → `RunFlow.go_to_arena()` → `combat_arena.tscn`. Deaths in the arena reset locally and do not call `RunFlow.on_player_died`.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/debug/combat_arena.gd` | Training session: diorama, death reset, hub return, duel reset |
| `apps/game/client/scripts/debug/arena_diorama.gd` | Procedural 30×30 castle floor, walls, torches, portal dress |
| `apps/game/client/scripts/debug/debug_overlay.gd` | F1/F2/F3 debug HUD; FPS, combat state, seeds |
| `apps/game/client/scripts/debug/mcp_validation.gd` | 4-line alias extending `validation_runner.gd` |
| `apps/game/client/scenes/debug/combat_arena.tscn` | Player, 6× `training_grunt`, HubReturn, DebugOverlay, CombatHUD |
| `apps/game/client/scenes/debug/mcp_validation.tscn` | Headless runner (`validation_runner.gd` on root) |
| `apps/game/client/scenes/debug/shadow_probe.tscn` | Shader/shadow probe (`shadow_probe.gd`) |
| `apps/game/client/scenes/debug/empty_world.tscn` | Bare floor + player; no script, no code references |

## How it works

### Combat arena

`RunFlow.go_to_arena` (`run_flow.gd:328-329`) loads `ARENA_SCENE` without setting a formal run (`_run_active` stays false). Hub opens this when near the arena interactable (`hub.gd:143-149`).

`combat_arena.gd:_ready` (`:27-42`): group `"training_arena"`, `ArenaDiorama.apply`, pixel bootstrap, overlay/hub wiring, `PlayerControls.sync_player_loadout()`. Player death → 0.55s → `reset_training_player` (`:56-62`) — no XP/loot penalties. `reset_training_session` resets player + all dummies (`:65-97`). Hub return on interact → `RunFlow.return_to_hub` (`:134-144`).

`DUMMY_SPAWNS` const (`:5-12`) is **unused** — dummies are placed only in the `.tscn` at ±7 / ±9.5. `enemy_path` export points at a single grunt for overlay HP.

### Arena diorama

`arena_diorama.gd`: checkerboard floor, center lane accents, four wall meshes + collision, hub-return portal architecture, four corner lights. Hides legacy floor mesh.

### Debug overlay

`debug_overlay.gd`: F1 toggles overlay, F2 hitboxes, F3 damage numbers (`:47-55`). Per-frame: FPS, dodge/guard, HP/stamina, one enemy HP via `enemy_path`, dummy count, weapon debug, run seeds (`:58-115`). Room label resolves castle_run / hub (`:143-155`). `reset_duel` calls arena `reset_training_session` (`:201-234`).

Also instanced on `castle_run.tscn` for in-run debugging.

### MCP validation

`mcp_validation.tscn` attaches `validation_runner.gd` directly (not the alias script). Runner executes validation suites headless, writes `user://mcp_validation.json`, quits. `mcp_validation.gd` exists for back-compat class references only (4 lines).

### Other scenes

- `shadow_probe.tscn`: env-driven (`PROBE_TUNE`, `PROBE_STD`, …) material/shadow grid; not in suite list.
- `empty_world.tscn`: 40×40 floor + player; **ABSENT** from client script references.

`castle_arena.tscn` under `scenes/rooms/castle/` is an in-dungeon room template, not this debug arena.

## Contracts

| Contract | Detail |
|----------|--------|
| Group | `"training_arena"` |
| Entry | `RunFlow.go_to_arena` → `res://scenes/debug/combat_arena.tscn` |
| Death | `CombatReactions.player_died` → local reset only (`run_flow.gd:396-397` bypass) |
| Overlay inputs | F1 / F2 / F3 |
| Validation output | `user://mcp_validation.json` |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Hub → combat arena loop | IMPLEMENTED | `go_to_arena`, local death reset, hub return |
| Arena diorama | IMPLEMENTED | `arena_diorama.gd` |
| Debug overlay | IMPLEMENTED | F-keys + combat readouts |
| `DUMMY_SPAWNS` const | STUB | Unused (`combat_arena.gd:5-12`) |
| Overlay enemy HP | PARTIAL | Single `enemy_path` / TrainingGruntA only |
| `mcp_validation` alias | PLACEHOLDER | Scene uses `validation_runner.gd` directly |
| `empty_world.tscn` | ABSENT from play/tooling path | No script references |
| `shadow_probe` | PLACEHOLDER | Manual/env probe, not suite-wired |

## Related

- Improvement plan: [`../actual_improvements/debug-arenas.md`](../actual_improvements/debug-arenas.md)
- [`run-flow.md`](run-flow.md), [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md), [`enemies.md`](enemies.md) (`training_grunt`)
