# Guard — improvement plan

## Current state

The guard state machine, the 0.18 s parry window, the 2.0x riposte and the guard break on empty stamina all work end to end (see [`../existing_codebase/guard.md`](../existing_codebase/guard.md)). What does not work is the economics: blocking removes 22% of a hit and costs a flat 18 stamina, so blocking a 20-damage `frost_knight` swing still costs 15.6 HP *and* more than half a dodge, which makes blocking a strictly worse answer than rolling in every situation. Parrying is the correct answer and the game barely says so — `get_parry_stagger_duration()` returns 1.2 s and has no caller, so a successful parry negates the hit and leaves the attacker mid-swing instead of open. Every guard number is a GDScript constant; no shield, weapon or armor piece can express stability, and no enemy can be guard-broken because `ShieldHurtbox` is a flat 75% forever.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| GRD-01 | P0 | Parry does not stagger the attacker — `get_parry_stagger_duration()` has no caller, so the riposte window opens against an enemy that is still attacking | `guard.gd:142-143`; no match outside its own definition |
| GRD-02 | P0 | Blocking is dominated by dodging: 22% reduction for 18 stamina versus 100% negation for 32 stamina with a 0.25 s i-frame window | `guard.gd:8-9`, `dodge.gd:12,14-15` |
| GRD-03 | P0 | Every guard value is a hardcoded constant; shields, weapons and armor cannot carry stability, arc or reduction | `guard.gd:8-15`; no `block_*` key in `content/schemas/weapon-definition.v1.json` or `content/schemas/item-catalog.v1.json` |
| GRD-04 | P1 | `get_block_time_remaining()` returns the literal `1.0` and the HUD renders it as a duration | `guard.gd:156-159`, `combat_hud.gd:430-431` |
| GRD-05 | P1 | The parry window never re-arms while block is held, and there is no HUD affordance telling the player the window closed | `guard.gd:64,79` — `_parry_timer` is set only on `is_action_just_pressed` |
| GRD-06 | P1 | Guard cannot be cancelled into an attack and has no movement penalty, so holding block is free mobility with 22% mitigation | `weapon_controller.gd:568`, `guard.gd:146-147` |
| GRD-07 | P1 | `ShieldHurtbox` is unbreakable: 75% frontal mitigation with no stamina, no timer and no guard-break state | `shield_hurtbox.gd:5-27` |
| GRD-08 | P1 | `ShieldHurtbox` drops `status_id` and `status_stacks` when it rebuilds the `DamageInfo` | `shield_hurtbox.gd:18-24` — five-argument `DamageInfo.create` |
| GRD-09 | P2 | `set_combat_stat_modifiers` accepts `equipment_stats` and ignores it; only the talent `blockReduction` reaches guard | `guard.gd:97-98` |
| GRD-10 | P2 | The `Guard` node is found by literal node name from three separate files with no assertion that it exists | `hurtbox.gd:98-105`, `weapon_controller.gd:81`, `hit_feedback.gd:35` |

## Target design

### 1. Parry pays out

A parry must create the opening the riposte multiplier is priced for. On `try_parry_attack` success, `Guard` staggers the attacker:

```gdscript
func try_parry_attack(attacker: Node) -> bool:
    # ... existing window check ...
    _stagger_attacker(attacker)
```

`_stagger_attacker` calls, in order of preference: `attacker.apply_stagger(PARRY_STAGGER_ENEMY)` (already implemented on `castle_enemy_base`, exercised by `combat_suite.gd:194-195`), then `attacker.get_parent().apply_stagger(...)` when the attacker node is a hitbox rather than a body. `PARRY_STAGGER_ENEMY := 1.2` is kept; it is longer than the 1.4 s `RIPOSTE_WINDOW` minus a `sword_basic` light attack's 0.15 s startup, so the riposte lands inside the stagger with margin.

The attacker's in-flight attack is also cancelled: `_stagger_attacker` calls `attacker.cancel_attack()` if present, which disables the enemy hitbox and clears `_hit_targets`. Without this the parried swing continues and can still connect on a later frame.

