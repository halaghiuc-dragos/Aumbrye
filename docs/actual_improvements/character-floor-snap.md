# Character floor snap — improvement plan

## Current state

`CharacterFloorSnap` (`apps/game/client/scripts/art/characters/character_floor_snap.gd`) is a 31-line static helper with three functions: `collision_bottom_local` derives the lowest point of a body's `CollisionShape3D`, `snap_feet_to_floor` places the body so that point rests on a given `floor_y`, and `align_diorama_visual` offsets a visual root. See [`../existing_codebase/character-floor-snap.md`](../existing_codebase/character-floor-snap.md).

The collision maths is correct for the three supported shapes. Two things are wrong. `align_diorama_visual` uses `-body.position.y` as its offset, which is only correct when the body's parent origin sits exactly at the floor — for an enemy spawned on a raised platform or with any parent offset, the visual is displaced by the platform height. And nothing verifies the floor: `snap_feet_to_floor` trusts a caller-supplied `floor_y` that defaults to `0.0`, with no raycast, so seven of the eight call sites place characters at world zero regardless of the actual geometry beneath them.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| SNP-01 | P0 | `align_diorama_visual` computes the visual offset as `-body.position.y - feet_y`, which assumes the body's parent origin is the floor plane. An enemy parented under a raised platform node, or whose parent has any y offset, gets its visual displaced by exactly that offset — feet floating or sunk | `character_floor_snap.gd:30`, called at `apps/game/client/scripts/enemies/castle_enemy_base.gd:113` |
| SNP-02 | P0 | No floor is ever measured. `snap_feet_to_floor(body, floor_y = 0.0)` takes the height on faith and seven of the eight call sites pass no argument at all, so every enemy and most player placements assume the floor is at world y zero | `character_floor_snap.gd:21`, `apps/game/client/scripts/dungeon/dungeon_builder.gd:443`, `:471`, `:558`, `apps/game/client/scripts/dungeon/waves_run.gd:195`, `apps/game/client/scripts/dungeon/castle_run.gd:354`, `:381`, `:388` |
| SNP-03 | P1 | `feet_local_y(_profile)` ignores its argument and returns `0.0` for every profile. The parameter name is underscore-prefixed, so it is a deliberate stub, but the signature advertises a per-profile value that does not exist and callers pass a profile string that is discarded | `apps/game/client/scripts/art/characters/diorama_character_skin.gd:193-196`, `character_floor_snap.gd:29` |
| SNP-04 | P1 | Only `CapsuleShape3D`, `BoxShape3D`, and `CylinderShape3D` are handled. A `SphereShape3D`, a `ConvexPolygonShape3D`, or any other shape silently returns just `collision.position.y`, placing the body half its height into the floor with no warning | `character_floor_snap.gd:12-18` |
| SNP-05 | P1 | Only the first `CollisionShape3D` named exactly `"CollisionShape3D"` is considered. A body with two shapes, or one named differently, is measured from the wrong shape or from nothing | `character_floor_snap.gd:8-10` |
| SNP-06 | P2 | `snap_feet_to_floor` writes `body.position.y`, which is parent-local, while `floor_y` reads as a world height. The two only agree when the parent is at the origin, which is the same latent assumption as SNP-01 | `character_floor_snap.gd:23` |
| SNP-07 | P2 | The player and enemies use different halves of the API. The player calls only `snap_feet_to_floor`; enemies call only `align_diorama_visual`. Nothing guarantees the player's own visual is aligned, and nothing guarantees an enemy's collision is | `castle_run.gd:345`, `castle_enemy_base.gd:113` |
| SNP-08 | P2 | No validation coverage. Neither `player_suite.gd` nor `enemy_suite.gd` asserts that a spawned character's feet touch the floor | grep of `CharacterFloorSnap` in `apps/game/client/scripts/validation/` returns nothing |

## Target design

**Work in world space, then convert once.** Every function that positions a node should compute the answer in world space and convert to parent-local exactly once at the write, which removes both SNP-01 and SNP-06 at the root:

```gdscript
static func snap_feet_to_world_y(body: Node3D, world_floor_y: float) -> void:
	var bottom_local := collision_bottom_local(body)
	var parent := body.get_parent() as Node3D
	var world_y := world_floor_y - bottom_local * _uniform_scale(body)
	body.position.y = world_y if parent == null else parent.to_local(Vector3(0.0, world_y, 0.0)).y
```

