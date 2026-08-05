# Stair lever and floor menu — improvement plan

## Current state

The lever works in the happy path: it is created in every `_stairs` room, unlocks when the floor boss dies, and its menu calls into `RunFlow` to change floors. Around that core, three things are broken and several are missing. The stair-room arrival spawn never executes because the snapshot meta is consumed one line earlier, so every floor transition drops the player at the start room. Only the last of several levers is retained and unlocked, so a floor with two `_stairs` rooms can present a permanently dead lever. Nine of ten themes have no `LeverSpawn` marker, so the lever is positioned by a hardcoded west-wall guess. The menu does not pause the run, cannot be driven by a gamepad, and reads the lever's private fields. See [`../existing_codebase/stair-lever.md`](../existing_codebase/stair-lever.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| STL-01 | P0 | `_restore_saved_snapshot` removes the `run_snapshot` meta before `_apply_floor_transition_spawn` reads it, so the player never spawns at the stairs after a floor change | `castle_run.gd:47-48`, `:311`, `:286-287` |
| STL-02 | P0 | `_stair_lever` holds only the last created lever; every other `_stairs` room gets a lever that is never configured with retreat and never unlocked | `dungeon_builder.gd:45,651,671-677` |
| STL-03 | P1 | Nine of ten themes have no `SpawnPoints/LeverSpawn`, so the lever is placed by a hardcoded west-wall offset derived from the blockout size | `dungeon_builder.gd:654-668`; marker only in `castle_stairs.tscn:44` |
| STL-04 | P1 | `StairMenu` does not pause the tree, so enemies keep attacking while the modal is open with a freed cursor | `stair_menu.gd:16`, no `get_tree().paused` |
| STL-05 | P1 | No button receives focus and no focus neighbors are set, so the menu is unusable on a gamepad | `stair_menu.gd:81-85` |
| STL-06 | P1 | The modifier-key fallback is dead in `CastleRun`, is keyboard-only, and its `SHIFT` descend branch is gated on `_can_ascend` | `stair_lever.gd:53-66`, `castle_run.gd:113-114` |
| STL-07 | P1 | The prompt is a generic "Floor options" with no target floor, no direction, and no locked-state explanation | `stair_lever.gd:94-101` |
| STL-08 | P2 | `StairMenu` reads the lever's private fields and calls its private `_use_lever` by name | `stair_menu.gd:72-77,89-90` |
| STL-09 | P2 | The lever has no animation, audio, or VFX for pull, unlock, or transition | no `AudioDirector` / `VfxService` reference in either file |
| STL-10 | P2 | `find_stairs_room_id` matches `_stairs` templates **or** `corridor` rooms and falls back to the literal `"stairs"`, a different rule from the builder's lever rule | `run_floor_config.gd:47-53` vs `dungeon_builder.gd:615` |
| STL-11 | P2 | `stairs_spawn_facing_y` dereferences its room argument with no null guard, and `m7_suite` calls it with `null` | `run_floor_config.gd:58`, `m7_suite.gd:343` |
| STL-12 | P2 | `lever_used` has no listeners; the lever's own signal is unused telemetry | `stair_lever.gd:7,72` |
| STL-13 | P2 | The lever is built node-by-node in `DungeonBuilder` rather than instantiated from a scene | `dungeon_builder.gd:620-651` |
| STL-14 | P2 | The suites only assert the script loads and that its source text contains a substring | `m7_suite.gd:330-349,903` |
| STL-15 | P2 | The lever's `_unhandled_input` stays live while the menu is open, so a second press re-enters `open_for_lever` | `stair_lever.gd:45-52`, `stair_menu.gd:25-31` |
| STL-16 | P2 | `close_menu` unconditionally re-captures the mouse regardless of what else is open | `stair_menu.gd:38` |

## Target design

The lever becomes an authored scene registered per stair room, and the menu becomes a proper `MenuShell` screen with the same pause and focus behavior as the pause menu.

### 1. Fix arrival (STL-01)

`_restore_saved_snapshot` currently owns the meta lifetime. Read the snapshot once in `CastleRun._ready`, keep it in a local, and pass it to both consumers:

```gdscript
var snapshot := _take_run_snapshot_meta()   # reads and removes once
_restore_saved_snapshot(snapshot)
_apply_floor_transition_spawn(snapshot)
```

