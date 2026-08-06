# Boss door and exit portal — improvement plan

## Status: FINISHED

## Current state

Both interactables are authored scenes (`boss_room_door.tscn`, `exit_portal.tscn`) instantiated by `DungeonBuilder`. The exit portal requires `Props` and `ExitPortalMarker`, activates only through `ExitPortal.activate()`, and ends the run only after `RunOutcomeConfirm` on interact. The boss door uses a five-state enum with optional sigil / all-keys requirements from `DungeonCatalog.get_boss_door_requirement()`. Run snapshots persist `bossDoorState`. See [`../existing_codebase/boss-door-exit-portal.md`](../existing_codebase/boss-door-exit-portal.md).

## Gaps

| ID | Sev | Gap | Status | Evidence |
|----|-----|-----|--------|----------|
| BDP-01 | P0 | Exit portal orphaned without `Props` | **DONE** | `dungeon_builder.gd:745-761` — parent/marker checked before instantiate; errors on missing nodes |
| BDP-02 | P0 | Portal completes run on step-in | **DONE** | `exit_portal.gd:56-68` — `RunOutcomeConfirmScript.ask` on interact only |
| BDP-03 | P1 | No scene files; code-built trees | **DONE** | `scenes/dungeon/boss_room_door.tscn`, `exit_portal.tscn`; `dungeon_builder.gd:754,877` |
| BDP-04 | P1 | Door opens on any interact | **DONE** | `boss_room_door.gd:8,118-135`; `dungeon_catalog.gd:166-168`; `content/dungeons/dark_cathedral.json` `bossDoorRequirement: "sigil"` |
| BDP-05 | P1 | Sealed door hides label | **DONE** | `boss_room_door.gd:149-158` — sealed state shows "The way back is sealed" |
| BDP-06 | P1 | `activate()` bypassed | **DONE** | `dungeon_builder.gd:160-168` — `open_exit_portal()` calls `activate()` only |
| BDP-07 | P1 | Door built without boss | **DONE** | `dungeon_builder.gd:869-872`; `castle_run.gd:213-220` — exit/boss room ids from definition |
| BDP-08 | P2 | `seal_door()` clears `_opened` | **DONE** | `boss_room_door.gd:8,52-54` — single `_state` enum; `is_opened()` true in OPEN/RELEASED only |
| BDP-09 | P2 | No audio/VFX | **DONE** | `boss_room_door.gd:72,88,99`; `exit_portal.gd:40-41,64`; `audio_director.gd:49-53,260-261`; `vfx_service.gd:137-158` |
| BDP-10 | P2 | Suites only assert existence | **DONE** | `dungeon_suite.gd:1088-1288`; `m6_suite.gd:591-607`; `flow_suite.gd:22-36` |
| BDP-11 | P2 | No `deactivate()` | **DONE** | `exit_portal.gd:44-51` |
| BDP-12 | P2 | Hardcoded portal path in slice | **DONE** | `forgotten_castle_slice.gd:44-52` — `_find_exit_portal()` via `RoomTemplate.room_id` |

## Target design

Implemented as specified: authored scenes, portal parent/marker contract, confirmation modal, door state enum with requirements, builder scene instantiation, audio cues via `AudioDirector.play_cue`, VFX via `VfxService`, snapshot `bossDoorState`.

## Work plan

1. **Portal parent check first** — DONE (`dungeon_builder.gd:745-761`).
2. **`activate()` / `deactivate()`** — DONE (`exit_portal.gd:33-51`, `dungeon_builder.gd:167`).
3. **Confirmation on exit** — DONE (`exit_portal.gd`, `run_outcome_confirm.gd`).
4. **Door state enum** — DONE (`boss_room_door.gd`).
5. **Boss room id from definition** — DONE (`castle_run.gd:213-220`).
6. **Authored scenes** — DONE (`scenes/dungeon/*.tscn`).
7. **Audio and VFX cues** — DONE (`audio_director.gd`, `vfx_service.gd`).
8. **Door requirement** — DONE (`dungeon_catalog.gd`, `content/dungeons/*.json`, `content/items/quest/boss_sigil.json`).
9. **Cleanup** — DONE (`forgotten_castle_slice.gd`).

## Data and schema changes

- `content/schemas/dungeon-catalog-entry.v1.json` — added `bossDoorRequirement` enum.
- `content/dungeons/<id>.json` — all ten entries include `bossDoorRequirement` (default `none`; `dark_cathedral` uses `sigil`).
- `content/items/quest/boss_sigil.json` + `content/items/catalog.json` materials list.
- Run snapshot key `bossDoorState` — `castle_run.gd:449-453,333-339` (defaults in apply when missing).

## Acceptance criteria

- [x] On every biome's final floor, the exit portal has a non-null parent under the boss room's `Props` node (BDP-01). Evidence: `dungeon_suite.gd:1178-1214`.
- [x] Entering the portal area does not complete the run; only a confirmed interact does (BDP-02). Evidence: `exit_portal.gd:56-68`.
- [x] `DungeonBuilder` contains no `Area3D.new()` or `StaticBody3D.new()` for the door or the portal (BDP-03). Evidence: `dungeon_builder.gd:745-761,869-897`.
- [x] With `bossDoorRequirement = "sigil"` and no sigil held, `interact` does not open the door and the prompt names the requirement (BDP-04). Evidence: `boss_room_door.gd:149-152`, `dungeon_suite.gd:1151-1175`.
- [x] In the sealed state the label is visible and non-empty (BDP-05). Evidence: `boss_room_door.gd:155-157`.
- [x] `open_exit_portal()` sets `monitoring` only via `ExitPortal.activate()` (BDP-06). Evidence: `dungeon_builder.gd:167`, `dungeon_suite.gd:1242-1262`.
- [x] A definition with `placements.boss == null` produces no `BossRoomDoor` node (BDP-07). Evidence: `dungeon_builder.gd:869-872`, `dungeon_suite.gd:1265-1288`.
- [x] `is_opened()` is false in `CLOSED` and `LOCKED`, true in `OPEN` and `RELEASED`, and false in `SEALED`, and `state` is the only stored field (BDP-08). Evidence: `boss_room_door.gd:8,52-54,100-104`.
- [x] Opening, sealing, and releasing the door each emit exactly one audio cue (BDP-09). Evidence: `boss_room_door.gd:72,88,99`.
- [x] A snapshot taken while sealed restores to `SEALED` (save format). Evidence: `castle_run.gd:449-453,333-339`.

## Validation

- `dungeon_suite.gd`: `test_boss_door_blocks`, `test_boss_door_opens_and_seals`, `test_boss_door_release`, `test_boss_door_requirement`, `test_exit_portal_parented`, `test_exit_portal_requires_confirm`, `test_exit_portal_activate_path`, `test_no_door_without_boss`.
- `flow_suite.gd`: `test_portal_completes_run`.
- `m6_suite.gd`: per-biome open/seal/release on boss door.

## Related

- [`../existing_codebase/boss-door-exit-portal.md`](../existing_codebase/boss-door-exit-portal.md)
- [`dungeon-builder.md`](dungeon-builder.md)
- [`room-templates.md`](room-templates.md)
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md)
- [`castle-run.md`](castle-run.md)
- [`run-flow.md`](run-flow.md)
- [`ui/run_outcome.md`](ui/run_outcome.md)