and the visual alignment becomes independent of the body's parent entirely, because it asks where the body's collision bottom is in the world and puts the visual root there:

```gdscript
static func align_diorama_visual(body: Node3D, visual: Node3D, profile: String) -> void:
	if visual == null:
		return
	var feet_world_y := body.global_position.y + collision_bottom_local(body) * _uniform_scale(body)
	var target := Vector3(visual.global_position.x, feet_world_y - feet_local_y(profile), visual.global_position.z)
	visual.global_position = target
```

Rejected alternative: adding a parent-offset argument to the existing signature. It would fix the symptom while leaving the same coordinate-space confusion in place for the next caller, and every existing call site would have to know a value it has no business knowing.

**Measure the floor.** Add a raycast probe so `floor_y` no longer has to be guessed:

```gdscript
static func probe_floor_y(world: World3D, from: Vector3, fallback: float,
		max_drop := PROBE_MAX_DROP, mask := PROBE_MASK) -> float
```

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `PROBE_UP_OFFSET` | `1.0` m | how far above `from` the ray starts, so a body already slightly sunk still finds the surface |
| `PROBE_MAX_DROP` | `6.0` m | ray length below `from`; a miss returns `fallback` |
| `PROBE_MASK` | `1` | world geometry layer, matching the spring arm and the lock-on line-of-sight ray |
| `PROBE_MAX_SLOPE_DEG` | `50.0` | a hit whose normal is steeper than this is rejected as a wall, and the ray continues |

New `snap_to_floor_below(body, fallback_y)` combines the probe and the placement, and becomes the call used by `dungeon_builder.gd`, `waves_run.gd`, and `castle_run.gd`. The explicit `snap_feet_to_world_y` stays for the cases where the caller genuinely knows the height, such as `castle_run.gd:345` which already passes a computed `floor_y`.

**Handle every shape.** Extend `collision_bottom_local` with `SphereShape3D` (`position.y - radius`), `SeparationRayShape3D` (`position.y - length`), and a generic fallback using `shape.get_debug_mesh().get_aabb().position.y` for convex and concave shapes. An unrecognized shape emits a `push_warning` naming the body and the shape class rather than silently returning a wrong answer.

**Handle multiple shapes.** Replace the single named lookup with the minimum over all `CollisionShape3D` children:

```gdscript
static func collision_bottom_local(body: Node3D) -> float:
	var lowest := INF
	for child in body.find_children("*", "CollisionShape3D", true, false):
		var shape := child as CollisionShape3D
		if shape.shape == null or shape.disabled:
			continue
		lowest = minf(lowest, _shape_bottom(shape, body))
	return 0.0 if lowest == INF else lowest
```

`_shape_bottom` composes the shape's local bottom with the transform from the shape node up to `body`, so a shape nested under an intermediate node is measured correctly.

**Honest `feet_local_y`.** Either make it real or remove it. The rig genuinely places feet at the origin (`diorama_character_skin.gd:193-194`), so the correct action is to delete the function and the `profile` argument that only exists to feed it, and document the rig invariant with an assertion in the skin builder: after building a profile, the combined AABB of its meshes must have a minimum y within `0.02` m of zero. That converts an unused abstraction into an enforced invariant.

**One entry point per character.** Add `snap_character(body, visual, profile, fallback_y)` that probes the floor, places the collision, and aligns the visual in that order, and use it for both the player and enemies. The player path in `locomotion.gd` calls it after the rig is built; `castle_enemy_base.gd` replaces its `align_diorama_visual` call with it.

## Work plan

1. **Rewrite `collision_bottom_local`** as a minimum over all enabled shapes with the transform composition, add the three missing shape types and the debug-mesh fallback, and add the `push_warning`. Closes SNP-04 and SNP-05.
2. **Add `probe_floor_y`** with the four probe constants and the slope rejection. Closes the measurement half of SNP-02.
3. **Add `snap_feet_to_world_y`** and `snap_to_floor_below`, both parent-space correct. Closes SNP-06.
4. **Rewrite `align_diorama_visual`** to work from the body's world feet position. Closes SNP-01.
5. **Migrate the call sites**: `dungeon_builder.gd:443`, `:471`, `:558`, `waves_run.gd:195`, `castle_run.gd:354`, `:381`, `:388` move to `snap_to_floor_below`; `castle_run.gd:345` keeps the explicit height through `snap_feet_to_world_y`. Closes the rest of SNP-02.
6. **Delete `feet_local_y`** and the `profile` argument, and add the rig-origin assertion in `diorama_character_skin.gd`. Closes SNP-03.
7. **Add `snap_character`** and use it from both `locomotion.gd` and `castle_enemy_base.gd`. Closes SNP-07.
8. **Add the validation cases** below. Closes SNP-08.

