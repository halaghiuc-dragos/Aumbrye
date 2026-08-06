# Debug arenas — improvement plan

## Status: FINISHED

## Current state

The hub training arena works as a sandbox: six authored `training_grunt` dummies, procedural diorama via `ArenaDiorama.apply`, local death reset (0.55 s), hub return interact, F1–F3 overlay, and R duel reset. `DUMMY_SPAWNS` in `combat_arena.gd` mirrors the `.tscn` positions today but is unused, so the const can drift silently. The overlay shows HP for `TrainingGruntA` only while counting all dummies. Satellite scenes (`empty_world`, `shadow_probe`) are undocumented or manual-only, and `mcp_validation.gd` duplicates the scene's `validation_runner.gd` attachment. `go_to_arena` does not set a sandbox marker — death bypass relies on the `"training_arena"` group alone. See [`../existing_codebase/debug-arenas.md`](../existing_codebase/debug-arenas.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DBG-01 | P2 | `DUMMY_SPAWNS` unused — dummies only in `.tscn`; const can drift | `combat_arena.gd:5-12`; positions in `combat_arena.tscn:51-73` |
| DBG-02 | P2 | Overlay `enemy_path` shows one grunt HP while six dummies exist | `debug_overlay.gd:27-28`, `:131-134`; `combat_arena.tscn:105` |
| DBG-03 | P2 | `empty_world.tscn` has no script and no references — purpose unclear | `empty_world.tscn`; grep under `apps/game/client` returns zero hits |
| DBG-04 | P2 | `shadow_probe` not registered in validation suites; env-only manual probe | `shadow_probe.gd:23-55`; absent from `validation_runner.gd` `SUITE_PATHS` |
| DBG-05 | P2 | Dual validation entry: `mcp_validation.gd` alias vs scene using `validation_runner.gd` | `mcp_validation.gd:1-3`; `mcp_validation.tscn:3-6`; `harness_suite.gd:105-109` |
| DBG-06 | P2 | `go_to_arena` sets no run lifecycle flags — intentional sandbox, but no explicit query for systems that assume a run | `run_flow.gd:386-387`; death bypass uses group only at `run_flow.gd:475-476` |

## Target design

### Single source for dummy layout (DBG-01)

**Chosen:** spawn dummies from `DUMMY_SPAWNS` in `combat_arena.gd:_ready`, after diorama setup, parenting under a `TrainingDummies` node kept in the scene (empty container). Remove the six instanced `training_grunt` nodes from `combat_arena.tscn`.

```gdscript
const TRAINING_GRUNT_SCENE := preload("res://scenes/enemies/training_grunt.tscn")

func _spawn_training_dummies() -> void:
    var parent := get_node_or_null("TrainingDummies") as Node3D
    if parent == null:
        parent = Node3D.new()
        parent.name = "TrainingDummies"
        add_child(parent)
    for child in parent.get_children():
        child.queue_free()
    for pos in DUMMY_SPAWNS:
        var dummy := TRAINING_GRUNT_SCENE.instantiate() as CharacterBody3D
        dummy.position = pos
        if player_path:
            dummy.set("player_path", parent.get_path_to(get_node(player_path)))
        parent.add_child(dummy)
    call_deferred("_wire_dummy_death_reset")
```

Keep `enemy_path` / overlay default pointing at the first spawned child (or drop `enemy_path` once DBG-02 resolves focus dynamically).

**Rejected:** delete `DUMMY_SPAWNS` and trust the `.tscn` — `debug_overlay.gd` already preloads `CombatArenaScript` for `PLAYER_SPAWN` (`:297-301`); the const is the natural shared contract for layout tests and designer tuning.

### Overlay multi-dummy readout (DBG-02)

Add `_resolve_focus_dummy() -> CharacterBody3D` on `debug_overlay.gd`:

1. If `_player` has `LockOn` with `is_locked` and valid `current_target` in group `"training_dummy"`, use that target.
2. Else nearest `training_dummy` to `_player.global_position` (planar distance, `y` ignored).
3. Else first node in `"training_dummy"` group.
4. Else fall back to `_enemy` from `enemy_path` export (castle_run / hub compatibility).

Display lines:

