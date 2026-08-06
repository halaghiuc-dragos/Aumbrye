# World state — improvement plan

## Status: FINISHED

## Current state
`WorldState` (`apps/game/client/scripts/app/world_state.gd`) is a namespaced, validated string→Variant dictionary that dungeon interactables use for locks, levers, and room content. Snapshot round-trip through `activeRun.snapshot.worldFlags` is deep-copied and validated on restore. `WorldFlags` (`world_flags.gd`) is the canonical id registry. Flags clear on run start, run end, and hub return. `namespace_changed` subscribers replace polling in door and vault content scripts.

## Gaps
| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| WST-01 | P0 | `all_flags()` shallow copy aliases nested containers into the save blob | **FINISHED** — `duplicate(true)` at `world_state.gd:56-57` |
| WST-02 | P1 | `has_flag` conflates unset with falsy values | **FINISHED** — `has_flag` / `is_flag_true` split at `world_state.gd:35-40` |
| WST-03 | P1 | Flags survive retreat/abandon into the hub | **FINISHED** — `returned_to_hub` connected at `world_state.gd:15`, `world_state.gd:87-88` |
| WST-04 | P1 | `flag_changed` has no subscribers; consumers poll | **FINISHED** — `namespace_changed` at `world_state.gd:6`; door/vault subscribe |
| WST-05 | P1 | No flag id registry | **FINISHED** — `world_flags.gd`; `set_flag` validates |
| WST-06 | P2 | `restore_flags` accepts arbitrary values | **FINISHED** — `_sanitize_value` + rejection count at `world_state.gd:60-75` |
| WST-07 | P2 | No `erase_flag` | **FINISHED** — `erase_flag` at `world_state.gd:47-53` |

## Target design

Implemented as specified. See [`../existing_codebase/world-state.md`](../existing_codebase/world-state.md) for the live API.

## Work plan

1. **Add `world_flags.gd`** — FINISHED.
2. **Migrate call sites to builders** — FINISHED (`room_locked_door_content.gd`, `room_locked_vault_content.gd`, `room_puzzle_content.gd`, `room_npc_quest_content.gd`).
3. **Add validation, `is_flag_true`, `erase_flag`, presence-based `has_flag`** — FINISHED (`world_state.gd`).
4. **Deep-copy capture and sanitised restore** — FINISHED (`world_state.gd`, `castle_run.gd:316`).
5. **Connect `returned_to_hub`** — FINISHED (`world_state.gd:15`).
6. **Add `namespace_changed` and convert polling consumers** — FINISHED (door/vault scripts).

## Data and schema changes

`save_migrator.gd` `CURRENT_VERSION` bumped to `5`. `_migrate_v4_to_v5` rewrites legacy `key_*` → `lock.lock_*.opened` and `quest_*_active` → `secret.*.opened` in both `activeRun.snapshot` and `activeRun.lastCheckpoint` via `WorldFlags.migrate_legacy_id`. Unmapped keys are dropped.

## Acceptance criteria
- [x] `set_flag("room.r1.cleared", {"enemies": []})`, then mutating the passed dictionary, leaves `all_flags()["room.r1.cleared"]["enemies"]` unchanged. (WST-01)
- [x] `set_flag("chest.c1.opened", 0)` then `has_flag("chest.c1.opened")` is `true` and `is_flag_true("chest.c1.opened")` is `false`. (WST-02)
- [x] After `RunFlow.retreat_to_hub()`, `WorldState.all_flags()` is empty. (WST-03)
- [x] No dungeon interactable script calls `WorldState.has_flag` or `is_flag_true` from `_process`. (WST-04)
- [x] `set_flag("someTypo", true)` stores nothing and pushes an error in a debug build. (WST-05)
- [x] `restore_flags({"lock.a.opened": true, "garbage": Callable()})` stores one flag, returns `1`, and does not crash. (WST-06)
- [x] `erase_flag("lock.a.opened")` removes the key from `all_flags()` and emits `flag_changed("lock.a.opened", null)`. (WST-07)

## Validation
`apps/game/client/scripts/validation/suites/world_state_suite.gd` registered in `SUITE_PATHS`:

| Assertion id | Checks |
|--------------|--------|
| `world_state.id.rejects_unnamespaced` | `set_flag("foo", true)` leaves `all_flags()` empty |
| `world_state.id.accepts_builder_output` | `WorldFlags.lock_opened("gate_a")` is accepted and readable |
| `world_state.copy.deep` | Nested container mutation after `all_flags()` does not alter the copy |
| `world_state.presence.vs_truthiness` | `has_flag` / `is_flag_true` disagree for a `0` value |
| `world_state.erase.emits_null` | `erase_flag` removes the key and emits `flag_changed(id, null)` |
| `world_state.restore.rejects_invalid` | Mixed valid/invalid dictionary yields the correct rejection count and only valid keys |
| `world_state.lifecycle.cleared_on_return_to_hub` | Emitting `returned_to_hub` empties `_flags` |

`save_suite.gd` assertion `save.migrate.world_flags_namespaced` covers v4→v5 legacy id migration.

`room_content_suite.gd` assertion `room_content.world_flags.registry_only` verifies generated content ids satisfy `WorldFlags.is_valid_id`.

## Related
- Existing state: [`../existing_codebase/world-state.md`](../existing_codebase/world-state.md)
- [`run-flow.md`](run-flow.md), [`save-migrator.md`](save-migrator.md), [`local-save.md`](local-save.md), [`inventory-service.md`](inventory-service.md)
- Owned elsewhere: [`castle-run.md`](castle-run.md), [`stair-lever.md`](stair-lever.md), [`dungeon-traps.md`](dungeon-traps.md), [`room-content.md`](room-content.md)
