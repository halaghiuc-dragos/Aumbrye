# Castle run

`castle_run.tscn` is the production dungeon scene for castle and endless modes. `RunFlow` loads it with a procgen `DungeonDefinition`; the scene script builds the floor through a runtime `DungeonBuilder`, wires boss door / stairs / death / save, and tracks the active room. On the live play path from the hub castle and endless portals. `forgotten_castle_slice` is a hand-authored editor/validation fixture with no `RunFlow` wiring.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/castle_run.gd` | Scene controller: build, room tracking, boss door, snapshots, death, respawn outcome banner |
| `apps/game/client/scenes/dungeon/castle_run.tscn` | Authored Player, CombatHUD, InventoryUI, DebugOverlay, light |
| `apps/game/client/scripts/dungeon/forgotten_castle_slice.gd` | Editor fixture: spawn at entrance, toggle boss door marker / exit portal |
| `apps/game/client/scenes/dungeon/forgotten_castle_slice.tscn` | Static 8-room castle chain; no enemies, builder, or save on play path |
| `apps/game/client/scripts/ui/castle_entry_menu.gd` | Hub dungeon picker: new / continue / seed |
| `apps/game/client/scenes/ui/castle_entry_menu.tscn` | Menu shell |
| `content/fixtures/forgotten_castle_slice.json` | Default `DungeonBuilder.build()` fixture with secret `parentRoomId` |

## How it works

### Entry

Hub portal â†’ `CastleEntryMenu` (`hub.gd:61-63`, `:128-130`). Signals: `dungeon_run_requested` â†’ `RunFlow.start_new_run`, `continue_requested` â†’ `RunFlow.continue_castle_run`, `seed_run_requested` â†’ `RunFlow.start_run_with_seed`. Menu gates new runs on equipped weapon (`castle_entry_menu.gd:112-113`) and continue on `_castle_run_continuable()` (`:105-107`, `:218-222`): `has_continuable_run()` plus `runMode in ["castle", ""]`.

`RunFlow._enter_run` sets root metas (`dungeon_definition`, `run_snapshot`, â€¦) and loads `res://scenes/dungeon/castle_run.tscn` (`run_scene_router.gd:7`).

### `_ready` pipeline (`castle_run.gd:30-60`)

1. Join group `"castle_run"`.
2. Create `DungeonBuilder`, connect `boss_defeated` / `snapshot_dirty`.
3. `_resolve_dungeon_definition()` from `RunFlow.current_dungeon_definition` or root meta; empty â†’ error + `return_to_hub` (`:38-42`).
4. `build_from_definition` â€” **no fixture fallback**.
5. Biome presentation, runtime UI (`BossIntro`, `EpilogueCard`, `StairMenu`), snapshot restore (including floor-transition stair spawn), room id, deferred floor snap, death/health/inventory wiring, XP shard, respawn outcome banner, equipment, ambience.

### Floor transitions

`RunFlow.ascend_floor` / `descend_floor` regenerate or cache the next definition, write `run_snapshot` via `_build_floor_transition_snapshot` (`run_flow.gd:623-633`: `floorTransition`, `ascending`, tallies â€” **no player pose**), and reload the scene.

`castle_run._restore_saved_snapshot` applies the snapshot, calls `_place_at_stair_from_snapshot` when `floorTransition` is true, then removes `run_snapshot` meta (`castle_run.gd:314-325`). Stair-side spawn runs before meta removal; ascending uses `ascending: true`, descending uses `ascending: false` for `get_stair_spawn_global`.

### Boss room

`BOSS_ROOM_ID := "boss"` (`castle_run.gd:6`). Door registered from builder; sealed when the player is deep in the boss room (`:93-100`, `:214-221`). Cross-boundary hit blocking via `is_cross_boss_boundary` (consumed by `hitbox.gd`). First boss-room entry shows intro + HUD bind (`:142-154`). Defeat â†’ `RunFlow.register_boss_defeated`, door release, final-floor epilogue (`:485-506`).

