# Hitboxes and hurtboxes — improvement plan

## Status: FINISHED

## Current state

The `Hitbox` / `Hurtbox` pair does real work: a per-frame shape query, a team filter, a line-of-sight raycast, a boss-boundary check and per-swing target deduplication (see [`../existing_codebase/hit-hurtboxes.md`](../existing_codebase/hit-hurtboxes.md)). Two things it delivers are wrong. Statuses never arrive: `Hurtbox._apply_status_from_hit` requires a child node named `StatusController` and no enemy scene has one, so the dagger's authored `bleed` and every enemy-facing status is dropped without a warning. And the `damaged` signal carries the *pre-mitigation* `DamageInfo`, so enemies flinch on hits that were fully blocked and no listener can know what actually landed. Beyond that, the crit parameter is dead, sustained hitboxes are impossible, and the debug draw shows a shape that no longer matches the one being queried.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| HTB-01 | P0 | Enemies cannot receive statuses — `_apply_status_from_hit` needs a `StatusController` child and no enemy scene has one | `hurtbox.gd:159-167`; `StatusController` appears in exactly one scene, `player.tscn:89`; authored but undeliverable at `content/weapons/dagger.json:6,18,28,38,50` |
| HTB-02 | P0 | `damaged` emits the unmitigated `info`, so listeners flinch on 0-damage hits and cannot read the applied amount | `hurtbox.gd:61`, `castle_enemy_base.gd:79,748-758`, `final_boss_forgotten_castle.gd:50-53` |
| HTB-03 | P1 | The crit parameter of `set_attack_values` is never passed by any of the three callers | `hitbox.gd:66-79,135`, `weapon_controller.gd:350`, `castle_enemy_base.gd:643-649`, `enemy_projectile.gd:31` |
| HTB-04 | P1 | No sustained or multi-hit hitbox: `_hit_targets` clears only on `reset_swing()`, forcing every recurring damage source to reimplement a cooldown | `hitbox.gd:62-63,127-130`, `trap_damage_area.gd:9,28-30` |
| HTB-05 | P1 | The debug draw never rebuilds its mesh, so it shows the sword box while a greatsword box is being queried | `combat_collision_debug.gd:10-16`, `weapon_controller.gd:531-561` |
| HTB-06 | P1 | Line of sight is a single center-to-center ray with both endpoints clamped to `y >= 0.75`, so waist-high props cancel legal hits and low targets are mis-tested | `hitbox.gd:182-208` |
| HTB-07 | P1 | `AttackTokenService.reset_group` / `reset_all` have no callers, so a token held by an enemy freed outside `_end_attack` leaks for the run | `attack_token_service.gd:26,30`, `castle_enemy_base.gd:637,664,688` |
| HTB-08 | P2 | `intersect_shape(params, 16)` silently drops overlaps past the 16th in a frame | `hitbox.gd:109` |
| HTB-09 | P2 | `_owner_node` is resolved once in `_ready()` and goes stale on pooled or reparented enemies; `set_combat_owner` exists but has one caller | `hitbox.gd:32,82`, `enemy_projectile.gd:30` |
| HTB-10 | P2 | One hurtbox per character — no head, limb or weak-point regions, and no per-region multiplier data | `player.tscn:118-128`, `castle_grunt.tscn:66-75`; no region key in `content/schemas/enemy-definition.v1.json` |
| HTB-11 | P2 | Team separation is a string compare on shared collision layers 4 and 8, so the physics engine does work the filter then throws away | `hitbox.gd:121`, `player.tscn:56-57,120-121`, `castle_grunt.tscn:57-58,67-68` |

## Target design

### 1. Statuses reach everything that can be hurt

`Hurtbox` stops requiring a pre-authored node. It resolves or creates the controller on demand:

```gdscript
func _resolve_status_controller() -> StatusController:
    var body := _find_character_body()
    if body == null:
        return null
    var ctrl := body.get_node_or_null("StatusController") as StatusController
    if ctrl:
        return ctrl
    if _health == null:
        return null
    ctrl = StatusController.new()
    ctrl.name = "StatusController"
    ctrl.team = team
    body.add_child(ctrl)
    ctrl.set_health(_health)   # new setter; health_path cannot be resolved post-hoc
    return ctrl
```

Lazy creation is chosen over editing 36 enemy scenes because it also covers runtime-spawned bodies (`enemy_pool.gd`, boss adds) and future enemy scenes without a checklist step. `StatusController` gains `set_health(Health)` since its current `health_path` export is only read in `_ready()` (`status_controller.gd:17-19`).