### 2. Blocking becomes a real choice

Blocking should be the answer to pressure you cannot roll out of, and it should cost commitment rather than a flat tax. New model:

| Property | Today | Target | Source |
|----------|-------|--------|--------|
| Damage reduction | flat 0.22 | `block_reduction` from the equipped shield/weapon, default 0.55 | item data |
| Stamina cost | flat 18.0 | `incoming_poise_damage * BLOCK_STAMINA_PER_POISE` where `BLOCK_STAMINA_PER_POISE := 0.55`, divided by `block_stability` | derived |
| Poise transfer | flat 0.5x | `0.35x` scaled by `block_stability` | derived |
| Block arc | flat 120 deg | `block_arc_degrees` from item data, default 120 | item data |
| Movement while blocking | none | `BLOCK_MOVE_SPEED_MULT := 0.6` | constant |
| Regen while blocking | full | `RegenState.BLOCKING` trickle | [`stamina-mana.md`](stamina-mana.md) |

Worked example against a `castle_knight` swing (`attack_damage` 20, `attack_poise_damage` 17) with a default 1.0-stability shield at `block_reduction: 0.55`:

- Damage through: `20 * 0.45 = 9.0` HP, down from 15.6.
- Stamina: `17 * 0.55 = 9.35`, down from 18.0.
- Poise through: `17 * 0.35 = 5.95`, down from 8.5.

Against a `greatsword`-class heavy (poise damage 55) the same shield costs `30.25` stamina — nearly a full dodge — which is the correct pressure: you can block chip and you cannot block a committed heavy for free. This makes stamina cost track the attack's weight, which the flat 18.0 never could.

Rejected alternative: keep a flat cost and simply lower it. That fixes the dominance problem while leaving blocking equally correct against a dagger jab and a greatsword slam, which is the part that reads badly at play speed.

### 3. Guard cancel and shield bash

`WeaponController._is_action_blocked()` stops returning `true` for `is_guard_active`. Instead:

- `light_attack` while guarding performs a **shield bash**: `GUARD_BASH_STAMINA := 22.0`, 8 damage, `poise_damage: 28`, 0.12 s startup / 0.1 s active / 0.35 s recovery, and it applies `stun` x1 on hit. This gives the guard an offensive option and is the intended answer to a turtling shield enemy.
- `heavy_attack` while guarding drops guard and starts the heavy normally (a guard cancel) at the cost of `GUARD_CANCEL_STAMINA := 8.0`.

Both live on `Guard` as data-driven entries so a weapon without a shield can omit them.

### 4. Parry window that re-arms and reads

Two changes:

- `_parry_timer` re-arms whenever the guard has been held with no incoming hit for `PARRY_REARM_DELAY := 0.9` seconds. Holding block then becomes a rhythm rather than a one-shot, without letting a held button parry everything.
- `get_block_time_remaining()` returns the actual stamina headroom expressed as seconds of sustained blocking at the current incoming rate, or `INF` when nothing is incoming — and the HUD renders a *guard stability* bar rather than a fake timer. Concretely: `stamina.current / (last_block_cost / last_block_interval)`, clamped to `[0.0, 9.99]`.

### 5. Enemy guards that break

`ShieldHurtbox` gains the same economics as the player's guard, scaled down:

```gdscript
@export var block_mitigation := 0.75
@export var block_angle_deg := 100.0
@export var guard_stability := 60.0        # new: a poise-like pool
@export var guard_break_duration := 2.0    # new
```

Each frontally blocked hit subtracts the incoming `poise_damage` from `guard_stability`. At zero, the shield enters a `guard_break_duration` window during which `block_mitigation` is 0.0 and the owner is staggered via `apply_stagger(guard_break_duration)`. Stability regenerates at `20.0`/s after a 2.5 s delay, mirroring `Poise`. This gives shield enemies a readable answer — chip the shield with poise-heavy attacks or bash it — instead of the current unconditional 75%.

`ShieldHurtbox.receive_hit` also stops rebuilding the `DamageInfo` by hand. It mutates a duplicate so `status_id` and `status_stacks` survive:

