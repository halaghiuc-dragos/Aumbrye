# Castle run

`castle_run.tscn` is the production dungeon scene for castle and endless modes. `RunFlow` loads it with a procgen `DungeonDefinition`; the scene script builds the floor through a runtime `DungeonBuilder`, wires boss door / stairs / death / save, and tracks the active room. On the live play path from the hub castle and endless portals. `forgotten_castle_slice` is a separate hand-authored layout with no `RunFlow` wiring.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/castle_run.gd` | Scene controller: build, room tracking, boss door, snapshots, death |
| `apps/game/client/scenes/dungeon/castle_run.tscn` | Authored Player, CombatHUD, InventoryUI, DebugOverlay, light |
| `apps/game/client/scripts/dungeon/forgotten_castle_slice.gd` | Dev slice: spawn at entrance, toggle boss door marker / exit portal |
| `apps/game/client/scenes/dungeon/forgotten_castle_slice.tscn` | Static 8-room castle chain; no enemies, builder, or save |
| `apps/game/client/scripts/ui/castle_entry_menu.gd` | Hub dungeon picker: new / continue / seed |
| `apps/game/client/scenes/ui/castle_entry_menu.tscn` | Menu shell; `BiomeBox` present but hidden |

## How it works

### Entry

Hub portal → `CastleEntryMenu` (`hub.gd:61-63`, `:128-130`). Signals: `dungeon_run_requested` → `RunFlow.start_new_run`, `continue_requested` → `RunFlow.continue_castle_run`, `seed_run_requested` → `RunFlow.start_run_with_seed`. Menu gates new runs on equipped weapon (`castle_entry_menu.gd:112-113`) and continue on `LocalSave.has_continuable_run()` (`:106-107`) without filtering `runMode`. `RunFlow.continue_castle_run` still rejects non-castle saves (`run_flow.gd:106-109`).

`RunFlow._enter_run` sets root metas (`dungeon_definition`, `run_seed`, `run_snapshot`, …) and loads `res://scenes/dungeon/castle_run.tscn` (`run_scene_router.gd:7`).

### `_ready` pipeline (`castle_run.gd:31-61`)

1. Join group `"castle_run"`.
2. Create `DungeonBuilder`, connect `boss_defeated` / `snapshot_dirty`.
3. `_resolve_dungeon_definition()` from `RunFlow.current_dungeon_definition` or root meta; empty → error + `return_to_hub` (`:39-43`).
4. `build_from_definition` — **no fixture fallback**.
5. Biome presentation, runtime UI (`BossIntro`, `EpilogueCard`, `StairMenu`), snapshot restore, floor-transition spawn, room id, deferred floor snap, death/health/inventory wiring, XP shard, equipment, ambience.

### Floor transitions

`RunFlow.ascend_floor` / `descend_floor` regenerate or cache the next definition, write `run_snapshot` via `_build_floor_transition_snapshot` (`run_flow.gd:577-587`: `floorTransition`, `ascending`, tallies — **no player pose**), and reload the scene.

`castle_run._ready` calls `_restore_saved_snapshot()` then `_apply_floor_transition_spawn()` (`:47-48`). Restore applies the snapshot and **removes** `run_snapshot` meta (`:303-311`). Transition spawn then looks for the same meta (`:284-287`) and returns immediately. Stair-side spawn therefore does not run after a floor change; the player stays at the builder entrance spawn.

### Boss room

`BOSS_ROOM_ID := "boss"` (`castle_run.gd:6`). Door registered from builder; sealed when the player is deep in the boss room (`:94-97`, `:203-210`). Cross-boundary hit blocking via `is_cross_boss_boundary` (consumed by `hitbox.gd`). First boss-room entry shows intro + HUD bind (`:128-139`). Defeat → `RunFlow.register_boss_defeated`, door release, final-floor epilogue (`:468-484`).

### Stairs and escape

Levers from rooms whose `template_id` ends with `_stairs` (`dungeon_builder.gd:610-677`). Interact opens `stair_menu` group UI or calls `RunFlow.ascend_floor` / `descend_floor` / `retreat_to_hub`. Final-floor exit portal (`exit_portal.gd`) calls `complete_run_via_portal` when opened after boss defeat.

`RunFloorConfig.find_stairs_room_id` also accepts `type == "corridor"` (`run_floor_config.gd:47-53`); lever setup does not — objective/spawn can target a room with no lever.

### Death and continue

Death releases the door and calls `RunFlow.on_player_died` (`castle_run.gd:487-491`): bonfire checkpoint → reload castle; else results screen. Snapshots write `LocalSave.activeRun.snapshot` (schema v4) from pose, enemies, loot, boss flags (`:411-465`).

### Forgotten castle slice

`forgotten_castle_slice.gd` (51 lines) spawns the player at `Rooms/CastleEntrance` and exposes `open_boss_door` / `open_exit_portal` on hardcoded paths. `ROOM_SCENES` preload table is unused. No code under `apps/game/client` loads the scene; fixture JSON is the default for `DungeonBuilder.build()` only, not the live `build_from_definition` path. Validation asserts `castle_run.gd` does not contain the string `forgotten_castle_slice`.

## Contracts

| Contract | Detail |
|----------|--------|
| Group | `"castle_run"` — queried by `RunFlow`, `hitbox`, `debug_overlay` |
| Boss room id | Literal `"boss"` in door setup and room tracking |
| Root metas | `dungeon_definition`, `run_snapshot`, `run_seed`, … from `RunFlow._enter_run` |
| Signals in | `boss_defeated`, `snapshot_dirty`, door `door_opened` / `door_sealed`, `CombatReactions.player_died` |
| Autoloads | `RunFlow`, `LocalSave`, `BiomeRegistry`, `RunFloorConfig`, `WorldState`, `InventoryService`, `AudioDirector`, `CharacterService` |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Procgen castle / endless via `castle_run` | IMPLEMENTED | `RunFlow` → `build_from_definition` |
| Hub entry menu | IMPLEMENTED | `hub.gd` + `castle_entry_menu.gd` |
| Floor-transition stair spawn | BROKEN | Meta removed before `_apply_floor_transition_spawn` (`castle_run.gd:47-48`, `:311`, `:286`) |
| Boss door / exit portal / multi-floor | IMPLEMENTED | Builder + `castle_run` |
| Save / continue / bonfire | IMPLEMENTED | Snapshot + `lastCheckpoint` paths |
| `forgotten_castle_slice` | PLACEHOLDER | No RunFlow, enemies, or save |
| Continue button run-mode filter | PARTIAL | Menu enables any continuable run; `continue_castle_run` rejects endless |
| `inventory_ui_path` export | STUB | Declared `castle_run.gd:16`, never read |
| Debug label "M2 Castle Run" | PLACEHOLDER | `castle_run.tscn` stale label |

## Related

- Improvement plan: [`../actual_improvements/castle-run.md`](../actual_improvements/castle-run.md)
- [`run-flow.md`](run-flow.md), [`dungeon-builder.md`](dungeon-builder.md), [`bosses.md`](bosses.md), [`boss-door-exit-portal.md`](boss-door-exit-portal.md), [`stair-lever.md`](stair-lever.md)