A validation assertion (below) then guarantees every enemy scene ends up with one after its first hit, so the lazy path is verified rather than assumed.

### 2. `hit_resolved` replaces `damaged` for anything that needs the truth

This is the same `DamageResolution` introduced in [`combat-core.md`](combat-core.md). `Hurtbox` emits both signals during a deprecation window:

```gdscript
signal damaged(info: DamageInfo)                   # deprecated
signal hit_resolved(resolution: DamageResolution)
```

Migration targets, all of which currently take `_info` and ignore it:

| Consumer | Today | Target |
|----------|-------|--------|
| `castle_enemy_base.gd:748` | flinch on any `damaged` | flinch only when `res.outgoing > 0.0`; use `res.blocked` for a shield-spark reaction instead |
| `training_grunt.gd:240` | same | same |
| `final_boss_forgotten_castle.gd:50` | skip flinch while immune | check immunity in `receive_hit` so the damage is actually prevented, not just the flinch |

`damaged` is removed once all three are migrated.

### 3. Hitboxes that can stay out

Add an optional re-hit interval so one mechanism covers swings, beams, auras and traps:

```gdscript
@export var rehit_interval := 0.0   # 0.0 = one hit per target per swing (today's behavior)

var _hit_times: Dictionary = {}     # instance_id -> seconds since enable()
```

`_try_hit` checks `_hit_times` instead of the `_hit_targets` array: a target is eligible when it is absent, or when `rehit_interval > 0.0` and `now - _hit_times[id] >= rehit_interval`. `reset_swing()` clears the dictionary. With `rehit_interval` left at its default the behavior is bit-for-bit what ships today.

`trap_damage_area.gd` then deletes its private `_cooldowns` dictionary and sets `rehit_interval = hit_interval` on a real `Hitbox`, which also gets it team filtering, line of sight and boss-boundary handling for free. The multi-hit `hits` array from [`weapons.md`](weapons.md) uses `reset_swing()` per window rather than `rehit_interval`, since those hits are authored rather than periodic.

### 4. Line of sight that does not lie

Replace the single clamped center-to-center ray with a three-ray fan sampled across the target's collision shape, and drop the `MIN_LOS_HEIGHT` hack:

```gdscript
const LOS_SAMPLE_HEIGHTS: Array[float] = [0.25, 0.55, 0.85]   # fractions of the target shape height
const LOS_REQUIRED_CLEAR := 1                                  # one clear ray is enough
```

Rays originate from the attacker body's chest (`_owner_node.global_position + Vector3.UP * 1.0`) rather than the hitbox center, because the hitbox may already be inside the obstructing prop. A hit is legal if at least one ray is clear. This fixes both failure modes: a waist-high crate no longer cancels a hit on a standing target, and a genuinely walled-off target still fails all three.

`WORLD_COLLISION_MASK := 1` is kept, so props that should not block must not be on layer 1 — that is already the existing convention.

### 5. Hit regions

Give hurtboxes an optional damage multiplier and a region name so a head shot reads differently from a body shot:

```gdscript
# hurtbox.gd
@export var region: String = "body"        # "body" | "head" | "limb" | "weakpoint"
@export var region_damage_mult := 1.0
@export var region_poise_mult := 1.0
```

`receive_hit` applies both immediately after the arc multiplier from [`combat-core.md`](combat-core.md), and writes `res.region` so feedback can differentiate. Enemy definitions declare which regions their scene provides:

```json
"hurt_regions": [
  { "name": "body", "damage_mult": 1.0, "poise_mult": 1.0 },
  { "name": "head", "damage_mult": 1.6, "poise_mult": 1.4 }
]
```

Rollout is per-enemy: any scene without extra hurtbox nodes behaves exactly as today. Start with the three bosses and `castle_knight`, where a weak point is a legible mechanic.

### 6. Collision layers that do the filtering

Split the shared layers so the physics engine stops reporting overlaps the script immediately discards:

| Layer bit | Meaning |
|-----------|---------|
| 1 | World |
| 2 | Characters |
| 3 | Player hitbox |
| 4 | Player hurtbox |
| 5 | Enemy hitbox |
| 6 | Enemy hurtbox |
| 7 | Trap hitbox |

Player hitbox masks 6 and, for friendly-fire traps, 7. Enemy hitbox masks 4. The `team` string check stays as a defensive assertion — it becomes a `push_warning` when it ever fires, which would indicate a mis-authored scene.