```gdscript
var mitigated := DamageInfo.create(
    info.amount * (1.0 - block_mitigation),
    info.poise_damage * (1.0 - block_mitigation),
    info.source, info.damage_type, info.direction,
    info.status_id, info.status_stacks
)
```

### 6. Guard as content

All guard tuning moves to the equipped item so a tower shield and a buckler differ:

```json
"block": {
  "reduction": 0.62,
  "stability": 1.4,
  "arc_degrees": 140,
  "parry_window": 0.14,
  "bash_damage": 10,
  "bash_poise_damage": 34
}
```

`Guard.set_combat_stat_modifiers(equipment_stats, talent_stats)` gains a third argument carrying the resolved `block` block from the `secondary` slot (falling back to the `weapon` slot, then to the constants). Higher `stability` means cheaper blocks; a wider `arc_degrees` costs a shorter `parry_window`, which is the buckler-versus-tower-shield trade expressed as data.

## Work plan

1. **Parry staggers the attacker** — `guard.gd` `_stagger_attacker()` calling `apply_stagger()` and `cancel_attack()`; `cancel_attack()` added to `castle_enemy_base.gd` as a thin wrapper over its existing `_end_attack` path. (GRD-01)
2. **Fix `ShieldHurtbox` status loss** — seven-argument `DamageInfo.create`. One line, no dependencies. (GRD-08)
3. **Real block economics** — `BLOCK_STAMINA_PER_POISE`, poise transfer scaling, `BLOCK_MOVE_SPEED_MULT` exposed through a `get_move_speed_multiplier()` read by `locomotion.gd`, and the `RegenState.BLOCKING` call from [`stamina-mana.md`](stamina-mana.md) step 4. (GRD-02)
4. **Honest guard HUD** — `get_block_time_remaining()` returns real headroom; `combat_hud.gd` renders a stability bar. (GRD-04)
5. **Parry re-arm** — `PARRY_REARM_DELAY` timer in `_physics_process`. (GRD-05)
6. **Guard cancel and shield bash** — remove the `is_guard_active` early return from `weapon_controller.gd:568`, add the two guard actions. (GRD-06)
7. **Breakable enemy shields** — `guard_stability`, `guard_break_duration` and the regen loop on `shield_hurtbox.gd`. (GRD-07)
8. **Guard as content** — `block` object in the item schema, resolution in `inventory_service.gd`, third argument on `set_combat_stat_modifiers`, and deletion of the corresponding constants. (GRD-03, GRD-09)
9. **Contract assertion** — a `_ready()` `push_error` in `hurtbox.gd` when a player-team hurtbox resolves no `Guard`, so the node-name contract fails loudly. (GRD-10)

Steps 1-2 are one-file changes. Step 3 changes tuning that steps 4-8 build on, so it should land before them.

## Data and schema changes

| Change | File |
|--------|------|
| `block` object: `reduction` (0-0.95), `stability` (min 0.1), `arc_degrees` (0-360), `parry_window` (min 0), `bash_damage`, `bash_poise_damage` — all numbers, all optional | `content/schemas/item-catalog.v1.json` |
| Same `block` object allowed on weapon definitions for two-handed weapons that self-guard | `content/schemas/weapon-definition.v1.json` |
| `guard_stability` (number, min 0) and `guard_break_duration` (number, min 0) on enemy definitions | `content/schemas/enemy-definition.v1.json` |
| `blockStability` as an item/affix stat key | `content/schemas/item-catalog.v1.json`, `content/schemas/affix-definition.v1.json` |
| `guard_stability: 60`, `guard_break_duration: 2.0` authored on shield enemies | `content/enemies/castle_shield.json` and other shield users |

No save-format change; `save_migrator.gd` `CURRENT_VERSION` stays at 4.

## Acceptance criteria

