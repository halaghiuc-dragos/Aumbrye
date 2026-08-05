# Boss door and exit portal

Two small interactables that bracket the end of a floor. `BossRoomDoor` is the barrier the player opens to enter the arena and that seals behind them once they commit. `ExitPortal` is the run-completion trigger, present only on the final floor. Neither has a scene file — `DungeonBuilder` builds both node trees in code and attaches the scripts.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/boss_room_door.gd` | Barrier state machine, interact prompt, open/seal/release/reset |
| `apps/game/client/scripts/dungeon/exit_portal.gd` | `Area3D` that calls `RunFlow.complete_run_via_portal` |

## How it works

### Boss room door

`DungeonBuilder._setup_boss_door(castle_run)` (`dungeon_builder.gd:696-764`) builds the tree, then attaches the script and registers the door:

```
BossRoomDoor (Node3D, boss_room_door.gd)
  Barrier (StaticBody3D, layer 1, mask 0)
    BarrierShape (CollisionShape3D, DOOR_WIDTH x DOOR_HEIGHT x WALL_THICKNESS)
    MeshInstance3D (same box, biome wall material)
  InteractArea (Area3D, layer 0, mask 2, 5 x 4 x 3 box at local (0, 2, -2))
  Label3D (billboard, font 28, at (0, 4, -2), hidden)
```

It is parented to the room with the hardcoded id `"boss"` (`:697`) and positioned at `_boss_approach_socket(room).position + facing * 0.25`, falling back to `(0, 0, -depth/2 + 0.25)` (`:752-759`). `_boss_approach_socket` (`:771`) picks the socket whose world facing best matches the room's own `-Z`, and falls back to `find_socket(NORTH)`.

`_ready()` (`boss_room_door.gd:18`) resolves the five children by exact name, forces the label to billboard, and connects the area signals. All five lookups are non-optional except the mesh, so a missing `Barrier`, `BarrierShape`, `InteractArea`, or `Label3D` is a hard error.

State is two booleans, `_opened` and `_sealed`:

| Method | Line | `_opened` | `_sealed` | Barrier | Label |
|--------|------|-----------|-----------|---------|-------|
| initial | — | false | false | solid | prompt when near |
| `open_door()` | `:48` | true | false | disabled, hidden | hidden |
| `seal_door()` | `:59` | **false** | true | solid, visible | hidden |
| `release_door()` | `:71` | true | false | disabled, hidden | hidden |
| `reset_door()` | `:80` | false | false | solid, visible | prompt when near |

`seal_door()` setting `_opened = false` means `is_opened()` reports false while the barrier is up and the player is inside the arena. `_update_label()` (`:101`) hides the prompt whenever `_opened or _sealed or not _near_player`, so a sealed door gives the player no text at all — the barrier just appears.

`_unhandled_input` (`:30`) opens the door on `interact` when the player is in range and the door is neither sealed nor already open. There is no key or boss-token requirement.

`CastleRun` drives the lifecycle:

| Trigger | Line | Call |
|---------|------|------|
| player walks past `BOSS_GATE_DEPTH_THRESHOLD` into the arena while the door is open and the boss is alive | `castle_run.gd:94-97` | `seal_door()` |
| `door_opened` signal | `:193-194` | `_on_boss_door_opened` -> `_persist_snapshot` |
| `door_sealed` signal | `:195-196` | `_persist_snapshot` |
| snapshot restore with `bossDefeated` | `:317-319` | `release_door()` |
| boss defeat / run continue paths | `:474`, `:489` | `release_door()` |
| retry after death | `:393-394` | `reset_door()` |

`_is_player_deep_in_boss_room()` (`:203-210`) compares the player's local Z against `-half_depth + BOSS_GATE_DEPTH_THRESHOLD` using the hardcoded room id `BOSS_ROOM_ID`.

### Exit portal

`DungeonBuilder._setup_exit_portal()` (`dungeon_builder.gd:567`) runs only when `_is_final_floor`, and returns early if `Props/ExitPortal` already exists. `_create_exit_portal(room)` (`:577`) builds:

```
ExitPortal (Area3D, exit_portal.gd, layer 0, mask 2, monitoring = false, visible = false)
  CollisionShape3D (BoxShape3D 3 x 3 x 1)
  <DioramaInteractableSkin.build_exit_portal visuals>
