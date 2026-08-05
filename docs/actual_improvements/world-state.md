# World state — improvement plan

## Current state
`WorldState` (`apps/game/client/scripts/app/world_state.gd`, 52 lines) is an untyped, unnamespaced string→Variant dictionary that dungeon interactables use for locks, levers, and room content. See [`../existing_codebase/world-state.md`](../existing_codebase/world-state.md). It works, and its snapshot round-trip through `activeRun.snapshot.worldFlags` is real. The problems are correctness at the edges: `has_flag` cannot distinguish an unset flag from one set to `0`, `all_flags()` is a shallow copy so container values alias live state into the save blob, flags are not cleared when the player retreats to the hub, and the `flag_changed` signal has no subscriber so nothing can react to world changes without polling.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| WST-01 | P0 | `all_flags()` is a shallow `duplicate()`, so a Dictionary- or Array-valued flag is written into `activeRun.snapshot.worldFlags` by reference; post-capture mutation silently rewrites the saved snapshot | `world_state.gd:33-34`, consumed at `castle_run.gd:435` |
| WST-02 | P1 | `has_flag` returns `bool(...)`, so `set_flag(id, 0)` and `set_flag(id, "")` read as absent; callers cannot store counters or ids and then test presence | `world_state.gd:25-26` |
| WST-03 | P1 | `returned_to_hub` is not connected, so flags survive `retreat_to_hub` and `abandon_active_run` into the hub scene and leak into the next run if it is a continue | `world_state.gd:10-13`, `run_flow.gd:491-509`, `run_flow.gd:344-352` |
| WST-04 | P1 | `flag_changed` is emitted but has no connection anywhere under `apps/game/client/scripts/`; every consumer polls `has_flag` in `_process` instead | `world_state.gd:5`, `world_state.gd:22` |
| WST-05 | P1 | No flag id registry: ids are free-form strings, so a typo in a read silently returns the default forever and no tool can list what the dungeon actually tracks | no constant list exists in `world_state.gd` |
| WST-06 | P2 | `restore_flags` accepts any dictionary without validating key types or value types, so a corrupted snapshot injects arbitrary state | `world_state.gd:37-40` |
| WST-07 | P2 | No `erase_flag`; the only way to unset is `set_flag(id, false)`, which leaves the key present in `all_flags()` and grows the snapshot for the whole run | `world_state.gd:16-40` |

## Target design

### Namespaced, registered flag ids
Flags become a documented, greppable surface. Add a registry script `apps/game/client/scripts/app/world_flags.gd`:

```gdscript
class_name WorldFlags
extends RefCounted

## Canonical run-flag id builders. Every WorldState key must come from here.

const NS_LOCK := "lock"
const NS_LEVER := "lever"
const NS_DOOR := "door"
const NS_ROOM := "room"
const NS_SECRET := "secret"
const NS_CHEST := "chest"
const NS_TRAP := "trap"

const NAMESPACES: Array[String] = [
    NS_LOCK, NS_LEVER, NS_DOOR, NS_ROOM, NS_SECRET, NS_CHEST, NS_TRAP,
]

static func lock_opened(lock_id: String) -> String:
    return "%s.%s.opened" % [NS_LOCK, lock_id]

static func lever_pulled(lever_id: String) -> String:
    return "%s.%s.pulled" % [NS_LEVER, lever_id]

static func room_cleared(room_id: String) -> String:
    return "%s.%s.cleared" % [NS_ROOM, room_id]

static func chest_opened(instance_id: String) -> String:
    return "%s.%s.opened" % [NS_CHEST, instance_id]

static func is_valid_id(flag_id: String) -> bool:
    var parts := flag_id.split(".")
    return parts.size() == 3 and parts[0] in NAMESPACES and parts[1] != ""
```

`WorldState.set_flag` rejects ids that fail `WorldFlags.is_valid_id` with a `push_error` in debug builds and a `push_warning` in release, and does not store them. This makes a typo loud instead of silent.

Chosen over an enum: the ids are parameterised by runtime room and lock ids from the dungeon definition, so a closed enum cannot express them. A validated three-segment convention gives the same greppability without losing dynamism.