- [ ] A successful parry against a `castle_knight` mid-windup puts it into stagger for 1.2 s and its in-flight hitbox is disabled. (GRD-01)
- [ ] Blocking a `castle_knight` swing (20 damage, 17 poise damage) with a default shield costs 9.35 stamina and lets 9.0 damage through. (GRD-02)
- [ ] Blocking a 55-poise-damage heavy costs 30.25 stamina — more than blocking a 17-poise light. (GRD-02)
- [ ] Equipping a shield with `"block": {"reduction": 0.62, "stability": 1.4}` measurably changes both the damage through and the stamina cost. (GRD-03)
- [ ] `get_block_time_remaining()` returns a value that changes as stamina changes and is never a constant. (GRD-04)
- [ ] Holding block for 1.0 s with no incoming hits re-opens the parry window. (GRD-05)
- [ ] Pressing `light_attack` while guarding starts a shield bash without dropping guard first; pressing `heavy_attack` drops guard and swings. (GRD-06)
- [ ] Movement speed while guarding is 60% of walk speed. (GRD-06)
- [ ] Landing 60 points of poise damage on a `castle_shield`'s front breaks its guard, zeroes its mitigation for 2.0 s and staggers it. (GRD-07)
- [ ] A `dagger` light attack blocked by a `castle_shield` still applies `bleed` to it. (GRD-08)

## Validation

Extend `apps/game/client/scripts/validation/suites/combat_suite.gd`, replacing `combat.guard_parry_block_api` (`combat_suite.gd:55-73`), which today only greps `guard.gd` for four `func` strings and passes even if every one of them is a stub.

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `combat.parry_staggers_attacker` | Spawn `castle_knight`, force it into windup, force `parry_window_active`, call `try_parry_attack(enemy)` → `enemy.is_staggered` true and its `Hitbox.is_active()` false | GRD-01 |
| `combat.block_cost_scales_with_poise` | `modify_incoming_hit` with `poise_damage` 17 then 55 → stamina spends of 9.35 and 30.25 | GRD-02 |
| `combat.block_reduction_from_data` | Apply a fixture item with `block.reduction: 0.62` → `modify_incoming_hit` returns `amount * 0.38` | GRD-03 |
| `combat.block_time_is_not_constant` | Call `get_block_time_remaining()` at 100 and at 30 stamina → different values | GRD-04 |
| `combat.parry_rearms` | Enter guard, await 1.0 s with no hits → `parry_window_active` true again | GRD-05 |
| `combat.guard_cancel_allowed` | While `is_guard_active`, `_try_attack("heavy")` starts an attack | GRD-06 |
| `combat.shield_bash_applies_stun` | Bash a `training_grunt` → its `StatusController` reports an active `stun` (requires [`statuses-and-buffs.md`](statuses-and-buffs.md) STA-01) | GRD-06 |
| `combat.shield_enemy_guard_breaks` | Land 60 poise damage frontally on `castle_shield` → `block_mitigation` effectively 0 for 2.0 s and `is_staggered` true | GRD-07 |
| `combat.shield_preserves_status` | `receive_hit` on `ShieldHurtbox` with `status_id: "bleed"` → the forwarded `DamageInfo.status_id` is still `"bleed"` | GRD-08 |
| `combat.guard_node_contract` | Instantiate `player.tscn`, assert `get_node_or_null("Guard")` is non-null and exposes all four duck-typed methods by `has_method`, not by file text | GRD-10 |

## Related

- Current behavior: [`../existing_codebase/guard.md`](../existing_codebase/guard.md)
- [`combat-core.md`](combat-core.md) — pipeline stages 3 and 4
- [`dodge.md`](dodge.md) — the option guard competes with
- [`stamina-mana.md`](stamina-mana.md) — `RegenState.BLOCKING`, block cost
- [`weapons.md`](weapons.md) — guard-cancel and bash live in `WeaponController`
- [`statuses-and-buffs.md`](statuses-and-buffs.md) — bash applies `stun`
- [`enemies.md`](enemies.md) — `apply_stagger` / `cancel_attack` on the enemy base
- [`hit-feedback.md`](hit-feedback.md), [`ui/combat_hud.md`](ui/combat_hud.md)
