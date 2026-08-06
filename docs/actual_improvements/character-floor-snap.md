# Character floor snap — improvement plan

## Status: FINISHED

## Current state

`CharacterFloorSnap` (`apps/game/client/scripts/art/characters/character_floor_snap.gd`) probes world geometry, snaps `CharacterBody3D` collision feet in world space, and aligns `DioramaVisual` rigs to the same plane through `snap_character`. Player and enemies share the unified entry point; dungeon, waves, and castle spawns call `snap_to_floor_below` or `snap_feet_to_world_y`. See [`../existing_codebase/character-floor-snap.md`](../existing_codebase/character-floor-snap.md).

## Gaps
| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| SNP-01 | P0 | `align_diorama_visual` assumed parent origin was the floor | **FINISHED** — world-space feet via `to_global` / `global_position` |
| SNP-02 | P0 | No floor measurement; callers trusted `floor_y = 0.0` | **FINISHED** — `probe_floor_y` + `snap_to_floor_below` on all spawn paths |
| SNP-03 | P1 | `feet_local_y` was a fake stub | **FINISHED** — removed; `_assert_feet_at_origin` + `rig_mesh_min_y` |
| SNP-04 | P1 | Only three collision shape types handled | **FINISHED** — sphere, separation ray, debug-mesh fallback + warning |
| SNP-05 | P1 | Only first named `CollisionShape3D` considered | **FINISHED** — minimum over all enabled shapes with transform composition |
| SNP-06 | P2 | Parent-local `position.y` vs world `floor_y` mismatch | **FINISHED** — `snap_feet_to_world_y` writes via `global_position` |
| SNP-07 | P2 | Player and enemies used different API halves | **FINISHED** — `snap_character` from `locomotion.gd` and `castle_enemy_base.gd` |
| SNP-08 | P2 | No validation coverage | **FINISHED** — `player_suite.gd` + `enemy_suite.gd` |

## Target design

**Work in world space, then convert once.** `snap_feet_to_world_y` moves the body along world Y until `collision_bottom_local` sits on the target height, using `global_position` so parent offsets and rotation do not leak into placement.

**Measure the floor.** `probe_floor_y(world, from, fallback, max_drop, mask)` raycasts from `from + PROBE_UP_OFFSET` downward up to `PROBE_MAX_DROP`, rejects normals steeper than `PROBE_MAX_SLOPE_DEG` (50°), and returns `fallback` on miss. `snap_to_floor_below` combines probe + placement.

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `PROBE_UP_OFFSET` | `1.0` m | ray start above probe origin |
| `PROBE_MAX_DROP` | `6.0` m | maximum downward ray length |
| `PROBE_MASK` | `1` | world geometry layer |
| `PROBE_MAX_SLOPE_DEG` | `50.0` | reject wall-like hits |

**Handle every shape.** `collision_bottom_local` min-reduces all enabled `CollisionShape3D` children. Supported primitives plus `ConvexPolygonShape3D` / concave via `get_debug_mesh().get_aabb().position.y` with `push_warning`.

**Rig feet invariant.** Rigs keep feet at the visual origin; `DioramaCharacterSkin._assert_feet_at_origin` errors when combined mesh AABB min y exceeds `0.02` m.

**One entry point per character.** `snap_character(body, visual, fallback_y)` probes, snaps collision, then aligns the visual.

## Work plan

1. **Rewrite `collision_bottom_local`** — SNP-04, SNP-05.
2. **Add `probe_floor_y`** — SNP-02 measurement.
3. **Add `snap_feet_to_world_y` and `snap_to_floor_below`** — SNP-06.
4. **Rewrite `align_diorama_visual`** — SNP-01.
5. **Migrate call sites** in `dungeon_builder.gd`, `waves_run.gd`, `castle_run.gd` — SNP-02.
6. **Delete `feet_local_y`**; add rig-origin assertion — SNP-03.
7. **Add `snap_character`** to `locomotion.gd` and `castle_enemy_base.gd` — SNP-07.
8. **Extend validation suites** — SNP-08.

## Data and schema changes

- No content JSON, schema, or save changes. Probe constants live on `character_floor_snap.gd`.
- World geometry must be on collision layer `1` (same convention as `orbit_camera.gd` and `lock_on.gd`).

## Acceptance criteria

- [x] Enemy under parent offset `3.0` m has visual feet matching collision bottom within `0.01` m. (SNP-01)
- [x] Enemy on platform at `2.4` m stands on the platform. (SNP-02)
- [x] Probe hitting only a 70° wall returns fallback. (SNP-02)
- [x] `feet_local_y` removed; built profiles have mesh AABB min y within `0.02` m. (SNP-03)
- [x] `SphereShape3D` radius `0.5` at local y `0.5` snaps bottom to floor. (SNP-04)
- [x] Foot box + torso capsule measured from foot box. (SNP-05)
- [x] Disabled `CollisionShape3D` ignored. (SNP-05)
- [x] Parent offset `5.0` m up snaps to correct world height. (SNP-06)
- [x] Player and enemies placed through `snap_character` with aligned collision and visuals. (SNP-07)

## Validation

`player_suite.gd`:

- `floor_snap.collision_bottom_capsule`, `collision_bottom_sphere`, `collision_bottom_multiple_shapes`, `collision_bottom_ignores_disabled`, `collision_bottom_unknown_shape_warns`
- `floor_snap.snap_respects_parent_offset`, `probe_finds_platform`, `probe_rejects_steep_normal`, `probe_miss_returns_fallback`
- `floor_snap.visual_aligned_under_offset_parent`, `snap_character_aligns_both`, `world_geometry_on_layer_one`, `rig_feet_at_origin`

`enemy_suite.gd`:

- `enemy.spawns_on_platform_floor` — one enemy per profile on a `2.4` m platform within `0.02` m

## Related
- Existing state: [`../existing_codebase/character-floor-snap.md`](../existing_codebase/character-floor-snap.md)
- [`locomotion.md`](locomotion.md), [`player-combat.md`](player-combat.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`enemies.md`](enemies.md), [`dungeon-builder.md`](dungeon-builder.md), [`castle-run.md`](castle-run.md), [`waves-run.md`](waves-run.md), [`floor-shell.md`](floor-shell.md), [`validation-suites.md`](validation-suites.md)
