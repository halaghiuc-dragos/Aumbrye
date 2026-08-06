# Character floor snap

## Status: FINISHED

`CharacterFloorSnap` places `CharacterBody3D` collision feet on measured or caller-supplied floor height and aligns `DioramaVisual` rigs to the same world plane. On the live play path for player spawn/teleport, enemy and boss spawn in procedural dungeons, castle run restore, and waves run.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/character_floor_snap.gd` | `class_name CharacterFloorSnap extends RefCounted`, all `static` |

Callers:

| Caller | Call |
|--------|------|
| `apps/game/client/scripts/player/locomotion.gd` | `snap_character(self, visual)` after rig build / appearance refresh |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | `snap_character(self, _diorama_visual)` in `_setup_diorama_visual` |
| `apps/game/client/scripts/dungeon/dungeon_builder.gd` | `snap_to_floor_below` on player, enemies, boss |
| `apps/game/client/scripts/dungeon/castle_run.gd` | `snap_feet_to_world_y` when raycast height known; else `snap_to_floor_below` |
| `apps/game/client/scripts/dungeon/waves_run.gd` | `snap_to_floor_below(enemy)` after `add_child` |

## How it works

### `collision_bottom_local(body)` (`character_floor_snap.gd`)

Iterates all enabled `CollisionShape3D` descendants (`find_children("*", "CollisionShape3D", true, false)`), computes each shape's lowest point in body-local space via `_collision_shape_bottom_local`, and returns the minimum. Supported primitives: `CapsuleShape3D`, `BoxShape3D`, `CylinderShape3D`, `SphereShape3D`, `SeparationRayShape3D`. Other shapes use `shape.get_debug_mesh().get_aabb().position.y` with `push_warning`. Returns `0.0` when no enabled shapes exist.

### `probe_floor_y(world, from, fallback, ...)` (`character_floor_snap.gd`)

Raycasts from `from + Vector3(0, PROBE_UP_OFFSET, 0)` downward `PROBE_UP_OFFSET + max_drop` metres with `collision_mask = PROBE_MASK` (default `1`). Rejects hits whose normal exceeds `PROBE_MAX_SLOPE_DEG` (50Â°). Returns hit `position.y` or `fallback` on miss/rejection.

| Constant | Value |
|----------|-------|
| `PROBE_UP_OFFSET` | `1.0` |
| `PROBE_MAX_DROP` | `6.0` |
| `PROBE_MASK` | `1` |
| `PROBE_MAX_SLOPE_DEG` | `50.0` |

### `snap_feet_to_world_y(body, world_floor_y)` (`character_floor_snap.gd`)

Computes current feet world Y via `body.to_global(Vector3(0, collision_bottom_local(body), 0))`, applies delta to `body.global_position.y`.

### `snap_to_floor_below(body, fallback_y = NAN)` (`character_floor_snap.gd`)

Probes floor below `body.global_position`; when `fallback_y` is `NAN`, uses current feet world Y. Calls `snap_feet_to_world_y`.

### `align_diorama_visual(body, visual)` (`character_floor_snap.gd`)

Sets `visual.global_position.y` to collision feet world Y; preserves X/Z. Assumes rig feet sit at the visual origin (enforced by `DioramaCharacterSkin._assert_feet_at_origin`).

### `snap_character(body, visual, fallback_y = NAN)` (`character_floor_snap.gd`)

Calls `snap_to_floor_below` then `align_diorama_visual` â€” unified entry for player and enemies.

### `snap_feet_to_floor(body, floor_y = 0.0)` (`character_floor_snap.gd`)

Alias for `snap_feet_to_world_y` (backward-compatible name).

## The two body conventions

| | Player | Enemies |
|---|--------|---------|
| `CollisionShape3D` offset | `y = 0.8` (`player.tscn`) | centred on body origin |
| Capsule height | `1.6` | `2.4` typical (knight) |
| `collision_bottom_local` | `0.0` | about `-1.2` |
| Rig placement | origin at feet; `snap_character` aligns visual | body origin floats; `snap_character` drops visual to feet |

Rig feet sit at the visual origin â€” leg pivots at `y = leg.y` with meshes offset down (`diorama_character_skin.gd`). `DioramaCharacterSkin.rig_mesh_min_y` and `_assert_feet_at_origin` enforce min y within `0.02` m.

## Contracts

- Floor probe requires the body to be in a `World3D` with geometry on collision layer `1` (castle blockout, arena shell, spring arm, lock-on rays).
- `snap_character` overwrites body `global_position.y` and visual `global_position.y`.
- `castle_run.gd` passes an explicit raycast height through `snap_feet_to_world_y` during save restore (`_raycast_floor_y`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Multi-shape collision-bottom computation | IMPLEMENTED | `character_floor_snap.gd` `collision_bottom_local`, `_shape_bottom_offset_y` |
| World-space feet snap | IMPLEMENTED | `snap_feet_to_world_y`, `snap_to_floor_below` |
| Floor raycast probe with slope rejection | IMPLEMENTED | `probe_floor_y`, constants `PROBE_*` |
| Rig alignment (world space) | IMPLEMENTED | `align_diorama_visual`, `snap_character` |
| Unified player + enemy entry point | IMPLEMENTED | `locomotion.gd`, `castle_enemy_base.gd` |
| Rig feet-at-origin invariant | IMPLEMENTED | `diorama_character_skin.gd` `_assert_feet_at_origin`, `rig_mesh_min_y` |
| `feet_local_y` stub | REMOVED | was `diorama_character_skin.gd`; deleted SNP-03 |
| Slope alignment (body rotation to normal) | ABSENT | only Y position is written |
| Continuous per-frame foot snapping | ABSENT | one-shot at spawn/teleport/appearance refresh |
| Validation coverage | IMPLEMENTED | `player_suite.gd` (`floor_snap.*`), `enemy_suite.gd` (`enemy.spawns_on_platform_floor`) |

## Related
- Improvement plan: [`../actual_improvements/character-floor-snap.md`](../actual_improvements/character-floor-snap.md) - **FINISHED**
- [`diorama-character-skin.md`](diorama-character-skin.md), [`locomotion.md`](locomotion.md), [`player-combat.md`](player-combat.md)
- [`dungeon-builder.md`](dungeon-builder.md), [`castle-run.md`](castle-run.md), [`waves-run.md`](waves-run.md), [`enemies.md`](enemies.md), [`floor-shell.md`](floor-shell.md)
