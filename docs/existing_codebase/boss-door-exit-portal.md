# Boss door and exit portal

Two authored interactables that bracket the end of a floor. `BossRoomDoor` is the barrier the player opens to enter the arena and that seals behind them once they commit. `ExitPortal` is the run-completion trigger on the final floor only. Both are scene files instantiated by `DungeonBuilder`.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scenes/dungeon/boss_room_door.tscn` | Authored door node tree |
| `apps/game/client/scenes/dungeon/exit_portal.tscn` | Authored portal node tree |
| `apps/game/client/scripts/dungeon/boss_room_door.gd` | Five-state door machine, requirements, audio/VFX |
| `apps/game/client/scripts/dungeon/exit_portal.gd` | Dormant/active portal, confirmation before run end |
| `apps/game/client/scripts/ui/run_outcome_confirm.gd` | `MenuShell` confirmation wrapper for portal exit |
| `apps/game/client/scripts/dungeon/dungeon_builder.gd` | Instantiates scenes, `open_exit_portal`, `_create_exit_portal` |
| `content/items/quest/boss_sigil.json` | Quest item consumed for `bossDoorRequirement: "sigil"` |

## How it works

### Boss room door

`DungeonBuilder._setup_boss_door(castle_run)` (`dungeon_builder.gd:869-897`) returns early when `placements.boss` is null. Otherwise it instantiates `BOSS_ROOM_DOOR_SCENE`, calls `configure(biome_id, requirement, floor, locks)`, and parents the door to the exit room from `placements.exit` (default `"boss"`).

Scene tree:

```
BossRoomDoor (Node3D, boss_room_door.gd)
  Barrier (StaticBody3D, layer 1)
    BarrierShape (CollisionShape3D)
    MeshInstance3D
  InteractArea (Area3D, mask 2)
  Label3D
  DoorFrameVisual (from DioramaInteractableSkin.build_boss_door_frame)
```

`configure()` (`boss_room_door.gd:38-56`) reads `bossDoorRequirement` from `DungeonCatalog.get_boss_door_requirement(RunFlow.current_dungeon_id)` and sets initial state to `LOCKED` when `sigil` or `all_keys` is unmet, else `CLOSED`.

State enum (`boss_room_door.gd:8`):

| State | Barrier | Prompt when near |
|-------|---------|------------------|
| `LOCKED` | solid | "Sealed — find the Boss Sigil" or all-keys message |
| `CLOSED` | solid | interact glyph + "Enter the arena" |
| `OPEN` | disabled | hidden |
| `SEALED` | solid | "The way back is sealed" |
| `RELEASED` | disabled | hidden |

`is_opened()` is true only in `OPEN` and `RELEASED` (`boss_room_door.gd:52-54`). `seal_door()` no longer clears an `_opened` flag.

`CastleRun` drives lifecycle via `register_boss_door`, seal-on-depth (`castle_run.gd:92-100`), snapshot `bossDoorState` (`castle_run.gd:449-453`), and restore (`castle_run.gd:333-339`). Boss room id comes from `_get_boss_room_id()` (`castle_run.gd:213-217`), not a hardcoded constant.

### Exit portal

`_setup_exit_portal()` runs on final floors only (`dungeon_builder.gd:137-138`). `_create_exit_portal(room)` (`dungeon_builder.gd:745-761`):

1. Errors if `Props` is missing.
2. Errors if `Props/ExitPortalMarker` is missing (no position fallback).
3. Instantiates `EXIT_PORTAL_SCENE`, positions at marker, calls `configure(biome_id)`.

`ExitPortal.activate()` (`exit_portal.gd:33-41`) sets `monitoring` and `visible`, plays `portal_open` cue and portal VFX. `deactivate()` (`exit_portal.gd:44-51`) closes it. `body_entered` only sets proximity and label; `_unhandled_input` on `interact` calls `RunOutcomeConfirmScript.ask` then `RunFlow.complete_run_via_portal()` (`exit_portal.gd:56-68`).

`DungeonBuilder.open_exit_portal()` (`dungeon_builder.gd:160-168`) routes exclusively through `portal.activate()`.

`forgotten_castle_slice.gd` finds the portal via `_find_exit_portal()` scanning `Rooms` children for `RoomTemplate.room_id == "boss"` (`forgotten_castle_slice.gd:44-52`).

### Suite coverage

| Suite | Assertion |
|-------|-----------|
| `dungeon_suite.gd:1088-1288` | Door block/open/seal/release, sigil requirement, portal parent, confirm path, activate path, no door without boss |
| `m6_suite.gd:591-607` | Per-biome door open/seal/release |
| `flow_suite.gd:22-36` | Portal confirmation calls `complete_run_via_portal` |

## Contracts

- Door node names: `Barrier`, `Barrier/BarrierShape`, `Barrier/MeshInstance3D`, `InteractArea`, `Label3D` (`boss_room_door.gd:27-31`).
- Portal: room must have `Props` and `Props/ExitPortalMarker`; spawned node is `Props/ExitPortal`.
- Signals: `door_opened`, `door_sealed` — consumed by `CastleRun.register_boss_door`.
- `bossDoorRequirement`: `"none"` \| `"sigil"` \| `"all_keys"` in `content/dungeons/<id>.json`, read via `DungeonCatalog.get_boss_door_requirement()`.
- Snapshot key: `bossDoorState` (enum name string).
- Collision: interact areas mask 2; barrier layer 1.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Authored door and portal scenes | IMPLEMENTED | `scenes/dungeon/boss_room_door.tscn`, `exit_portal.tscn` |
| Portal parent/marker contract | IMPLEMENTED | `dungeon_builder.gd:745-761` |
| Run-completion confirmation | IMPLEMENTED | `exit_portal.gd:56-68`, `run_outcome_confirm.gd:10-28` |
| Door state enum + sealed label | IMPLEMENTED | `boss_room_door.gd:8,149-158` |
| Boss sigil / all-keys gate | IMPLEMENTED | `boss_room_door.gd:118-135,176-188` |
| `activate()` / `deactivate()` | IMPLEMENTED | `exit_portal.gd:33-51` |
| Audio cues (door + portal) | IMPLEMENTED | `audio_director.gd:49-53`; `boss_room_door.gd:72,88,99` |
| VFX on seal / portal open | IMPLEMENTED | `vfx_service.gd:137-158` |
| Snapshot `bossDoorState` | IMPLEMENTED | `castle_run.gd:449-453,333-339` |
| Behavioral suite coverage | IMPLEMENTED | `dungeon_suite.gd:1088-1288` |

## Related

- Improvement plan: [`../actual_improvements/boss-door-exit-portal.md`](../actual_improvements/boss-door-exit-portal.md)
- [`dungeon-builder.md`](dungeon-builder.md)
- [`room-templates.md`](room-templates.md)
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md)
- [`castle-run.md`](castle-run.md)
- [`run-flow.md`](run-flow.md)
- [`ui/run_outcome.md`](ui/run_outcome.md)