`_apply_floor_transition_spawn` keeps its `floorTransition` guard and its call into `DungeonBuilder.get_stair_spawn_global`. Because `_ensure_safe_player_spawn` is deferred (`castle_run.gd:50`), the arrival position must be inside the stair room's navmesh or the safety pass will teleport the player away again; the acceptance criteria below assert both.

### 2. One lever per stair room, all of them live (STL-02)

Replace the single field with a dictionary keyed by room id:

```gdscript
var _stair_levers: Dictionary = {}   # room_id -> Node3D
```

`_unlock_stair_lever()` becomes `_unlock_stair_levers()` and iterates. `get_stair_lever()` keeps its signature and returns the lever in the room chosen by `find_stairs_room_id` so existing suite code still works, and a new `get_stair_levers()` returns the dictionary.

Better still, stop generating multiple stair rooms: the room graph should mark exactly one `stairs` slot per floor (see [`room-graph-procgen.md`](room-graph-procgen.md) RGP-05), and the builder should `push_error` when it finds a second one. Both halves land together — the dictionary makes the current data safe, the graph fix makes the data correct.

### 3. Authored lever scene and marker in every stair room (STL-03, STL-13, STL-09)

New `apps/game/client/scenes/dungeon/stair_lever.tscn`:

```
StairLever (Node3D, stair_lever.gd)
  Visual (Node3D)                 <- authored bracket + handle, biome material slot
    Handle (Node3D)               <- rotated by the pull animation
  InteractArea (Area3D, mask 2)
  Label3D
  AnimationPlayer                 <- "locked_idle", "unlock", "pull"
  AudioStreamPlayer3D
```

`DungeonBuilder` instantiates it and positions it from `SpawnPoints/LeverSpawn`, which becomes mandatory in every `<theme>_stairs.tscn` under [`room-templates.md`](room-templates.md) RTP-07. A missing marker is a `push_error`, not a guess — the current guess is what puts levers inside walls in the nine clone themes.

Animation and cues: `locked_idle` (a chained, dim handle), `unlock` plus an `AudioDirector` cue when the boss dies, `pull` plus a cue on use, and a `VfxService` burst at the ramp when the floor transition starts.

### 4. Menu as a real screen (STL-04, STL-05, STL-08, STL-15, STL-16)

`StairMenu` moves onto the shared menu shell used by the pause menu ([`ui/menu_shell.md`](ui/menu_shell.md)):

- `open_for_lever(lever)` sets `get_tree().paused = true` and restores the previous pause state on close, rather than assuming the game was unpaused.
- Mouse mode is saved on open and restored on close instead of being forced to `MOUSE_MODE_CAPTURED` (STL-16).
- Buttons are created through `GameUISkinScript.make_menu_button` and the first is given `grab_focus()`, with `focus_neighbor_top` / `focus_neighbor_bottom` wired into a ring (STL-05).
- The lever passes its state explicitly: `open_for_lever(lever, options: Array[Dictionary])` where each option is `{ id, label, enabled, reason }`. The menu never reads private fields (STL-08).
- The lever sets `_menu_open` while the menu is up and ignores `interact` until `closed` fires (STL-15).

Option rows carry a `reason` so a disabled row can say why: "Descend - floor 1 is the lowest", "Retreat - defeat the boss first". This is where STL-07's missing information lands.

The public API becomes:

```gdscript
# stair_lever.gd
func floor_options() -> Array[Dictionary]:
    return [
        { "id": "ascend",  "label": "Ascend to floor %d" % (floor + 1), "enabled": _can_ascend,  "reason": _ascend_reason() },
        { "id": "descend", "label": "Descend to floor %d" % (floor - 1), "enabled": _can_descend, "reason": _descend_reason() },
        { "id": "retreat", "label": "Retreat to the hub",                "enabled": _can_retreat, "reason": _retreat_reason() },
    ]

func use(direction: String) -> void:   # public, replaces the private _use_lever call
```

### 5. Prompt content (STL-07)

Three prompt states, all through `InputGlyphService`:

| State | Text |
|-------|------|
| locked | "Sealed - defeat the floor boss" |
| unlocked, near | "<glyph> Stairs - floor N" |
| menu open | hidden |

The lever needs the current floor, so `configure` gains a `floor_index` parameter supplied from `RunFlow.get_current_floor()`.