## Data and schema changes

- No content JSON, no schema, and no save change. Every value is a named GDScript constant on `character_floor_snap.gd`.
- Removing `feet_local_y` is a source-level API change with two call sites, both listed above.
- World geometry must be on collision layer `1` for the probe to find it. That is already the convention used by the spring arm (`orbit_camera.gd:38`) and the lock-on line-of-sight ray (`lock_on.gd:306`), so no content retagging is expected; the validation case below confirms it.

## Acceptance criteria

- [ ] An enemy spawned under a parent node offset `3.0` m up has its visual feet at the same world height as its collision bottom, within `0.01` m. (SNP-01)
- [ ] An enemy spawned on a platform whose surface is at `2.4` m stands on the platform, not at world zero. (SNP-02)
- [ ] A floor probe that hits only a `70` deg wall falls back to the supplied height rather than snapping to the wall. (SNP-02)
- [ ] `feet_local_y` no longer exists, and building any character profile produces a mesh AABB whose minimum y is within `0.02` m of zero. (SNP-03)
- [ ] A body with a `SphereShape3D` of radius `0.5` at local y `0.5` snaps so its lowest point is exactly on the floor. (SNP-04)
- [ ] A body with a `0.3` m tall foot box and a `1.6` m tall torso capsule is measured from the foot box. (SNP-05)
- [ ] A disabled `CollisionShape3D` is ignored. (SNP-05)
- [ ] A body whose parent is offset `5.0` m up and rotated snaps to the correct world height. (SNP-06)
- [ ] Both the player and every enemy are placed through `snap_character`, and both have aligned collision and visuals. (SNP-07)

## Validation

Extend `apps/game/client/scripts/validation/suites/player_suite.gd`:

- `floor_snap.collision_bottom_capsule` — a `1.6` m capsule at local y `0.9` returns `0.1`.
- `floor_snap.collision_bottom_sphere` — a `0.5` m radius sphere at local y `0.5` returns `0.0`.
- `floor_snap.collision_bottom_multiple_shapes` — a foot box and a torso capsule return the foot box bottom.
- `floor_snap.collision_bottom_ignores_disabled` — disabling the lower shape raises the returned bottom.
- `floor_snap.collision_bottom_unknown_shape_warns` — a `ConvexPolygonShape3D` returns its debug-mesh AABB minimum, not `position.y`.
- `floor_snap.snap_respects_parent_offset` — parent at y `5.0`, floor at y `2.0`, assert the resulting `global_position.y` places the collision bottom at `2.0`.
- `floor_snap.probe_finds_platform` — a static box top at `2.4` m, probe from `4.0` m, assert `2.4` within `0.01`.
- `floor_snap.probe_rejects_steep_normal` — a `70` deg ramp only, assert the fallback is returned.
- `floor_snap.probe_miss_returns_fallback` — empty world, assert the fallback.
- `floor_snap.visual_aligned_under_offset_parent` — parent at y `3.0`, assert the visual's world feet match the collision bottom within `0.01`.
- `floor_snap.snap_character_aligns_both` — call `snap_character` and assert both the collision bottom and the visual feet sit on the probed floor.
- `floor_snap.world_geometry_on_layer_one` — build a floor shell and assert every `StaticBody3D` in it has bit `1` of `collision_layer` set, so the probe mask is valid.

Extend `apps/game/client/scripts/validation/suites/enemy_suite.gd`:

- `enemy.spawns_on_platform_floor` — spawn one enemy of each profile on a `2.4` m platform and assert each stands on it within `0.02` m.

## Related
- Existing state: [`../existing_codebase/character-floor-snap.md`](../existing_codebase/character-floor-snap.md)
- [`locomotion.md`](locomotion.md), [`player-combat.md`](player-combat.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`enemies.md`](enemies.md), [`dungeon-builder.md`](dungeon-builder.md), [`castle-run.md`](castle-run.md), [`waves-run.md`](waves-run.md), [`floor-shell.md`](floor-shell.md), [`validation-suites.md`](validation-suites.md)