### Presence versus truthiness
Split the two questions:

```gdscript
func has_flag(flag_id: String) -> bool      # key exists at all
func is_flag_true(flag_id: String) -> bool  # key exists and is truthy
func get_flag(flag_id: String, default_value: Variant = null) -> Variant
func erase_flag(flag_id: String) -> bool
```

`has_flag` becomes `_flags.has(flag_id)`. Every existing call site that means "did this happen" migrates to `is_flag_true`. `get_flag` defaults to `null` rather than `false` so a caller can tell "absent" from "stored false".

### Deep capture and validated restore
```gdscript
func all_flags() -> Dictionary:
    return _flags.duplicate(true)

func restore_flags(flags: Dictionary) -> int:
    _flags.clear()
    var rejected := 0
    for flag_id in flags:
        var key := str(flag_id)
        if not WorldFlags.is_valid_id(key):
            rejected += 1
            continue
        _flags[key] = _sanitize_value(flags[flag_id])
    if rejected > 0:
        push_warning("WorldState: dropped %d invalid flag(s) from snapshot" % rejected)
    return rejected
```

`_sanitize_value` accepts `bool`, `int`, `float`, `String`, and one level of `Array`/`Dictionary` whose leaves are those scalars; anything else is dropped. A corrupt snapshot therefore degrades to "some doors are shut again" rather than injecting arbitrary objects, and `restore_flags` returning the rejection count lets `castle_run.gd` surface a warning.

### Reactive consumers
`flag_changed(flag_id, value)` gains a companion so subscribers can filter cheaply without string parsing:

```gdscript
signal flag_changed(flag_id: String, value: Variant)
signal namespace_changed(namespace: String, flag_id: String, value: Variant)
```

`erase_flag` emits `flag_changed(flag_id, null)`. Door, lever, and chest scripts subscribe to `namespace_changed` in `_ready` and drop their `_process` polling.

### Lifecycle
Connect `returned_to_hub` alongside the existing two signals and reset there as well. `_on_run_started` keeps the `is_continue_restore()` guard, because a continue restores flags from the snapshot immediately afterwards.

## Work plan

1. **Add `world_flags.gd` with the namespace constants, builders, and `is_valid_id`** — new file `apps/game/client/scripts/app/world_flags.gd`. No behaviour change; game runnable.
2. **Migrate every `WorldState.set_flag` / `get_flag` / `has_flag` call site to the builders** — dungeon interactable scripts under `apps/game/client/scripts/dungeon/`. Purely mechanical id replacement, no `WorldState` change yet. Closes the data half of WST-05.
3. **Add validation, `is_flag_true`, `erase_flag`, and presence-based `has_flag`** — `world_state.gd`: reject invalid ids in `set_flag`, add the two new methods, change `has_flag` to `_flags.has`, change `get_flag`'s default to `null`. Update the call sites migrated in step 2 to use `is_flag_true` where they mean truthiness. Closes WST-02, WST-05, WST-07.
4. **Deep-copy capture and sanitised restore** — `world_state.gd`: `all_flags()` uses `duplicate(true)`, `restore_flags` validates and returns a rejection count, add `_sanitize_value`. `castle_run.gd:315` logs the rejection count. Closes WST-01, WST-06.
5. **Connect `returned_to_hub`** — `world_state.gd:10-13`. Closes WST-03.
6. **Add `namespace_changed` and convert polling consumers** — `world_state.gd` emits it from `set_flag` and `erase_flag`; door / lever / chest / trap scripts subscribe and delete their `_process` polls. Closes WST-04.

## Data and schema changes

No file under `content/` changes: world flags are runtime-only and never authored.

**Save format.** Step 2 renames every flag id, so a v4 `activeRun.snapshot.worldFlags` written by the current build contains legacy unnamespaced keys that step 3 and step 4 will reject. Bump `save_migrator.gd` `CURRENT_VERSION` to `5` (shared with the bump described in [`run-flow.md`](run-flow.md); if both land, they are one version step, not two) and rewrite the keys inside `_migrate_v4_to_v5`:

```gdscript
const LEGACY_WORLD_FLAG_MAP := {
    # legacy id -> namespaced builder output, one entry per id observed in the
    # pre-migration codebase. Unknown legacy keys are dropped, not guessed.
}

static func _migrate_world_flags(snapshot: Dictionary) -> void:
    var legacy: Variant = snapshot.get("worldFlags", {})
    if not legacy is Dictionary:
        snapshot["worldFlags"] = {}
        return
    var migrated: Dictionary = {}
    for key in legacy:
        var mapped: String = str(LEGACY_WORLD_FLAG_MAP.get(str(key), ""))
        if mapped != "":
            migrated[mapped] = legacy[key]
    snapshot["worldFlags"] = migrated
```

Apply it to both `activeRun.snapshot` and `activeRun.lastCheckpoint`. Dropping an unmapped key re-locks a door the player had opened; that is the honest failure mode and is strictly better than leaving an id that no reader will ever match.

**Failure behaviour.** `restore_flags` never aborts a run. A snapshot with zero valid flags produces a fully re-locked but completable floor, and `castle_run.gd` emits one `push_warning` naming the rejection count.

## Acceptance criteria
- [ ] `set_flag("room.r1.cleared", {"enemies": []})`, then mutating the passed dictionary, leaves `all_flags()["room.r1.cleared"]["enemies"]` unchanged. (WST-01)
- [ ] `set_flag("chest.c1.opened", 0)` then `has_flag("chest.c1.opened")` is `true` and `is_flag_true("chest.c1.opened")` is `false`. (WST-02)
- [ ] After `RunFlow.retreat_to_hub()`, `WorldState.all_flags()` is empty. (WST-03)
- [ ] No dungeon interactable script calls `WorldState.has_flag` or `is_flag_true` from `_process`. (WST-04)
- [ ] `set_flag("someTypo", true)` stores nothing and pushes an error in a debug build. (WST-05)
- [ ] `restore_flags({"lock.a.opened": true, "garbage": Callable()})` stores one flag, returns `1`, and does not crash. (WST-06)
- [ ] `erase_flag("lock.a.opened")` removes the key from `all_flags()` and emits `flag_changed("lock.a.opened", null)`. (WST-07)

## Validation
Add `apps/game/client/scripts/validation/suites/world_state_suite.gd` and register it in `SUITE_PATHS` in `apps/game/client/scripts/validation/validation_runner.gd`:

| Assertion id | Checks |
|--------------|--------|
| `world_state.id.rejects_unnamespaced` | `set_flag("foo", true)` leaves `all_flags()` empty |
| `world_state.id.accepts_builder_output` | `WorldFlags.lock_opened("gate_a")` is accepted and readable |
| `world_state.copy.deep` | Nested container mutation after `all_flags()` does not alter the copy |
| `world_state.presence.vs_truthiness` | `has_flag` / `is_flag_true` disagree for a `0` value |
| `world_state.erase.emits_null` | `erase_flag` removes the key and emits `flag_changed(id, null)` |
| `world_state.restore.rejects_invalid` | Mixed valid/invalid dictionary yields the correct rejection count and only valid keys |
| `world_state.lifecycle.cleared_on_return_to_hub` | Emitting `returned_to_hub` empties `_flags` |

Extend `apps/game/client/scripts/validation/suites/save_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `save.migrate.world_flags_namespaced` | A v4 snapshot with legacy ids migrates to namespaced ids for every entry in `LEGACY_WORLD_FLAG_MAP` and drops the rest |

Extend `apps/game/client/scripts/validation/suites/room_content_suite.gd` with `room_content.world_flags.registry_only`, asserting that every `WorldState` key produced by a full room-content build pass satisfies `WorldFlags.is_valid_id`.

## Related
- Existing state: [`../existing_codebase/world-state.md`](../existing_codebase/world-state.md)
- [`run-flow.md`](run-flow.md), [`save-migrator.md`](save-migrator.md), [`local-save.md`](local-save.md), [`inventory-service.md`](inventory-service.md)
- Owned elsewhere: [`castle-run.md`](castle-run.md), [`stair-lever.md`](stair-lever.md), [`dungeon-traps.md`](dungeon-traps.md), [`room-content.md`](room-content.md)
