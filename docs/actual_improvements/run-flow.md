# Run flow — improvement plan

## Status: FINISHED

## Current state
`RunFlow` drives castle and waves loops with unified outcome reporting via `RunLifecycle.build_results`, `run_warning` for in-frame hub/combat feedback, distance-based floor cache eviction, bonfire respawn overlays, awaited cloud finalize, and `RUN_META_KEYS` hygiene. See [`../existing_codebase/run-flow.md`](../existing_codebase/run-flow.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| RFL-01 | P0 | ~~Escape quest on death~~ **FINISHED** — `register_run_outcome(OUTCOME_ESCAPED)` from portal only | `quest_service.gd:95-97` |
| RFL-02 | P0 | ~~Mid-run generation failure leaves run unplayable~~ **FINISHED** — `_transition_floor` restores definition; `run_warning` emitted | `run_flow.gd:_transition_floor` |
| RFL-03 | P0 | ~~Waves `levels_gained` / `run_relics_lost` dishonest~~ **FINISHED** — all outcomes via `build_results` | `run_lifecycle.gd`, `run_flow.gd` |
| RFL-04 | P1 | ~~Floor cache string-key eviction~~ **FINISHED** — int keys, distance eviction | `run_flow.gd:_trim_floor_cache` |
| RFL-05 | P1 | ~~Bonfire death silent reload~~ **FINISHED** — `run_respawn_results` overlay in `castle_run` / `combat_hud` | `run_flow.gd:_bonfire_death_respawn` |
| RFL-06 | P1 | ~~`playerDead` flip-flop autosave~~ **FINISHED** — single write, `playerDead` erased | `run_flow.gd:_bonfire_death_respawn` |
| RFL-07 | P1 | ~~Failed run start silent in hub~~ **FINISHED** — `run_warning` + hub subscribe | `run_flow.gd:run_warning`, `hub.gd:_on_run_warning` |
| RFL-08 | P1 | ~~Cloud finalize swallowed~~ **FINISHED** — awaited status, `cloud_synced` on results | `run_flow.gd:_cloud_finalize_run` |
| RFL-09 | P2 | ~~Stale `floor_transition` / `run_results` metas~~ **FINISHED** — `RUN_META_KEYS` + `_clear_run_meta` | `run_flow.gd:RUN_META_KEYS` |
| RFL-10 | P2 | ~~Dead code in `run_flow.gd`~~ **FINISHED** — removed `_start_run`, `_try_online_generate`, `_unload_current_floor_chunk` | `run_flow.gd` |
| RFL-11 | P2 | ~~Waves results drift from `RunLifecycle`~~ **FINISHED** — waves paths use `build_results` | `run_flow.gd:complete_waves_run` |

## Target design

### Honest outcome reporting
Every outcome flows through one builder in `run_lifecycle.gd`, and the run emits a typed *outcome* rather than a bare dictionary. Add:

```gdscript
# run_lifecycle.gd
const OUTCOME_ESCAPED := "escaped"
const OUTCOME_DIED := "died"
const OUTCOME_RESPAWNED := "respawned"
const OUTCOME_RETREATED := "retreated"
const OUTCOME_ABANDONED := "abandoned"
const OUTCOME_WAVES_COMPLETE := "waves_complete"
const OUTCOME_WAVES_FAILED := "waves_failed"

static func build_results(
    outcome: String,
    elapsed: float,
    kill_count: int,
    loot_collected: Array,
    xp_result: Dictionary,
    full_xp: int,
    rules_summary: String,
    extra: Dictionary = {}
) -> Dictionary
```

The returned dictionary always carries the same key set, so `results_screen.tscn` never has to branch on presence:

| Key | Type | Meaning |
|-----|------|---------|
| `outcome` | String | one of the `OUTCOME_*` constants |
| `run_mode` | String | `castle` / `endless` / `waves` |
| `time_seconds` | float | elapsed wall time |
| `kills` | int | `_kill_count` at resolution |
| `loot` | Array[String] | item ids kept **after** the outcome rule applied |
| `loot_lost` | Array[String] | item ids removed by the outcome rule |
| `xp_gained` | int | XP actually granted |
| `xp_full_would_be` | int | XP the run was worth before the outcome fraction |
| `xp_deferred` | int | XP parked in the recoverable shard |
| `levels_gained` | int | always `xp_result.levels_gained` |
| `loot_kept` | bool | `loot_lost.is_empty()` |
| `run_relics_lost` | bool | whether `RunBuffs.clear_all()` discarded relics |
| `floor_reached` | int | `current_floor` |
| `boss_defeated` | bool | `_boss_defeated` |
| `cloud_synced` | bool | set by `_cloud_finalize_run` before the results scene reads it |
| `rules_summary` | String | player-facing sentence |

`loot_lost` is computed by diffing `_loot_collected` against the inventory after `remove_run_loot`, not asserted. `xp_deferred` is the exact value handed to `store_recoverable_xp_shard`, so the results screen and the shard label cannot disagree.

Chosen over "add the missing keys to the waves dictionaries": a single builder is the only way to keep the two paths from drifting again, and RFL-11 disappears for free.

### Escape-quest honesty
`run_ended` stops being a proxy for "the player escaped". `QuestService` gains an explicit hook and `RunFlow` calls it only from the escape path:

```gdscript
# quest_service.gd
func register_run_outcome(outcome: String, context: Dictionary) -> void
```

`_check_escape_quests()` becomes private to that call and requires `outcome == RunLifecycle.OUTCOME_ESCAPED`. `_on_run_ended` is reduced to clearing per-run progress for `escape`-type quests. The existing public `check_escape_on_portal()` (no call site today) is deleted rather than left as an attractive nuisance.

### Mid-run generation failure
`_transition_floor` keeps the previous definition until the replacement is proven good:

```gdscript
func _transition_floor(ascending: bool) -> void:
    var previous_definition := current_dungeon_definition.duplicate(true)
    var previous_floor := current_floor
    var definition := _resolve_floor_definition(current_floor)
    if definition.is_empty():
        current_floor = previous_floor
        current_dungeon_definition = previous_definition
        _emit_run_warning("Could not generate floor %d — you are still on floor %d." % [...])
        return
    ...
```

`_resolve_floor_definition(floor_index: int) -> Dictionary` centralises cache lookup and regeneration. A new signal `run_warning(message: String)` replaces the silent `last_hub_message` write so the combat HUD can toast it in place; the same signal serves RFL-07 when a start fails, with the hub subscribing in `hub.gd:_ready`.

Rejected alternative: kicking the player back to the hub on a generation failure. That destroys an in-progress run for a transient failure, and the previous floor is still fully loaded and playable.

### Floor cache
Key `floor_definitions` by `int`, not `String`, and evict by numeric distance from the active floor rather than by minimum:

```gdscript
func _trim_floor_cache() -> void:
    if floor_definitions.size() <= MAX_CACHED_FLOORS:
        return
    var keys: Array[int] = []
    for key in floor_definitions:
        keys.append(int(key))
    keys.sort_custom(func(a: int, b: int) -> bool:
        return absi(a - current_floor) > absi(b - current_floor)
    )
    while floor_definitions.size() > MAX_CACHED_FLOORS:
        floor_definitions.erase(keys.pop_front())
```

Distance ordering keeps floor N-1 and N+1 resident, which is what a player actually revisits with the stair lever.

### Bonfire respawn outcome
`_bonfire_death_respawn` builds `OUTCOME_RESPAWNED` results and shows them as a non-blocking overlay in the reloaded dungeon scene rather than routing to `RESULTS_SCENE`. It writes `run_respawn_results` as a root meta which `castle_run.gd` reads once on `_ready` and clears. The sequence also stops the `playerDead` flip-flop:

```gdscript
var active := LocalSave.get_active_run()
active["snapshot"] = checkpoint.duplicate(true)
active.erase("playerDead")
LocalSave.set_active_run(active)
```

A single write, a single autosave. `playerDead` is only ever set by the terminal death path, where the run is cleared immediately afterwards anyway.

### Cloud finalize visibility
`_cloud_finalize_run` returns its status and stamps the results dictionary:

```gdscript
func _cloud_finalize_run(...) -> Dictionary  # {"ok": bool, "reason": String}
```

`complete_run_via_portal` and `on_player_died` `await` it before setting the `run_results` meta, so `cloud_synced` is truthful. `"auth failed"` maps to `reason = "offline"` and is displayed as "Run saved locally (offline)" rather than being swallowed.

### Meta hygiene
`_clear_run_meta()` gains `floor_transition` and `run_results`; the meta name list becomes a `const RUN_META_KEYS: Array[String]` so adding a meta cannot skip cleanup. `run_results` is cleared by the results scene after it reads the dictionary, and defensively by `_clear_run_meta` on the next run start.

## Work plan

1. **Introduce `RunLifecycle.build_results` and the outcome constants** — `run_lifecycle.gd`: add `OUTCOME_*`, add `build_results()`, keep `build_escape_results` / `build_death_results` as thin wrappers so nothing breaks in one commit. Fixes nothing yet; game runnable.
2. **Route all five `RunFlow` outcome sites through `build_results`** — `run_flow.gd:355-392`, `395-431`, `929-948`, `951-972`, `975-995`. Compute `loot_lost` by diffing before/after `InventoryService.remove_run_loot`. Delete the wrappers. Closes RFL-03, RFL-11.
3. **Add `run_warning` signal and `_resolve_floor_definition`** — `run_flow.gd`: new signal, new helper, rewrite `_transition_floor` with the restore-on-failure contract, replace the `last_hub_message` writes at lines 156 and 558 with `_emit_run_warning`. Subscribe in `hub.gd:_ready` and in the combat HUD. Closes RFL-02, RFL-07.
4. **Fix the floor cache** — `run_flow.gd:610-646`: int keys, distance-based eviction. Closes RFL-04.
5. **Add `QuestService.register_run_outcome` and gate escape quests** — `quest_service.gd`: new method, make `_check_escape_quests` require the escaped outcome, reduce `_on_run_ended` to progress reset, delete `check_escape_on_portal`. Call `register_run_outcome` from `complete_run_via_portal` only. Closes RFL-01.
6. **Rework bonfire respawn** — `run_flow.gd:815-847`: single `activeRun` write, `run_respawn_results` meta, `OUTCOME_RESPAWNED` results. `castle_run.gd`: read and clear the meta on `_ready`, hand it to the HUD overlay. Closes RFL-05, RFL-06.
7. **Make cloud finalize awaited and reported** — `run_flow.gd:736-755`: return a status dictionary, `await` it in both terminal paths, stamp `cloud_synced` and the offline reason. Closes RFL-08.
8. **Meta hygiene and dead-code removal** — `run_flow.gd`: `RUN_META_KEYS` const, extend `_clear_run_meta`, delete `_try_online_generate`, `_start_run`, `_unload_current_floor_chunk`. Keep the `USE_ONLINE_PROCgen` constant and the guard in `_generate_dungeon` as the documented extension hook, but reduce the online branch to a single `push_error("online procgen not implemented")` so nothing pretends to work. Closes RFL-09, RFL-10.

## Data and schema changes

No `content/` schema is required by steps 1-8; the results dictionary is runtime-only.

**Save format.** Step 6 removes the transient `activeRun.playerDead = true` write but the key must still be tolerated on load, because saves written by the current build can contain it. Bump `save_migrator.gd` `CURRENT_VERSION` from `4` to `5` and add:

```gdscript
static func _migrate_v4_to_v5(data: Dictionary) -> Dictionary:
    var copy: Dictionary = data.duplicate(true)
    copy["schemaVersion"] = 5
    var active: Variant = copy.get("activeRun", {})
    if active is Dictionary and not active.is_empty():
        var run: Dictionary = active
        # A v4 save could be quarantined mid-respawn with playerDead still true
        # while lastCheckpoint is valid; prefer the checkpoint over discarding the run.
        if bool(run.get("playerDead", false)):
            var checkpoint: Variant = run.get("lastCheckpoint", {})
            if checkpoint is Dictionary and not checkpoint.is_empty():
                run["snapshot"] = (checkpoint as Dictionary).duplicate(true)
                run.erase("playerDead")
            else:
                copy.erase("activeRun")
        if run.has("floorDefinitions"):
            run.erase("floorDefinitions")
        run["schemaVersion"] = 5
        if copy.has("activeRun"):
            copy["activeRun"] = run
    return copy
```

Register it in `migrate()` after the v3→v4 step, and update `local_save.gd:11` implicitly through `SaveMigrator.CURRENT_VERSION`. Document the step in `docs/SAVE_MIGRATIONS.md` (named by `save_migrator.gd:7` `MIGRATION_DOC`).

**Failure behaviour.** A v5 save whose `activeRun` fails the checkpoint recovery above loses only the active run, never the character: `copy.erase("activeRun")` leaves `character`, `inventory`, `talents`, and `flags` intact, so `_validate_save` still passes and the player returns to the hub with their permanent progress.

## Acceptance criteria
- [x] Dying with an active `escape_castle` quest leaves it `active` and grants no gold; escaping completes it exactly once. (RFL-01)
- [x] Forcing `LocalProcgen.generate` to fail during `ascend_floor` leaves the player on the original floor with the original geometry loaded and shows a `run_warning` toast. (RFL-02)
- [x] `complete_waves_run` results report `levels_gained` equal to `grant_xp(...).levels_gained`, and `on_waves_failed` results contain `run_relics_lost`. (RFL-03)
- [x] After transitioning 1→2→…→10 in castle mode, `floor_definitions` contains floors 9, 10, and one neighbour — never floor 1. (RFL-04)
- [x] Dying at a bonfire checkpoint shows an in-scene outcome overlay stating XP granted, XP deferred to the shard, and the item ids stripped. (RFL-05)
- [x] `activeRun` is written exactly once during `_bonfire_death_respawn`, and `playerDead` never appears in a save written by that path. (RFL-06)
- [x] A refused run start (locked dungeon, locked tier, generation failure) updates the hub message within the same frame via `run_warning`. (RFL-07)
- [x] `run_results.cloud_synced` is `false` and the results screen reads "saved locally (offline)" when `ApiConfig.access_token` is empty. (RFL-08)
- [x] After returning to the hub, `get_tree().root.has_meta("floor_transition")` and `has_meta("run_results")` are both false. (RFL-09)
- [x] `run_flow.gd` contains no function without a call site. (RFL-10)
- [x] All seven outcomes produce dictionaries with an identical key set. (RFL-03, RFL-11)

## Validation
Extend `apps/game/client/scripts/validation/suites/flow_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `flow.results.key_parity` | Builds all seven outcomes through `RunLifecycle.build_results` and asserts identical `keys()` sets |
| `flow.results.waves_levels_honest` | Grants enough XP to cross a level boundary, completes waves, asserts `levels_gained >= 1` |
| `flow.results.loot_lost_diff` | Registers two loot ids, resolves a death, asserts `loot_lost` equals the ids actually absent from `InventoryService.inventory` |
| `flow.transition.generation_failure_restores` | Stubs `_resolve_floor_definition` to return `{}`, calls `ascend_floor`, asserts `current_floor` and `current_dungeon_definition` are unchanged and `run_warning` was emitted |
| `flow.cache.evicts_farthest` | Populates floors 1-4 with `MAX_CACHED_FLOORS = 3` at `current_floor = 4`, asserts key `1` was evicted and key `3` survives |
| `flow.meta.cleared_on_return` | Calls `return_to_hub`, asserts none of `RUN_META_KEYS` remain on the root |

Extend `apps/game/client/scripts/validation/suites/hub_m4_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `hub_m4.quest.escape_not_completed_on_death` | Accepts `escape_castle`, records gold, emits a death outcome, asserts state is still `active` and gold is unchanged |
| `hub_m4.quest.escape_completed_on_escape` | Same setup, calls `register_run_outcome(OUTCOME_ESCAPED, ...)`, asserts state `completed` and gold `+50` |

Extend `apps/game/client/scripts/validation/suites/save_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `save.migrate.v4_to_v5_playerdead_recovered` | v4 save with `playerDead: true` and a valid `lastCheckpoint` migrates to v5 with `activeRun.snapshot` equal to the checkpoint and no `playerDead` |
| `save.migrate.v4_to_v5_playerdead_no_checkpoint` | v4 save with `playerDead: true` and empty `lastCheckpoint` migrates to v5 with `activeRun` absent and `character` / `inventory` preserved |

## Related
- Existing state: [`../existing_codebase/run-flow.md`](../existing_codebase/run-flow.md)
- [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`dialogue-quests.md`](dialogue-quests.md), [`progression-service.md`](progression-service.md), [`world-state.md`](world-state.md)
- Owned elsewhere: [`castle-run.md`](castle-run.md), [`waves-run.md`](waves-run.md), [`ui/run_outcome.md`](ui/run_outcome.md)