```

positioned at `Props/ExitPortalMarker` or the hardcoded `(0, 1.5, 12)` (`:585-589`), then parented under the room's `Props` node — and only then. If the room has no `Props` child, the portal is fully constructed and never parented (`:596-599`), so it leaks and never fires.

`exit_portal.gd` is 19 lines: `_ready()` connects `body_entered` and hides itself when `monitoring` is false (`:5-8`); `activate()` sets `monitoring` and `visible` (`:11-13`); `_on_body_entered` requires a `CharacterBody3D` in the `player` group and calls `RunFlow.call_deferred("complete_run_via_portal")` (`:16-18`).

`activate()` has no callers. `DungeonBuilder.open_exit_portal()` (`:132-142`) instead sets `monitoring` and `visible` on the node directly, creating the portal first if it is missing. It is called from `_on_boss_defeated` when the floor is final (`:602-604`) and from `apply_snapshot` when `bossDefeated` is set (`:852-854`).

Entering the portal completes the run immediately — there is no confirmation prompt, no interact press, and no way to leave and come back.

`forgotten_castle_slice.gd:47` reaches the portal through the hardcoded path `Rooms/CastleBoss/Props/ExitPortal`, which only works for the authored castle slice scene.

### What the suites assert

| Suite | Line | Assertion |
|-------|------|-----------|
| `dungeon_suite.gd` | `:76-84` | `builder.get_boss_door() != null` |
| `dungeon_suite.gd` | `:86-99` | the exit room has `Props/ExitPortal` **or** `Props/ExitPortalMarker` |
| `m5_suite.gd` | `:215` | boss door present |
| `m6_suite.gd` | `:383-391` | boss door present, per biome |
| `flow_suite.gd` | `:86-91` | `RunFlow` exposes `complete_run_via_portal` |

Nothing asserts that the door actually blocks the player, that sealing happens, that the portal is parented, or that the portal fires.

## Contracts

- Node-name contract, enforced by `boss_room_door.gd:19-23`: `Barrier`, `Barrier/BarrierShape`, `Barrier/MeshInstance3D` (optional), `InteractArea`, `Label3D`.
- Node-name contract for the portal: the owning room must have a `Props` child; `Props/ExitPortalMarker` is optional.
- Signals out: `door_opened`, `door_sealed` — both consumed by `CastleRun.register_boss_door` (`castle_run.gd:191-196`).
- Run-scene contract: `register_boss_door(door)` is called by the builder if the parent implements it (`dungeon_builder.gd:763-764`).
- `RunFlow.complete_run_via_portal()` (`run_flow.gd:355`) is the single exit path.
- Collision: both interact areas use `collision_layer = 0`, `collision_mask = 2`; the barrier is layer 1, mask 0.
- `InputGlyphService.format_interact_label()` supplies the prompt text.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Boss door open / seal / release / reset | IMPLEMENTED | `boss_room_door.gd:48-87` |
| Seal-on-commit behavior | IMPLEMENTED | `castle_run.gd:94-97,203-210` |
| Snapshot persistence around door state | IMPLEMENTED | `castle_run.gd:193-196,317-319` |
| Exit portal completes the run | IMPLEMENTED | `exit_portal.gd:16-18`, `run_flow.gd:355` |
| No scene files for either | PLACEHOLDER | both node trees built in code (`dungeon_builder.gd:696-764,577-599`) |
| Barrier is an untextured box | PLACEHOLDER | `BoxMesh` with the biome wall material (`dungeon_builder.gd:717-724`) |
| `ExitPortal.activate()` | STUB | no callers; the builder sets the fields directly (`dungeon_builder.gd:140-142`) |
| Portal orphaned without a `Props` node | BROKEN | built and skinned before the parent check (`dungeon_builder.gd:577-599`); 72 of 90 room scenes have no `Props` |
| Boss door built with no boss | PARTIAL | `_setup_boss_door` runs unconditionally on every floor (`dungeon_builder.gd:696`) |
| Hardcoded `"boss"` room id | PARTIAL | `dungeon_builder.gd:697`, `castle_run.gd:204` |
| `seal_door()` clears `_opened` | PARTIAL | `is_opened()` lies while the player is sealed in (`boss_room_door.gd:63`) |
| Sealed door gives no feedback | PARTIAL | `_update_label` hides the label when `_sealed` (`boss_room_door.gd:102-104`) |
| Door opening requirement | ABSENT | any `interact` press opens it; no key, token, or boss-unlock gate (`boss_room_door.gd:30-37`) |
| Run-completion confirmation | ABSENT | walking into the portal ends the run immediately (`exit_portal.gd:16-18`) |
| Portal on non-final floors | ABSENT by design | `_setup_exit_portal` is gated on `_is_final_floor` (`dungeon_builder.gd:113-114`) |
| Portal deactivation | ABSENT | no `deactivate()`; once open it stays open |
| Suite coverage of behavior | ABSENT | suites only assert the nodes exist (`dungeon_suite.gd:76-99`) |
| Door / portal audio and VFX | ABSENT | no `AudioDirector` or `VfxService` call in either script |

## Related

- Improvement plan: [`../actual_improvements/boss-door-exit-portal.md`](../actual_improvements/boss-door-exit-portal.md)
- [`dungeon-builder.md`](dungeon-builder.md) — builds both, `open_exit_portal`, `_boss_approach_socket`
- [`room-templates.md`](room-templates.md) — the `Props`, `ExitPortalMarker`, and socket contract
- [`castle-run.md`](castle-run.md) — the lifecycle driver
- [`run-flow.md`](run-flow.md) — `complete_run_via_portal`
- [`bosses.md`](bosses.md) — the boss the door gates
- [`stair-lever.md`](stair-lever.md) — the non-final-floor exit
- [`ui/input_glyphs.md`](ui/input_glyphs.md) — prompt text
- [`ui/run_outcome.md`](ui/run_outcome.md) — the screen the portal opens
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — `build_exit_portal`, `build_boss_door_frame`