```
training dummies: N/6 alive
focus HP: <current> / <max> (<node.name>)
```

Remove the `dummy_count > 1` guard (`debug_overlay.gd:136`) so a single dummy still shows the aggregate line. Keep one detail HP line to avoid overlay spam.

### Scene inventory hygiene (DBG-03, DBG-04, DBG-05)

| Scene / file | Decision |
|--------------|----------|
| `empty_world.tscn` | **Delete** — zero references, superseded by `combat_arena.tscn` and `shadow_probe.tscn` for sandbox needs. Document removal in [`tools-scripts.md`](tools-scripts.md) only if a runner ever referenced it (none today). |
| `shadow_probe.tscn` | Keep as manual shader lab. Add `arena.shadow_probe_loads` (or `graphics.shadow_probe_loads`) in a graphics or arena suite: instantiate scene, await two frames, assert no `push_error` and root child count > 0. Document env vars in [`tools-scripts.md`](tools-scripts.md): `PROBE_TUNE`, `PROBE_STD`, `PROBE_WIDE`, `PROBE_NOCAST`. |
| `mcp_validation.gd` | **Delete** the alias file. Scene already uses `validation_runner.gd`; `harness_suite.gd:105-109` locks that contract. Update any `preload("res://scripts/debug/mcp_validation.gd")` call sites (grep before delete). |

**Rejected for DBG-05:** retarget `mcp_validation.tscn` to the alias — adds an indirection layer with no behavior benefit; the harness already asserts the canonical path.

### Sandbox mode flag (DBG-06)

Add explicit sandbox state on `RunFlow` so systems do not infer arena from scene tree groups:

```gdscript
# run_flow.gd
var _sandbox_active := false

func go_to_arena() -> void:
    _sandbox_active = true
    _goto_scene(ARENA_SCENE)

func return_to_hub(message: String = "") -> void:
    _sandbox_active = false
    # ... existing body ...

func is_sandbox_active() -> bool:
    return _sandbox_active
```

Do **not** write `LocalSave.activeRun` or set `_run_active = true`. Keep `on_player_died` group check as a belt-and-suspenders guard. Optional: add `RunModeConfig.MODE_ARENA := "arena"` only if a quest or audio hook needs a string mode; the bool is sufficient for DBG-06.

**Rejected:** overload `run_mode = "arena"` without clearing on every non-arena `_goto_scene` — too easy to leak state; a dedicated bool cleared in `return_to_hub` and any future hub-only transitions is safer.

## Work plan

1. **Code-spawn dummies from `DUMMY_SPAWNS`** — add `_spawn_training_dummies()` to `combat_arena.gd`; remove six `training_grunt` instances from `combat_arena.tscn`; keep empty `TrainingDummies` node. Update `arena_suite.gd` to assert positions against `CombatArenaScript.DUMMY_SPAWNS` after `_ready`. Closes DBG-01.

2. **Overlay focus target** — add `_resolve_focus_dummy()` to `debug_overlay.gd`; replace static `_enemy` HP block with focus line + `N/6 alive` aggregate. Closes DBG-02.

3. **Single validation entry path** — delete `mcp_validation.gd`; grep for references; confirm `harness.entrypoints.scene_matches_script` still passes. Closes DBG-05.

4. **Delete `empty_world.tscn`** — remove file; add `docs_suite` or `arena_suite` assertion that the path does not exist (prevents reintroduction). Closes DBG-03.

5. **Wire `shadow_probe` smoke test** — add `graphics.shadow_probe_loads` to `pixel_pipeline_suite.gd` or extend `arena_suite.gd` with a load-only test. Document env vars in [`tools-scripts.md`](tools-scripts.md). Closes DBG-04.

6. **Sandbox marker on `go_to_arena`** — add `_sandbox_active`, `is_sandbox_active()`, set/clear in `go_to_arena` / `return_to_hub`. Add `arena.sandbox.flag` assertion in `arena_suite.gd` or `flow_suite.gd`. Closes DBG-06.

Each step is independently landable and leaves the game runnable.

## Data and schema changes

None. No content JSON. No `save_migrator.gd` version bump.

## Acceptance criteria

