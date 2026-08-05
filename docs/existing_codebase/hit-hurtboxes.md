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

`set_attack_values(damage, poise, dmg_type, apply_status, status_stacks, crit_chance)` (`:66`) is the whole configuration surface. All three callers pass five arguments: `weapon_controller.gd:350`, `castle_enemy_base.gd:643-649`, `enemy_projectile.gd:31`. The sixth parameter therefore keeps its `0.0` default.

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
6. `target_id in _hit_targets` — one hit per target per swing.

On acceptance it appends the instance id, computes `direction = (area.global_position - _owner_node.global_position).normalized()`, rolls a crit (`final_damage *= 1.5` when `randf() < _crit_chance`, which is never true because `_crit_chance` is always 0.0), builds the `DamageInfo`, calls `area.receive_hit(info)`, plays `VfxService.play_hit_spark` at the target parent's position +1 m, and calls `HitFeedback.on_hit(area.get_parent(), damage_amount, direction)` on the **attacker's** `HitFeedback` child if it has one.

`on_hit` receives `damage_amount` — the pre-crit, pre-mitigation configured value — not `final_damage` and not what the hurtbox actually applied.

### Line of sight

`_has_clear_line_to(target)` (`:182`) raycasts from the hitbox's collision shape center to the target's `CollisionShape3D` center (falling back to area origins), with both endpoints' Y clamped up to `MIN_LOS_HEIGHT := 0.75` so downward melee angles do not false-block on the floor. `collision_mask = WORLD_COLLISION_MASK := 1`, bodies only, excluding the attacker body and the target's parent when both are `CollisionObject3D`. Any hit means the swing is cancelled for that target.

### Hurtbox

Covered in detail in [`combat-core.md`](combat-core.md). Structurally: an `Area3D` in the `combat_hurtbox` group with `monitorable = true`, three `@export`s (`team`, `health_path`, `poise_path`), one signal (`damaged(info)`), and ancestor-walking lookups for `Guard`, `Dodge`, `StatusController`, `HitFeedback` and the owning `CharacterBody3D`.

`damaged.emit(info)` (`hurtbox.gd:61`) passes the original, unmitigated `DamageInfo`. Consumers: `castle_enemy_base.gd:79` → `_on_hurt` plays a flinch animation or a mesh pulse; `training_grunt.gd:70` → same; `final_boss_forgotten_castle.gd:50` overrides `_on_hurt` to skip the flinch while immune — the health damage has already been applied by that point.

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
| Shape-query overlap scan with team, LOS and boss-boundary filters | IMPLEMENTED | `hitbox.gd:95-130` |
| One hit per target per swing | IMPLEMENTED | `hitbox.gd:127-130,62-63` |
| Debug draw for both box types | IMPLEMENTED | `combat_collision_debug.gd`, `debug_overlay.gd:178-185` |
| `AttackTokenService` concurrency cap | IMPLEMENTED | `attack_token_service.gd`, `castle_enemy_base.gd:613,664` |
| Status delivery to enemies | BROKEN | `hurtbox.gd:165` requires a child node named `StatusController`; no enemy scene under `apps/game/client/scenes/enemies/` has one — only `player.tscn:89` does. Every player-applied status (e.g. `content/weapons/dagger.json:18` `"status": "bleed"`) is silently dropped |
| `damaged` signal payload | BROKEN | `hurtbox.gd:61` emits the pre-mitigation `info`, so `_on_hurt` flinches on hits that dealt 0 damage after blocking |
| Crit parameter on `set_attack_values` | STUB | `hitbox.gd:72` — the sixth parameter is never passed by any of the three callers (`weapon_controller.gd:350`, `castle_enemy_base.gd:643`, `enemy_projectile.gd:31`), so `hitbox.gd:135` never fires |
| Multi-hit / sustained hitboxes | ABSENT | `_hit_targets` is cleared only by `reset_swing()`; there is no per-target re-hit interval. `trap_damage_area.gd:9,28-30` maintains its own `hit_interval` dictionary for exactly this reason |
| Swept / continuous collision | ABSENT | `hitbox.gd:95-113` samples the shape once per physics frame at its current transform |
| Overlap result cap | PARTIAL | `hitbox.gd:109` — `intersect_shape(params, 16)` silently drops the 17th and later overlaps in a frame |
| Line-of-sight accuracy | PARTIAL | `hitbox.gd:194-196` clamps both endpoints to `y >= 0.75`, and the test runs center-to-center, so a waist-high prop between two centers cancels an otherwise legal hit |
| Debug mesh tracking shape changes | BROKEN | `combat_collision_debug.gd:16` only toggles `visible`; the mesh is built once at `_ready()` from the then-current size, so `WeaponController._apply_hitbox_profile()` archetype resizes (`weapon_controller.gd:531-561`) are never reflected |
| `_owner_node` freshness | PARTIAL | `hitbox.gd:32` resolves it once in `_ready()`; `enemy_pool.gd` reuse or reparenting keeps the stale owner. `set_combat_owner()` (`:82`) exists as the override but has one caller, `enemy_projectile.gd:30` |
| `AttackTokenService.reset_group` / `reset_all` | STUB | `attack_token_service.gd:26,30` — no callers, so a token held by an enemy freed outside `_end_attack` leaks for the lifetime of the run |
| Hurtbox hit regions (head, limbs) | ABSENT | One box per character; no per-region multiplier data anywhere under `content/` |

## Related

- Improvement plan: [`../actual_improvements/hit-hurtboxes.md`](../actual_improvements/hit-hurtboxes.md)
- [`combat-core.md`](combat-core.md) — the `receive_hit` mitigation chain in full
- [`weapons.md`](weapons.md) — `set_attack_values` caller and hitbox sizing
- [`hit-feedback.md`](hit-feedback.md) — `HitFeedback.on_hit` caller
- [`guard.md`](guard.md) — `ShieldHurtbox`
- [`statuses-and-buffs.md`](statuses-and-buffs.md) — the dropped status delivery
- [`combat-hazards.md`](combat-hazards.md) — `trap_damage_area`, `poison_hazard`
- [`enemies.md`](enemies.md) — `AttackTokenService` consumer
- [`debug-arenas.md`](debug-arenas.md) — debug draw toggles
