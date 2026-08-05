# Guard

Hold-to-block with a parry window at the start of each press, plus a riposte payoff. `Guard` is player-only and on the live play path (`player.tscn:80`). `ShieldHurtbox` is a separate, unrelated mitigation used by shield enemies.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/combat/guard.gd` | `Guard` node: state machine, block math, parry, riposte |
| `apps/game/client/scripts/combat/shield_hurtbox.gd` | `Hurtbox` subclass used by shield enemies; flat frontal mitigation |

## How it works

### State machine

`guard.gd` is a `Node` with `GuardState { IDLE, GUARDING, GUARD_BROKEN }`. Constants:

| Constant | Value |
|----------|-------|
| `BLOCK_STAMINA_DRAIN_PER_HIT` | 18.0 |
| `BLOCK_DAMAGE_REDUCTION` | 0.22 |
| `GUARD_BREAK_STAGGER` | 0.8 s |
| `BLOCK_ARC_DEGREES` | 120.0 (60 deg half-arc) |
| `PARRY_WINDOW` | 0.18 s |
| `PARRY_STAGGER_ENEMY` | 1.2 s |
| `RIPOSTE_WINDOW` | 1.4 s |
| `RIPOSTE_DAMAGE_MULT` | 2.0 |

`_physics_process(delta)` (`:46`) runs a stagger timer first — while `_stagger_timer > 0.0` the node forces `IDLE` and returns, so a guard-broken player cannot re-guard for 0.8 s. Otherwise it ticks the riposte timer, then switches on state: `IDLE` waits for `block` to be *just pressed*, `GUARDING` counts the parry timer down and drops guard when `block` is released.

`_enter_guard()` sets `_parry_timer = PARRY_WINDOW` and emits `block_state_changed(true)`. Because the parry timer is only armed on a fresh press, holding block indefinitely gives one 0.18 s parry window and none afterward.

### Blocking

`Hurtbox.receive_hit` calls `modify_incoming_hit(info)` (`guard.gd:101`) for every hit that survives i-frames and parry:

1. Returns the hit unchanged if `_stagger_timer > 0.0` or `is_guard_active` is false.
2. Returns unchanged if `_is_frontal_hit(info.direction)` is false. Frontality is `rad_to_deg(facing.angle_to(-direction.normalized())) <= 60.0` where facing comes from `_body.get_facing_direction()` — for the player that is `Facing.global_transform.basis.z` (`locomotion.gd:167-170`), which does rotate.
3. Calls `_stamina.consume(BLOCK_STAMINA_DRAIN_PER_HIT)`. If it fails (or `Stamina` is missing) it calls `_trigger_guard_break()` and returns the hit at **full** damage with `blocked: false`.
4. Otherwise returns `amount * (1.0 - clampf(0.22 + blockReduction_talent, 0.0, 0.95))`, `poise * 0.5`, and `blocked: true`.

`_trigger_guard_break()` (`:176`) sets `guard_broken_state`, forces `GUARD_BROKEN`, resets the guard, sets `_stagger_timer = 0.8`, drains poise to zero via `_poise.take_poise_damage(_poise.max_poise)` and emits `guard_broken` plus `block_state_changed(false)`.

### Parry and riposte

`try_parry_attack(attacker)` (`:117`) is called by `Hurtbox.receive_hit` *before* the block path, and only succeeds while `_state == GUARDING and parry_window_active`. On success it emits `parry_success(attacker)`, sets `riposte_active` with `_riposte_timer = 1.4 s`, emits `riposte_ready`, plays `VfxService.play_parry` and `play_impact_decal` at the combat anchor, and ends the guard. The hit is fully negated because `receive_hit` returns immediately.

`get_riposte_damage_multiplier()` returns 2.0 while riposte is live. `WeaponController._enable_hitbox_for_attack()` (`weapon_controller.gd:341-346`) reads it, multiplies both damage and poise damage by it, and calls `consume_riposte()`.

`get_parry_stagger_duration()` (`:142`) returns `PARRY_STAGGER_ENEMY := 1.2` and has no caller anywhere under `apps/`.

### HUD queries

`combat_hud.gd:428-431` reads `get_parry_time_remaining()` and `get_block_time_remaining()`. The first returns the live `_parry_timer` while the window is open. The second returns the literal `1.0` whenever the state is `GUARDING` and `0.0` otherwise (`guard.gd:156-159`) — it is a boolean dressed as a duration.

### Stat modifiers

`set_combat_stat_modifiers(_equipment_stats, talent_stats)` (`:97`) stores only `CombatStatModifiers.block_reduction_bonus(talent_stats)`, i.e. the talent `blockReduction` key. It is called from `inventory_service.gd:210-211`. Equipment stats are accepted and ignored.

### Interaction with attacks

`WeaponController._is_action_blocked()` (`weapon_controller.gd:568`) returns true while `Guard.is_guard_active`, so no attack input is read at all while blocking. Guard cannot be attack-cancelled; the player must release `block` first.

`Guard.locks_movement()` returns true only during the 0.8 s guard-break stagger, so blocking does not slow movement.

### ShieldHurtbox

`shield_hurtbox.gd` extends `Hurtbox` and overrides `receive_hit`. Two `@export`s: `block_mitigation := 0.75`, `block_angle_deg := 100.0`. If the incoming `direction` is within a 50 deg half-arc of the owner body's `-basis.z`, it rebuilds a `DamageInfo` with `amount` and `poise_damage` both multiplied by `0.25` and forwards it to `super.receive_hit`. Note the rebuild drops `status_id` and `status_stacks` — `DamageInfo.create` is called with five arguments (`shield_hurtbox.gd:18-24`), so a status-carrying hit loses its status when it lands on a shield.

There is no stamina, no break, no timer and no state: a shield enemy mitigates 75% frontally forever.

## Contracts

- **Node name:** must be a child of the player `CharacterBody3D` named exactly `Guard`. `Hurtbox._find_guard()` (`hurtbox.gd:98-105`) walks ancestors looking for that literal name; `WeaponController` (`:81`), `PlayerCombatReactions` (`:29`) and `HitFeedback` (`:35`) each resolve it the same way.
- **Sibling nodes required:** `Stamina`, `Poise`.
- **Duck-typed methods consumed by `Hurtbox`:** `try_parry_attack(Node) -> bool`, `modify_incoming_hit(DamageInfo) -> Dictionary` with keys `amount`, `poise`, `blocked`.
- **Signals:** `guard_broken`, `block_state_changed(blocking)`, `parry_success(target)`, `riposte_ready`. Consumers: `player_combat_reactions.gd:35-38`, `hit_feedback.gd:36-37`.
- **Public state read by others:** `is_guard_active` (`weapon_controller.gd:568`), `is_blocking`, `parry_window_active`, `riposte_active`.
- **Input action:** `block` (keyboard Q, gamepad LT per the file header comment).
- **Autoloads used:** `VfxService`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Hold-to-block state machine | IMPLEMENTED | `guard.gd:46-94` |
| Parry window and full negation | IMPLEMENTED | `guard.gd:117-130`, `hurtbox.gd:41-43` |
| Riposte 2.0x multiplier | IMPLEMENTED | `guard.gd:133-139`, `weapon_controller.gd:341-346` |
| Guard break on insufficient stamina | IMPLEMENTED | `guard.gd:106-108,176-184` |
| Block damage reduction | PARTIAL | `guard.gd:9` — a flat 22% for every weapon and every attack; blocking a 20-damage hit still costs 15.6 HP and 18 stamina |
| Block stamina cost | PARTIAL | `guard.gd:8` — a flat 18.0 per hit regardless of the attack's damage, poise damage or weight |
| Parry staggering the attacker | STUB | `get_parry_stagger_duration()` (`guard.gd:142-143`) has no caller under `apps/`; `parry_success` reaches only a mesh pulse (`player_combat_reactions.gd:107-108`) and a "PARRIED" label (`hit_feedback.gd:80-85`) |
| `get_block_time_remaining()` | FAKE | `guard.gd:156-159` returns the literal `1.0`; `combat_hud.gd:430-431` treats it as a duration |
| Parry re-arm while holding block | ABSENT | `_parry_timer` is set only in `_enter_guard()` (`guard.gd:79`), which requires a fresh `is_action_just_pressed` |
| Shield or weapon stability data | ABSENT | No `block_*` keys in `content/schemas/weapon-definition.v1.json` or `content/schemas/item-catalog.v1.json`; all guard numbers are GDScript constants |
| Guard movement penalty | ABSENT | `locks_movement()` (`guard.gd:146-147`) is true only during guard-break stagger |
| Shield bash or guard-cancel attack | ABSENT | `weapon_controller.gd:568` blocks all attack input while `is_guard_active` |
| Equipment stats reaching guard | PARTIAL | `guard.gd:97-98` accepts `equipment_stats` and reads only the talent `blockReduction` |
| Enemy guard | ABSENT | No enemy scene mounts a `Guard` node; `shield_hurtbox.gd` is the only enemy mitigation |
| `ShieldHurtbox` | PARTIAL | `shield_hurtbox.gd:5` — flat 75% frontal mitigation with no stamina, no break, no timer; `:18-24` drops `status_id` and `status_stacks` from the rebuilt `DamageInfo` |

## Related

- Improvement plan: [`../actual_improvements/guard.md`](../actual_improvements/guard.md)
- [`combat-core.md`](combat-core.md) — where `modify_incoming_hit` and `try_parry_attack` are called
- [`stamina-mana.md`](stamina-mana.md) — the 18.0 per-hit drain
- [`weapons.md`](weapons.md) — riposte multiplier consumer, attack input blocking
- [`hit-hurtboxes.md`](hit-hurtboxes.md) — `ShieldHurtbox` base class
- [`hit-feedback.md`](hit-feedback.md) — "BLOCKED" and "PARRIED" labels
- [`enemies.md`](enemies.md) — shield enemy behavior
- [`player-combat-reactions.md`](player-combat-reactions.md)