### 6. Consistency and cleanup (STL-06, STL-10, STL-11, STL-12)

- Delete the modifier-key fallback entirely (STL-06). The menu is always present in `CastleRun`; a keyboard-only hidden binding with an inverted flag test is worse than no fallback. If a headless path needs it, expose `use(direction)` and call it directly.
- `find_stairs_room_id` uses one rule — `templateId.ends_with("_stairs")` — and returns `""` when there is none, with callers handling the empty case (STL-10). The `corridor` clause exists only because the assigner fills corridor slots with stairs templates; that is fixed in [`room-graph-procgen.md`](room-graph-procgen.md).
- `stairs_spawn_facing_y` returns `0.0` for a null room and drops the dead `ascending` argument, since all stair scenes have a south socket (STL-11).
- `lever_used` is either consumed by the analytics hook in [`achievements-meta.md`](achievements-meta.md) or removed (STL-12).

## Work plan

1. **Snapshot meta lifetime** — read once, pass to both consumers; assert arrival at the stairs (STL-01).
2. **Lever dictionary** — `_stair_levers`, unlock all, `push_error` on a second stairs room (STL-02).
3. **Menu on the shell** — pause, focus ring, mouse-mode save/restore, `closed` re-enables the lever (STL-04, STL-05, STL-15, STL-16).
4. **Explicit options API** — `floor_options()`, `use(direction)`, per-row `reason`; menu stops touching private fields (STL-08, STL-07).
5. **Delete the modifier path** (STL-06).
6. **Authored scene** — `stair_lever.tscn`, mandatory `LeverSpawn`, builder instantiates (STL-03, STL-13). Land with [`room-templates.md`](room-templates.md) RTP-07.
7. **Animation, audio, VFX** — three animations, three cues, one transition burst (STL-09).
8. **Helper cleanup** — `find_stairs_room_id`, `stairs_spawn_facing_y`, `lever_used` (STL-10, STL-11, STL-12).
9. **Suite rewrite** (STL-14).

## Data and schema changes

- New scene `apps/game/client/scenes/dungeon/stair_lever.tscn`.
- Every `apps/game/client/scenes/rooms/<theme>/<theme>_stairs.tscn` gains `SpawnPoints/LeverSpawn` and `SpawnPoints/PlayerSpawn` positioned at the top of the ramp (10 scenes; tracked under [`room-templates.md`](room-templates.md) RTP-07).
- `content/schemas/biome-definition.v2.json` (new in [`biome-registry.md`](biome-registry.md)) gains `audioCues.lever_pull`, `audioCues.lever_unlock`.
- No change to `content/schemas/dungeon-definition.v1.json` — the lever is derived from `templateId`, not declared in the definition. If the graph work adds an explicit `stairsRoomId` field, `find_stairs_room_id` reads it and the suffix rule becomes the fallback.
- Save format: no change. The lever's unlocked state is already derived from the snapshot's `bossDefeated` (`dungeon_builder.gd:856`).

## Determinism

Floor transitions must be reproducible: the same run seed and the same floor index must produce the same floor, and ascending then descending must return the player to the identical layout. Today that holds through the definition cache (`_stash_current_floor_in_cache` / `_get_cached_floor_definition`, `run_flow.gd:531,550`) plus `RunFloorConfig.mix_seed`. Two requirements follow:

- The cache must be authoritative for a revisited floor — regeneration must never be reached for a floor already visited in this run.
- With the cache disabled, `mix_seed(seed, n)` must still regenerate a byte-identical definition. The additive mix at `run_floor_config.gd:17` correlates adjacent floors and is replaced by a hashed mix in [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) DCT-05; the assertion below is written against whichever mix is current.

## Acceptance criteria