- [ ] After reload, dummy count equals `DUMMY_SPAWNS.size()` (6) and each `global_position` matches the corresponding const within 0.01 m; `combat_arena.tscn` contains zero instanced `training_grunt` nodes. (DBG-01)
- [ ] With lock-on targeting `TrainingGruntC`, overlay focus HP line shows `TrainingGruntC` health values. (DBG-02)
- [ ] With no lock-on, overlay focus HP tracks the nearest `training_dummy` to the player. (DBG-02)
- [ ] Overlay always shows `training dummies: N/6 alive` in the arena (including when N is 1). (DBG-02)
- [ ] `mcp_validation.tscn` root script is `validation_runner.gd`; `mcp_validation.gd` file deleted; zero `preload`/`extends` references remain. (DBG-05)
- [ ] `res://scenes/debug/empty_world.tscn` does not exist on disk. (DBG-03)
- [ ] `graphics.shadow_probe_loads` (or equivalent) passes headless: scene instantiates without errors. (DBG-04)
- [ ] After `RunFlow.go_to_arena()`, `RunFlow.is_sandbox_active()` is `true`; after `return_to_hub()`, `false`. `_run_active` stays `false` throughout. (DBG-06)
- [ ] Existing `arena_suite.gd` tests (`arena.training_grunt_present`, `arena.reset_duel_api`, `arena.training_death_reset`, `arena.global_player_controls`) still pass.

## Validation

Extend `apps/game/client/scripts/validation/suites/arena_suite.gd` (category `arena`). Do not replace existing assertions.

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `arena.dummies.from_const` | After arena `_ready`, count == `CombatArenaScript.DUMMY_SPAWNS.size()` and each dummy `global_position` matches const | DBG-01 |
| `arena.overlay.focus_lock` | Instantiate arena + overlay; set player `LockOn.current_target` to dummy B; overlay `_process` one frame; parsed label contains B's `Health.current` | DBG-02 |
| `arena.validation.single_entry` | `mcp_validation.tscn` script path is `validation_runner.gd`; `mcp_validation.gd` absent | DBG-05 |
| `arena.empty_world_removed` | `ResourceLoader.exists("res://scenes/debug/empty_world.tscn")` is false | DBG-03 |
| `arena.sandbox.flag` | Call `RunFlow.go_to_arena()` on a test tree stub or invoke `is_sandbox_active()` after setting flag in test harness; assert true, then false after `return_to_hub()` | DBG-06 |
| `graphics.shadow_probe_loads` | Load `shadow_probe.tscn`, add to tree, await 2 frames, `queue_free`; no errors | DBG-04 |

**Existing assertions to preserve:**

| Assertion id | Current check |
|--------------|---------------|
| `arena.training_grunt_present` | Six dummies under `TrainingDummies` |
| `arena.grunt_hp_bar` | First dummy has `HealthBar` |
| `arena.hub_return_area` | `HubReturn/InteractArea` exists |
| `arena.wall_collision` | Four wall collision shapes |
| `arena.reset_duel_api` | `reset_duel` restores player + dummy |
| `arena.training_death_reset` | Player death restores without run penalties |
| `arena.global_player_controls` | `PlayerControls.sync_player_loadout` wires weapon |

**Manual checklist** (automation cannot easily verify F-key UX):

1. Hub arena door (no Shift) loads `combat_arena.tscn`.
2. F1 toggles overlay; F2 draws hitboxes; F3 toggles damage numbers; R resets session.
3. Hub return portal at `z = -6` returns to hub with message.

**Run command:**

```powershell
powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd -- --suite=arena
```

## Related

- Existing state: [`../existing_codebase/debug-arenas.md`](../existing_codebase/debug-arenas.md)
- [`run-flow.md`](run-flow.md) — `go_to_arena`, death bypass, proposed `is_sandbox_active`
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md) — runner and suite registration
- [`tools-scripts.md`](tools-scripts.md) — CI Godot entry, `shadow_probe` env vars
- [`enemies.md`](enemies.md) — `training_grunt`
- [`lock-on.md`](lock-on.md) — overlay focus source
- [`hit-hurtboxes.md`](hit-hurtboxes.md) — F2 debug draw
- [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)
