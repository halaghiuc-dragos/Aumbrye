# Hitboxes and hurtboxes

The `Area3D` pair that turns an attack into a `DamageInfo` delivery, plus the debug visualization for both and the service that limits how many enemies may commit to an attack at once. Every damage source in the client — melee, projectiles, traps — ends at `Hurtbox.receive_hit`.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/combat/hitbox.gd` | `Hitbox` `Area3D`: overlap scan, team filter, line-of-sight, `DamageInfo` construction |
| `apps/game/client/scripts/combat/hurtbox.gd` | `Hurtbox` `Area3D`: `receive_hit` mitigation chain (detailed in [`combat-core.md`](combat-core.md)) |
| `apps/game/client/scripts/combat/combat_collision_debug.gd` | `CombatCollisionDebug`: builds an unshaded wire-ish mesh from a `CollisionShape3D` |
| `apps/game/client/scripts/combat/attack_token_service.gd` | `AttackTokenService` autoload: per-group attacker concurrency cap |

## How it works

### Hitbox lifecycle

`Hitbox._ready()` (`hitbox.gd:23`) joins the `combat_hitbox` group, caches the child `CollisionShape3D` (pushing an error if absent), connects `area_entered`, and starts fully disabled: `monitoring = false`, `monitorable = false`, `set_physics_process(false)`. `_owner_node` is resolved once by walking ancestors to the first `CharacterBody3D`, falling back to `get_parent()`.

`enable()` sets `_active`, `monitoring`, physics processing, and immediately calls `_scan_overlaps()` so a target already inside the box is hit on the activation frame rather than on the next `area_entered`. `disable()` reverses it and zeroes `_last_overlap_count`. `reset_swing()` clears `_hit_targets`.

`set_attack_values(damage, poise, dmg_type, apply_status, status_stacks, crit_chance, crit_multiplier)` (`:69`) is the configuration surface. `weapon_controller.gd` passes crit from `CombatStatModifiers.crit_chance`; enemy callers pass five arguments (crit defaults to 0).

### Overlap detection

Two paths feed `_try_hit`:

1. Godot's own `area_entered` signal.
2. `_scan_overlaps()` (`:95`), run every physics frame while active. It builds a `PhysicsShapeQueryParameters3D` from the collision shape's global transform and `collision_mask`, with `collide_with_areas = true`, `collide_with_bodies = false`, excluding its own RID, and calls `space.intersect_shape(params, 16)` — a hard cap of 16 results per frame. It counts results into `_last_overlap_count` (exposed via `get_last_overlap_count()`) and calls `_try_hit` on each `Area3D`.

There is no swept or continuous test; each frame samples the shape at its current transform.

### `_try_hit` filters

`_try_hit(area)` (`:116`) rejects in this order:

1. Not active, or the area is itself.
2. The area has no `receive_hit` method.
3. `area.get("team") == team` — same-team hits are dropped. Teams are the strings `"player"`, `"enemy"` and `"trap"`.
4. `_is_cross_boss_boundary(area)` — asks the node in the `castle_run` group whether attacker and target are on opposite sides of a boss boundary.
5. `_has_clear_line_to(area)` — see below.
6. `_hit_times` per-target dedup with optional `rehit_interval` (`:133-139`) — when `rehit_interval > 0`, the same target can be hit again after the interval elapses.

On acceptance it records the hit time, computes `direction`, rolls crit (`final_damage *= _crit_multiplier` when `randf() < _crit_chance`), builds `DamageInfo` with `info.crit`, calls `area.receive_hit(info)`, then plays VFX and `HitFeedback.on_hit`.

`on_hit` receives `damage_amount` — the pre-crit, pre-mitigation configured value — not `final_damage` and not what the hurtbox actually applied.

### Line of sight

`_has_clear_line_to(target)` (`:182`) raycasts from the hitbox's collision shape center to the target's `CollisionShape3D` center (falling back to area origins), with both endpoints' Y clamped up to `MIN_LOS_HEIGHT := 0.75` so downward melee angles do not false-block on the floor. `collision_mask = WORLD_COLLISION_MASK := 1`, bodies only, excluding the attacker body and the target's parent when both are `CollisionObject3D`. Any hit means the swing is cancelled for that target.

### Hurtbox

Covered in detail in [`combat-core.md`](combat-core.md). `receive_hit` builds a `DamageResolution`, emits `hit_resolved` at every exit, and lazy-creates a `StatusController` on the victim body when status application is needed (`hurtbox.gd:275-293`). `@export region` and `region_damage_mult` / `region_poise_mult` support per-region multipliers.

`damaged.emit(info)` (`hurtbox.gd:132`) still passes the original unmitigated `DamageInfo`. `castle_enemy_base.gd` also listens to `hit_resolved` for flinch when `outgoing > 0`.

`ShieldHurtbox` (`shield_hurtbox.gd`) is the only subclass; see [`guard.md`](guard.md).

### Collision layers

From `player.tscn` and `castle_grunt.tscn`:

| Node | `collision_layer` | `collision_mask` |
|------|-------------------|------------------|
| World geometry | 1 | — |
| `Player` / enemy `CharacterBody3D` | 2 | — |
| `Hitbox` (both teams) | 4 | 8 |
| `Hurtbox` (both teams) | 8 | 4 |

Both teams share layers 4 and 8; separation is entirely by the `team` string comparison at `hitbox.gd:121`.

### Debug drawing

`CombatCollisionDebug.set_debug_draw(area, enabled, color)` (`combat_collision_debug.gd:9`) looks for a `DebugDraw` `MeshInstance3D` child, creates one on first use from the area's `CollisionShape3D` (box, capsule, sphere, or `shape.get_debug_mesh()`), scales it by `DEBUG_SCALE := Vector3(1.05, 1.05, 1.05)`, applies an unshaded emissive material with `no_depth_test = true` and `cull_mode = CULL_DISABLED`, then toggles `visible`.

The mesh is built once from the shape's dimensions at creation time and never rebuilt. `HITBOX_COLOR` is red, `HURTBOX_COLOR` is blue. Both `Hitbox` and `Hurtbox` call it with `false` in `_ready()`, which creates the mesh eagerly. `debug_overlay.gd:178-185` toggles every node in the `combat_hitbox` and `combat_hurtbox` groups.

### AttackTokenService

Autoload (`project.godot:52`). `DEFAULT_MAX_TOKENS := 2`. `request_token(group_id, max_tokens)` increments a per-group counter and returns false at the cap; `release_token(group_id)` decrements or erases; `reset_group` and `reset_all` clear state.

`castle_enemy_base.gd:613` requests a token in `_start_windup` keyed on `_data.attack_token_group` (default `"room_default"`) and returns without attacking if refused. `_release_attack_token()` (`:688`) is called from `_start_attack` when the enemy died mid-windup (`:637`) and from `_end_attack` (`:664`). `reset_group()` and `reset_all()` have no callers anywhere under `apps/`.

## Contracts

- **Groups:** `combat_hitbox`, `combat_hurtbox` — used by `debug_overlay.gd:178-185`.
- **Duck-typed target contract:** any `Area3D` with a `receive_hit(DamageInfo)` method and a `team` property is a valid hit target. This is how `trap_damage_area.gd:22-33` delivers damage without knowing about `Hurtbox`.
- **Node name:** the hitbox's `CollisionShape3D` child must be named exactly `CollisionShape3D` (`hitbox.gd:25`, `combat_collision_debug.gd:20`, `hitbox.gd:190`).
- **Scene contract:** the hitbox must descend from a `CharacterBody3D` for `_owner_node` to be the attacker; otherwise it falls back to the direct parent.
- **Team strings:** `"player"`, `"enemy"`, `"trap"`.
- **Signals:** `Hurtbox.damaged(info)`.
- **Autoloads used:** `VfxService`, `AttackTokenService`.
- **Group lookup:** `castle_run` for `is_cross_boss_boundary`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Shape-query overlap scan with team, LOS and boss-boundary filters | IMPLEMENTED | `hitbox.gd:100-130` |
| Per-target dedup with optional `rehit_interval` | IMPLEMENTED | `hitbox.gd:133-139`, `@export rehit_interval` |
| Crit from player talents/equipment | IMPLEMENTED | `weapon_controller.gd:477-479`, `hitbox.gd:146-148` |
| Lazy `StatusController` on enemies | IMPLEMENTED | `hurtbox.gd:275-293` |
| `hit_resolved` + `DamageResolution` pipeline | IMPLEMENTED | `hurtbox.gd:43-132`, `damage_resolution.gd` |
| Debug draw for both box types | IMPLEMENTED | `combat_collision_debug.gd` |
| `AttackTokenService` concurrency cap | IMPLEMENTED | `attack_token_service.gd`, `castle_enemy_base.gd` |
| `damaged` signal payload | PARTIAL | Still emits pre-mitigation `info`; use `hit_resolved.outgoing` for applied damage |
| Debug mesh tracking shape changes | PARTIAL | Mesh built once at `_ready()`; archetype resizes not reflected |
| `AttackTokenService.reset_group` / `reset_all` | STUB | No callers — token leak if enemy freed mid-windup |
| Swept / continuous collision | ABSENT | Per-frame shape sample only |
| Hurtbox hit regions (head, limbs) | PARTIAL | `@export region` exists; no per-enemy scene authoring yet |

## Related

- Improvement plan: [`../actual_improvements/hit-hurtboxes.md`](../actual_improvements/hit-hurtboxes.md) — **FINISHED**
- [`combat-core.md`](combat-core.md) — the `receive_hit` mitigation chain in full
- [`weapons.md`](weapons.md) — `set_attack_values` caller and hitbox sizing
- [`hit-feedback.md`](hit-feedback.md) — `HitFeedback.on_hit` caller
- [`guard.md`](guard.md) — `ShieldHurtbox`
- [`statuses-and-buffs.md`](statuses-and-buffs.md) — the dropped status delivery
- [`combat-hazards.md`](combat-hazards.md) — `trap_damage_area`, `poison_hazard`
- [`enemies.md`](enemies.md) — `AttackTokenService` consumer
- [`debug-arenas.md`](debug-arenas.md) — debug draw toggles