### 7. Owner freshness and token hygiene

- `Hitbox` re-resolves `_owner_node` in `_notification(NOTIFICATION_PARENTED)` as well as `_ready()`, and `enable()` re-resolves it when `_owner_node` is no longer `is_instance_valid`.
- `CastleRun` calls `AttackTokenService.reset_group(group_id)` on room clear and `reset_all()` on floor transition and run end, mirroring the four `RunBuffs.clear_all()` sites in `run_flow.gd`.
- `castle_enemy_base._finalize_death()` calls `_release_attack_token()` unconditionally.

### 8. Debug draw that matches reality

`CombatCollisionDebug.set_debug_draw` compares the cached mesh's dimensions against the current shape and rebuilds when they differ. `Hitbox` and `Hurtbox` stop calling it in `_ready()` — creating the mesh eagerly for every combat area in every scene is wasted allocation — and instead create it on first `set_debug_draw(true)`.

Add a `_last_overlap_count` readout to the debug overlay so the 16-result cap is observable; raise the cap to `MAX_OVERLAP_RESULTS := 32` and `push_warning` when a frame saturates it.

## Work plan

1. **Lazy `StatusController`** — `Hurtbox._resolve_status_controller()`, `StatusController.set_health()`. Closes the single biggest silent-drop in combat. (HTB-01)
2. **`hit_resolved` migration** — emit alongside `damaged`, migrate the three `_on_hurt` consumers, move `final_boss_forgotten_castle` immunity into `receive_hit`, then delete `damaged`. (HTB-02)
3. **Pass crit chance** — the sixth argument from `weapon_controller.gd` and `castle_enemy_base.gd`. Shared with [`weapons.md`](weapons.md) step 3 and [`combat-core.md`](combat-core.md) step 3. (HTB-03)
4. **`rehit_interval`** — `_hit_times` dictionary in `hitbox.gd`, then convert `trap_damage_area.gd` to use a real `Hitbox`. (HTB-04)
5. **Token hygiene** — `reset_group` / `reset_all` call sites in `castle_run.gd` and `run_flow.gd`; unconditional release in `_finalize_death`. (HTB-07)
6. **Line-of-sight fan** — `LOS_SAMPLE_HEIGHTS`, chest-origin rays, remove `MIN_LOS_HEIGHT`. (HTB-06)
7. **Debug draw rebuild** — dimension comparison and lazy creation; raise the overlap cap and warn on saturation. (HTB-05, HTB-08)
8. **Owner freshness** — re-resolve on reparent and on `enable()`. (HTB-09)
9. **Hit regions** — `region` exports, `hurt_regions` schema key, extra hurtbox nodes on three bosses and `castle_knight`. (HTB-10)
10. **Layer split** — renumber layers across `player.tscn`, all 36 enemy scenes, `enemy_projectile.tscn` and trap scenes in one commit; downgrade the team check to a warning. (HTB-11)

Steps 1-3 are the ones that change observable combat. Step 10 touches the most files and should land last, behind a validation assertion that every hitbox/hurtbox pair still resolves.

## Data and schema changes

| Change | File |
|--------|------|
| `hurt_regions`: array of `{ name (string), damage_mult (number, min 0), poise_mult (number, min 0) }` | `content/schemas/enemy-definition.v1.json` |
| `attack_token_group` documented as an optional string (already read at `castle_enemy_base.gd:612`, currently undeclared) | `content/schemas/enemy-definition.v1.json` |
| `attack_token_max` (integer, min 1) so a boss room can raise the concurrency cap above `DEFAULT_MAX_TOKENS := 2` | `content/schemas/enemy-definition.v1.json` |

No save-format change; `save_migrator.gd` `CURRENT_VERSION` stays at 4. The layer renumbering is scene data, not content, and needs no schema work.

## Acceptance criteria