### Stairs and escape

Levers from rooms whose `template_id` ends with `_stairs` via `RunFloorConfig.is_stairs_room` (`dungeon_builder.gd:780-787`, `run_floor_config.gd:47-55`). Interact opens `stair_menu` group UI or calls `RunFlow.ascend_floor` / `descend_floor` / `retreat_to_hub`. Shift+interact on a descend-only lever uses `_can_descend` (`stair_lever.gd:57-58`). Final-floor exit portal (`exit_portal.gd`) calls `complete_run_via_portal` when opened after boss defeat.

### Death and continue

Death releases the door and calls `RunFlow.on_player_died` (`castle_run.gd:509-513`): bonfire checkpoint â†’ `_bonfire_death_respawn` sets `run_respawn_results` meta and reloads castle; `castle_run._show_respawn_outcome_if_needed` shows `CombatHUD.show_respawn_outcome` once; else results screen. Snapshots write `LocalSave.activeRun.snapshot` (schema v4) from pose, enemies, loot, boss flags (`:427-482`).

### Forgotten castle slice

`forgotten_castle_slice.gd` spawns the player at `Rooms/CastleEntrance` and exposes `open_boss_door` / `open_exit_portal` on hardcoded paths. Header documents editor/validation-only scope. No code under `apps/game/client` loads the scene on the live play path; fixture JSON is the default for `DungeonBuilder.build()` only. Validation asserts `castle_run.gd` does not contain the string `forgotten_castle_slice`.

## Contracts

| Contract | Detail |
|----------|--------|
| Group | `"castle_run"` â€” queried by `RunFlow`, `hitbox`, `debug_overlay` |
| Boss room id | Literal `"boss"` in door setup and room tracking |
| Root metas | `dungeon_definition`, `run_snapshot`, `run_respawn_results`, `run_seed`, â€¦ from `RunFlow._enter_run` / bonfire respawn |
| Signals in | `boss_defeated`, `snapshot_dirty`, door `door_opened` / `door_sealed`, `CombatReactions.player_died` |
| Autoloads | `RunFlow`, `LocalSave`, `BiomeRegistry`, `RunFloorConfig`, `WorldState`, `InventoryService`, `AudioDirector`, `CharacterService` |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Procgen castle / endless via `castle_run` | IMPLEMENTED | `RunFlow` â†’ `build_from_definition` |
| Hub entry menu | IMPLEMENTED | `hub.gd` + `castle_entry_menu.gd` |
| Floor-transition stair spawn | IMPLEMENTED | `_place_at_stair_from_snapshot` in `_restore_saved_snapshot` (`castle_run.gd:314-325`) |
| Boss door / exit portal / multi-floor | IMPLEMENTED | Builder + `castle_run` |
| Save / continue / bonfire | IMPLEMENTED | Snapshot + `lastCheckpoint` paths |
| Bonfire respawn HUD banner | IMPLEMENTED | `run_respawn_results` â†’ `CombatHUD.show_respawn_outcome` (`castle_run.gd:122-129`, `combat_hud.gd:684-703`) |
| `forgotten_castle_slice` | PLACEHOLDER | Editor/validation fixture only; no RunFlow |
| Continue button run-mode filter | IMPLEMENTED | `_castle_run_continuable()` (`castle_entry_menu.gd:218-222`) |
| Debug label | IMPLEMENTED | `castle_run.tscn` â€” "Castle Run" |

## Related

- Improvement plan: [`../actual_improvements/castle-run.md`](../actual_improvements/castle-run.md) - **FINISHED**
- [`run-flow.md`](run-flow.md), [`dungeon-builder.md`](dungeon-builder.md), [`bosses.md`](bosses.md), [`boss-door-exit-portal.md`](boss-door-exit-portal.md), [`stair-lever.md`](stair-lever.md)
