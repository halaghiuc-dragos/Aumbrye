# Stair lever and floor menu

The stair lever is the interactable that moves the player between floors of a multi-floor run. `DungeonBuilder` instantiates `stair_lever.tscn` in every room whose `templateId` ends with `_stairs`, starts locked, and unlocks when the floor's boss dies. Interacting opens `StairMenu`, a `MenuShell` modal that pauses the run and offers ascend, descend, and retreat-to-hub through the lever's public `floor_options()` / `use()` API.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scenes/dungeon/stair_lever.tscn` | Authored lever scene: interact area, label, handle pivot, `AnimationPlayer`, `AudioStreamPlayer3D` |
| `apps/game/client/scripts/dungeon/stair_lever.gd` | `Node3D` interactable: lock state, prompts, animations, `floor_options()`, `use()` |
| `apps/game/client/scripts/ui/stair_menu.gd` | Modal `Control` built from `MenuShell`; pause and focus restore |
| `apps/game/client/scripts/dungeon/dungeon_builder.gd` | Instantiates and places levers; `_stair_levers` dictionary |
| `apps/game/client/scripts/dungeon/castle_run.gd` | Snapshot meta lifetime; `StairMenu` instantiation |
| `apps/game/client/scripts/dungeon/run_floor_config.gd` | `find_stairs_room_id`, `stairs_spawn_facing_y` |

## How it works

### Creation

`DungeonBuilder._setup_stair_levers()` (`dungeon_builder.gd:790-804`, called from `build_from_definition` at `:139`) walks every built room whose `templateId` ends with `_stairs` (via `RunFloorConfig.is_stairs_room`). `_create_stair_lever(room, room_id)` (`:807-825`) instantiates `STAIR_LEVER_SCENE`, parents under `Props`, and places from `SpawnPoints/LeverSpawn`. A missing marker is `push_error` and the lever is freed â€” there is no west-wall guess (`:836-847`). More than one stairs room logs `push_error` but still creates a lever per room (`:798-802`).

`_stair_levers: Dictionary` maps `room_id â†’ Node3D` (`:54`). `get_stair_lever()` returns the lever in the room chosen by `find_stairs_room_id(definition)` (`:822-825`). `get_stair_levers()` returns all values as an `Array[Node3D]` (`:828-833`).

### Direction flags

`configure(can_ascend, can_descend, can_retreat, floor_index)` (`stair_lever.gd:29-36`) sets direction flags and the current floor index used in prompts and option labels.

| Flag | Expression | Site |
|------|-----------|------|
| `can_ascend` | `not RunFlow.is_final_floor() or RunFlow.get_run_mode() == "endless"` | `dungeon_builder.gd:819` |
| `can_descend` | `floor_index > 1 and RunFlow.get_run_mode() != "endless"` | `:820` |
| `can_retreat` | `RunFlow.get_run_mode() in ["endless", "castle"]` | `:821` |

### Lock and unlock

`_unlocked` starts false (`stair_lever.gd:13`). `unlock()` plays the `unlock` animation and `lever_unlock` SFX (`:63-67`). `DungeonBuilder._unlock_stair_lever()` (`dungeon_builder.gd:850-858`) re-configures and unlocks every entry in `_stair_levers`. Called from `_on_boss_defeated()` on non-final floors (`:784-786`) and `apply_snapshot()` when `bossDefeated` (`:1065`).

### Interaction

`_unhandled_input` (`stair_lever.gd:115-120`) requires `interact`, proximity, unlock, and `not _menu_open`, then calls `StairMenu.open_for_lever(self, floor_options())`. There is no modifier-key fallback.

`use(direction)` (`:100-113`) plays `pull` animation, `lever_pull` SFX, a `VfxService.play_hit_spark` burst, emits `lever_used`, and calls `RunFlow.ascend_floor()`, `descend_floor()`, or `retreat_to_hub()`.

Prompts (`_update_label`, `:139-154`):

| State | Text |
|-------|------|
| locked, near | `"Sealed â€” defeat the floor boss"` |
| unlocked, near | `"<glyph> Stairs â€” floor N"` |
| menu open | hidden |

### StairMenu

`open_for_lever(lever, options)` (`stair_menu.gd:25-41`) saves pause state and mouse mode, sets `get_tree().paused = true`, calls `lever.set_menu_open(true)`, and rebuilds `MenuShell` buttons from the options array. Each row carries `id`, `label`, `enabled`, and `reason`; disabled rows append the reason in parentheses (`:67-96`). Focus neighbors form a ring (`:99-106`); the first enabled button receives `grab_focus()` (`:109-116`).

`close_menu` (`:44-57`) restores the saved pause state and mouse mode, clears `_menu_open` on the lever, and emits `closed`.

### Floor transition and arrival

`CastleRun._ready` reads the snapshot once via `_take_run_snapshot_meta()` (`castle_run.gd:46-48`, `:294-301`), passes it to `_restore_saved_snapshot(snapshot)` (`:323-325`) and `_apply_floor_transition_spawn(snapshot)` (`:304-309`). `_place_at_stair_from_snapshot` uses `RunFloorConfig.find_stairs_room_id` and `DungeonBuilder.get_stair_spawn_global` (`:311-321`).

`RunFloorConfig.find_stairs_room_id(definition)` (`run_floor_config.gd:52-56`) returns the first room whose `templateId` ends with `_stairs`, or `""` when none. `stairs_spawn_facing_y(stair_room, ascending)` (`:59-67`) returns `0.0` for a null room.

`lever_used` connects to `AchievementService.notify("stair_lever_used", â€¦)` in `stair_lever._ready` (`stair_lever.gd:48-49`, `:228-230`).

### What the suites assert

| Suite | ID | Assertion |
|-------|-----|-----------|
| `m7_suite.gd` | `:383-428` | one lever per stairs room across all 10 biomes |
| `m7_suite.gd` | `:431-443` | lever starts locked |
| `m7_suite.gd` | `:451-476` | two levers unlock together |
| `m7_suite.gd` | `:479-491` | `floor_options()` exposes three rows |
| `m7_suite.gd` | `:493-504` | `stairs_spawn_facing_y(null)` returns `0.0` |
| `m7_suite.gd` | `:507-575` | menu pause, focus, disabled reasons |
| `flow_suite.gd` | `:376-404` | floor-transition stair spawn |
| `dungeon_suite.gd` | `:894-921` | two-lever dictionary unlock |

## Contracts

- Scene node contract: `InteractArea`, `Label3D`, `Visual/Handle`, `AnimationPlayer`, `AudioStreamPlayer3D` (`stair_lever.tscn`).
- Room contract: `Props` (parent), `SpawnPoints/LeverSpawn` (mandatory placement), `SpawnPoints/PlayerSpawn` (arrival).
- Template contract: lever exists when `templateId.ends_with("_stairs")`.
- Group contract: `stair_menu` group node with `open_for_lever(lever, options)`.
- Public lever API: `floor_options() -> Array[Dictionary]`, `use(direction: String)`, `set_menu_open(bool)`.
- Outbound: `RunFlow.ascend_floor()`, `descend_floor()`, `retreat_to_hub()`, `can_retreat_to_hub()`.
- Signals: `lever_used(direction)` â†’ `AchievementService.notify`; `StairMenu.closed`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Lever creation, lock, unlock on boss death | IMPLEMENTED | `dungeon_builder.gd:790-858` |
| One lever per stairs room (dictionary) | IMPLEMENTED | `dungeon_builder.gd:54`, `:807-825` |
| Authored `stair_lever.tscn` | IMPLEMENTED | `scenes/dungeon/stair_lever.tscn`, `dungeon_builder.gd:21` |
| `LeverSpawn` in all 10 themes | IMPLEMENTED | `scenes/rooms/*/*_stairs.tscn` |
| Floor-transition spawn at stairs | IMPLEMENTED | `castle_run.gd:46-48`, `:294-321` |
| Menu pause + focus + mouse restore | IMPLEMENTED | `stair_menu.gd:25-57`, `:99-116` |
| Explicit options API (no private field reads) | IMPLEMENTED | `stair_lever.gd:72-118`, `stair_menu.gd:67-115` |
| Prompt floor number + locked explanation | IMPLEMENTED | `stair_lever.gd:139-154` |
| Pull/unlock animation, audio, VFX | IMPLEMENTED | `stair_lever.gd:63-67`, `:100-104`, `:175-220` |
| `lever_used` consumer | IMPLEMENTED | `stair_lever.gd:228-230` |
| Behavioral suite coverage | IMPLEMENTED | `m7_suite.gd:334-575`, `flow_suite.gd:376-404` |

## Related

- Improvement plan: [`../actual_improvements/stair-lever.md`](../actual_improvements/stair-lever.md) - **FINISHED**
- [`dungeon-builder.md`](dungeon-builder.md)
- [`room-templates.md`](room-templates.md)
- [`run-flow.md`](run-flow.md)
- [`castle-run.md`](castle-run.md)
- [`ui/menu_shell.md`](ui/menu_shell.md)
- [`audio-director.md`](audio-director.md)
- [`vfx-service.md`](vfx-service.md)