- [ ] Hitting a `castle_grunt` with the `dagger` equipped applies `bleed` and the enemy loses HP over time. (HTB-01)
- [ ] Every enemy scene under `apps/game/client/scenes/enemies/` has a working `StatusController` after taking one hit. (HTB-01)
- [ ] A fully blocked hit does not trigger the enemy flinch animation. (HTB-02)
- [ ] `hit_resolved.outgoing` equals the HP actually removed, for blocked, backstabbed, resisted and crit hits alike. (HTB-02)
- [ ] With `critChance` at 1.0, every hit reports `res.crit`. (HTB-03)
- [ ] A hitbox with `rehit_interval: 0.5` left enabled for 2.0 s hits a stationary target exactly 4 times; with `rehit_interval: 0.0` it hits once. (HTB-04)
- [ ] Switching from `sword_basic` to `greatsword` with debug draw on visibly changes the drawn box. (HTB-05)
- [ ] A 0.9 m crate between the player and a standing `castle_grunt` does not cancel a melee hit; a full wall does. (HTB-06)
- [ ] `AttackTokenService._active_counts` is empty after a floor transition. (HTB-07)
- [ ] 20 enemies packed into one hitbox all receive the hit. (HTB-08)
- [ ] A pooled enemy reused after death attributes its hits to itself, not to its previous owner. (HTB-09)
- [ ] Hitting `castle_knight`'s head hurtbox deals 1.6x the damage of a body hit. (HTB-10)
- [ ] A player hitbox reports zero overlaps against another player-team hurtbox at the physics layer, with no `team` string rejection needed. (HTB-11)

## Validation

Extend `apps/game/client/scripts/validation/suites/combat_suite.gd`. `combat.hitbox_team_filter` (`combat_suite.gd:75-88`) currently asserts `hitbox.team == hurtbox.team` on two literals the test itself just assigned — it must be replaced with a real overlap test.

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `combat.status_reaches_enemy` | Load `dagger.json`, hit a `training_grunt`, assert its `StatusController.get_active_statuses()` contains `bleed` | HTB-01 |
| `combat.every_enemy_scene_takes_status` | For each `.tscn` under `scenes/enemies/`, instantiate, deliver a status-carrying `receive_hit`, assert an active status | HTB-01 |
| `combat.blocked_hit_no_flinch` | Force a full block, assert `_on_hurt` was not reached (spy on the animator or assert `res.outgoing == 0.0` and no flinch call) | HTB-02 |
| `combat.resolution_matches_health_delta` | For 10 randomized hits, assert `hit_resolved.outgoing` equals the observed `Health.current` delta | HTB-02 |
| `combat.crit_argument_forwarded` | Assert `Hitbox._crit_chance` is nonzero after `_enable_hitbox_for_attack` with `critChance` set | HTB-03 |
| `combat.rehit_interval` | Enable a hitbox with `rehit_interval = 0.5` over a stationary hurtbox for 2.0 s → 4 `hit_resolved` emissions; with 0.0 → 1 | HTB-04 |
| `combat.debug_mesh_tracks_shape` | Toggle debug draw, resize the shape via `_apply_hitbox_profile`, toggle again → `DebugDraw` mesh size equals the new shape size | HTB-05 |
| `combat.los_ignores_low_props` | Place a 0.9 m `StaticBody3D` on layer 1 between attacker and target → the hit lands; replace with a 3 m wall → it does not | HTB-06 |
| `combat.tokens_reset_on_floor_change` | Request 2 tokens, call `reset_all()`, assert `request_token` succeeds twice again | HTB-07 |
| `combat.overlap_cap` | 20 hurtboxes inside one hitbox → 20 `hit_resolved` emissions | HTB-08 |
| `combat.hitbox_team_filter_at_physics` | A player hitbox and a player hurtbox overlapping → `get_last_overlap_count() == 0` (not a string compare on two literals) | HTB-11 |
| `combat.region_multiplier` | Hit `castle_knight`'s head hurtbox and its body hurtbox with identical attacks → 1.6x ratio | HTB-10 |

## Related

- Current behavior: [`../existing_codebase/hit-hurtboxes.md`](../existing_codebase/hit-hurtboxes.md)
- [`combat-core.md`](combat-core.md) — `DamageResolution`, arc multipliers, the mitigation chain
- [`weapons.md`](weapons.md) — `set_attack_values` caller, multi-hit windows
- [`statuses-and-buffs.md`](statuses-and-buffs.md) — what HTB-01 unblocks
- [`hit-feedback.md`](hit-feedback.md) — `HitFeedback.on_hit` caller and the honest-number fix
- [`guard.md`](guard.md) — `ShieldHurtbox` subclass
- [`combat-hazards.md`](combat-hazards.md) — `trap_damage_area` conversion
- [`enemies.md`](enemies.md) — `_on_hurt` migration, token release on death
- [`combat-validation.md`](combat-validation.md), [`debug-arenas.md`](debug-arenas.md)