- [ ] After `ascend_floor()`, the player's position is inside the new floor's stair room and remains there after the deferred safety pass (STL-01).
- [ ] A definition with two `_stairs` rooms produces two levers, both unlocked on boss defeat (STL-02).
- [ ] All 10 `<theme>_stairs.tscn` scenes contain `SpawnPoints/LeverSpawn`, and `_place_stair_lever_on_wall` contains no fallback offset (STL-03).
- [ ] `get_tree().paused` is true while the menu is open and returns to its previous value on close (STL-04).
- [ ] Opening the menu focuses the first enabled button; up and down move focus in a ring (STL-05).
- [ ] `stair_lever.gd` contains no `Input.is_key_pressed` call (STL-06).
- [ ] The unlocked prompt names the current floor; the locked prompt names the boss requirement (STL-07).
- [ ] `stair_menu.gd` contains no `_lever.get(` and no `_lever.call("_use_lever"` (STL-08).
- [ ] Pulling the lever plays the `pull` animation and exactly one audio cue before the scene change (STL-09).
- [ ] `find_stairs_room_id` returns `""` for a definition with no stairs room, and the builder and helper agree on the id for all 10 biomes (STL-10).
- [ ] `stairs_spawn_facing_y(null)` returns `0.0` without an error (STL-11).

## Validation

Extend `apps/game/client/scripts/validation/suites/m7_suite.gd`, replacing `_test_stair_lever_script` at `:330-349`:

- `test_lever_created_per_stairs_room` — for all 10 biomes, build a floor and assert one lever per `_stairs` room, each parented under that room's `Props`.
- `test_lever_inside_room` — assert each lever's global position is inside its room's AABB, at least 0.3 m from any wall plane, and reachable from the room's `PlayerSpawn` on the navmesh.
- `test_lever_starts_locked` — assert `is_unlocked() == false` and that a simulated `interact` neither opens the menu nor calls `RunFlow.ascend_floor`.
- `test_lever_unlocks_on_boss_death` — emit boss defeat, assert every lever on the floor reports `is_unlocked()`.
- `test_lever_flags_by_mode` — table-drive `(run_mode, floor, is_final)` and assert `floor_options()` enablement: castle floor 1 (ascend only, retreat once unlocked), castle floor 10 (descend only), endless floor 1 (ascend only, no descend).
- `test_transition_spawn_at_stairs` — call `ascend_floor()`, await the reload, assert the player is inside the new floor's stair room and that `player_room_id` equals the stairs room id (STL-01).
- `test_round_trip_layout_identical` — ascend then descend, assert the returned floor's definition hashes equal the original's (determinism).
- `test_regenerate_same_seed` — with the floor cache cleared, regenerate floor N from the same run seed and assert a byte-identical canonical JSON.
- `test_facing_helper_null_safe` — `stairs_spawn_facing_y(null)` returns `0.0` (STL-11).
- Delete the source-text assertion at `:903`; `test_lever_flags_by_mode` covers retreat behaviorally (STL-14).

Extend `apps/game/client/scripts/validation/suites/menu_shell_suite.gd` (or the pause-menu suite, whichever owns modal behavior):

- `test_stair_menu_pauses` — open, assert `get_tree().paused`; close, assert the previous value is restored (STL-04).
- `test_stair_menu_focus` — assert the first enabled button owns focus after `open_for_lever` and that `ui_down` moves it (STL-05).
- `test_stair_menu_disabled_reasons` — with `can_descend == false`, assert the descend row is present, disabled, and its `reason` string is non-empty (STL-07).

Manual checklist: pull the lever in all 10 biomes and confirm the handle animation reads under the fixed diorama camera, that the lever is never behind the stair ramp, and that the menu can be completed on a gamepad without touching the mouse.

## Related

- [`../existing_codebase/stair-lever.md`](../existing_codebase/stair-lever.md)
- [`dungeon-builder.md`](dungeon-builder.md) — DBL rows for lever creation and placement
- [`room-templates.md`](room-templates.md) — RTP-07 `LeverSpawn`, `PlayerSpawn`, `Props` in every scene
- [`room-graph-procgen.md`](room-graph-procgen.md) — exactly one stairs slot per floor
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) — DCT-05 hashed floor seeds, floor limits
- [`boss-door-exit-portal.md`](boss-door-exit-portal.md) — the final-floor exit
- [`run-flow.md`](run-flow.md) — `ascend_floor`, `descend_floor`, `retreat_to_hub`
- [`castle-run.md`](castle-run.md) — snapshot meta lifetime, `StairMenu` instantiation
- [`ui/menu_shell.md`](ui/menu_shell.md), [`ui/menu_shell_a11y.md`](ui/menu_shell_a11y.md) — the shell and focus rules
- [`ui/input_glyphs.md`](ui/input_glyphs.md) — prompt glyphs
- [`audio-director.md`](audio-director.md), [`vfx-service.md`](vfx-service.md) — cues
