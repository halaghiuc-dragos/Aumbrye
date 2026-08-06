# Combat core

The damage resolution primitives every fight runs through: `Health`, `Poise`, `DamageInfo`, the `Hurtbox.receive_hit` mitigation chain, `CombatStatModifiers`, and floating damage numbers. All of it is on the live play path — every player and enemy scene mounts `Health`, and `Hurtbox` is the single entry point for damage in the client.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/combat/health.gd` | `Health` node: HP pool, `died` signal, revive/force-kill helpers |
| `apps/game/client/scripts/combat/poise.gd` | `Poise` node: stagger meter with delayed regen |
| `apps/game/client/scripts/combat/damage_info.gd` | `DamageInfo` payload + `apply_resistance()` |
| `apps/game/client/scripts/combat/hurtbox.gd` | `Hurtbox.receive_hit()` — the mitigation chain |
| `apps/game/client/scripts/combat/combat_stat_modifiers.gd` | Static helpers turning equipment/talent/class stats into combat multipliers |
| `apps/game/client/scripts/combat/damage_number.gd` | `DamageNumberSpawner` static spawners + `Label3D` float animation |
| `apps/game/client/scenes/combat/damage_number.tscn` | Scene loaded by both spawners |

## How it works

### Damage pipeline order

`Hurtbox.receive_hit(info)` (`hurtbox.gd:34`) is the only place mitigation happens. Steps, in the exact order they run:

1. **Dead check** — `hurtbox.gd:35`. If the attached `Health.is_dead()`, return with no feedback.
2. **I-frames** — `hurtbox.gd:37-39`. Walks ancestors for a node named `Dodge` and reads its `iframes_active` property. If true, return immediately. No signal, no VFX, no `damaged` emission.
3. **Parry** — `hurtbox.gd:41-43`. Walks ancestors for a node named `Guard`, calls `try_parry_attack(info.source)`. If it returns `true`, return.
4. **Block** — `hurtbox.gd:46-51`. `Guard.modify_incoming_hit(info)` returns `{amount, poise, blocked}`. If `blocked` is true, `_emit_block_feedback()` fires immediately, before the remaining mitigation runs, so the "BLOCKED" number shows the post-block-but-pre-defense figure.
5. **Backstab** — `_apply_backstab()` (`hurtbox.gd:64`). `BACKSTAB_DAMAGE_MULT := 1.5` when the angle between `body.global_transform.basis.z` and the vector to the attacker is `<= BACKSTAB_ARC_DEGREES := 70.0`.
6. **Flat defense** — `_apply_defense()` (`hurtbox.gd:84`). Reads two `Object` metas off the `CharacterBody3D`: `combat_defense` and `combat_damage_reduction`, both written by `inventory_service.gd:213-214`. `reduction = clampf(defense * DEFENSE_PER_POINT + damage_reduction, 0.0, 0.9)` with `DEFENSE_PER_POINT := 0.02`.
7. **Resistances** — `_apply_resistances()` → `DamageInfo.apply_resistance()`. The table comes from `EnemyCatalog.get_definition(enemy_id).resistances` and is only reachable when the victim body implements `get_enemy_id()` (`hurtbox.gd:152`).
8. **Health** — `_health.take_damage(final_amount)` only when `final_amount > 0.0`.
9. **Poise** — `_poise.take_poise_damage(final_poise)` only when the victim is not already dead.
10. **Status** — `_apply_status_from_hit()` looks for a child node named `StatusController` on the victim body.
11. **Victim feedback** — `MaterialFlash.flash(body)`, `VfxService.play_blood_decal`, `VfxService.play_impact_decal`, then `HitFeedback.on_hit_received()` if the body has one.
12. **`damaged` signal** — `damaged.emit(info)` emits the *original*, unmitigated `DamageInfo`.

### Health

`health.gd`. `MAX_HEALTH := 100.0`. `configure(max_hp)` sets both `max_health` and `current` and clears `_dead`. `take_damage(amount)` clamps at 0 and emits `died` once. `heal`, `reset_health`, `restore_current(value)` (clamped, used for save restore) and `force_dead()` round out the API. There is no damage-type awareness, no overkill value, and no death-cause record: `take_damage` takes a single `float`.

### Poise

`poise.gd`. `MAX_POISE := 50.0`, `REGEN_RATE := 20.0` per second, `REGEN_DELAY := 2.0` seconds. `take_poise_damage()` early-returns while `_broken` is true, so a broken target absorbs no further poise damage. Regen is gated on `_regen_timer`, which every poise hit resets to 2.0 s, so a broken target stays broken for at least 2.0 s before the first regen frame sets `current > 0.0` and clears `_broken` (`poise.gd:38-39`).

Poise never gates health damage. It only emits `poise_broken`, consumed by `player_combat_reactions.gd:34` (which staggers for `POISE_STAGGER_DURATION := 0.85` then calls `reset_poise()`) and `castle_enemy_base.gd:77`. `poise_damaged` is consumed by `player_anim_director.gd:125` for a flinch.

### DamageInfo

`damage_info.gd`. Six damage types (`physical`, `fire`, `frost`, `poison`, `lightning`, `arcane`) in `ALL_TYPES`; `create()` falls back to `physical` for any unlisted string. Fields: `amount`, `damage_type`, `poise_damage`, `source`, `direction`, `status_id`, `status_stacks`.

`direction` is set by `Hitbox._try_hit` (`hitbox.gd:131-133`) as `(target.global_position - attacker.global_position).normalized()` — it points *from* the attacker *to* the victim.

`apply_resistance(base, type, resistances)` returns `maxf(0.0, base * (1.0 - resist))`. There is no upper clamp, so a negative resistance value amplifies damage without limit.

### CombatStatModifiers

`combat_stat_modifiers.gd` is a `RefCounted` of twelve statics. Live ones and their call sites:

| Function | Formula | Called from |
|----------|---------|-------------|
| `damage_multiplier` | `1 + damagePercent/100 + physicalDamage`, floor 0.1 | `inventory_service.gd:205`, `weapon_controller.gd:205` |
| `weapon_scaling_multiplier` | `1 + sum(class_stat * coeff)` over the weapon's `scaling` block | `weapon_controller.gd:146,201` |
| `stamina_cost_multiplier` | `maxf(0.1, 1 - staminaCostReduction)` | `weapon_controller.gd:457` |
| `block_reduction_bonus` | `blockReduction` | `guard.gd:98` |
| `max_stamina_bonus` | `staminaMax` | `inventory_service.gd:193` |
| `stamina_regen_multiplier` | `1 + staminaRegen` | `inventory_service.gd:194` |
| `max_poise_bonus` | talent `poise` | `inventory_service.gd:197` |
| `move_speed_multiplier` | `1 + moveSpeedPercent/100 + moveSpeed` | `inventory_service.gd:208` |

`flat_damage_bonus` (`:25`), `poise_damage_multiplier` (`:29`), `crit_chance` (`:37`) and `incoming_damage_multiplier` (`:41`) have no call sites anywhere under `apps/`.

### Damage numbers

`damage_number.gd` exposes two statics, both `load()`ing `res://scenes/combat/damage_number.tscn` on every call: `spawn(world_position, amount, parent)` offsets +1.8 m and tints `Color(1.0, 0.35, 0.25)`; `spawn_text(world_position, text, parent, color)` offsets +2.0 m with a caller-supplied color. `LIFETIME := 0.65`, `RISE_SPEED := 1.2`; the instance tweens `position:y` and `modulate:a` in parallel and then `queue_free()`s.

## Contracts

- **Node names are the API.** `Hurtbox` finds `Guard`, `Dodge`, `StatusController` and `HitFeedback` by literal node name (`hurtbox.gd:101,111,125,165`). Renaming any of them silently disables that stage of the pipeline.
- **`CharacterBody3D` ancestry.** `_find_character_body()` walks up until it hits a `CharacterBody3D`; backstab, defense, resistances, status and feedback all no-op if there is none.
- **Metas.** `combat_defense` and `combat_damage_reduction` on the player `CharacterBody3D`, written by `InventoryService.apply_equipment_to_player_node()`.
- **Signals.** `Health.health_changed(current, max_value)`, `Health.died`, `Poise.poise_changed`, `Poise.poise_broken`, `Poise.poise_damaged(amount, remaining)`, `Hurtbox.damaged(info)`.
- **Autoloads used:** `VfxService`, `EnemyCatalog` (a `class_name` static, not an autoload).
- **`@export`s on `Hurtbox`:** `team` (`"player"` / `"enemy"`), `health_path`, `poise_path`.
- **Collision layers** (from `player.tscn` and `castle_grunt.tscn`): body layer 1<<1, hitbox layer 1<<2 mask 1<<3, hurtbox layer 1<<3 mask 1<<2, world layer 1<<0.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| `DamageResolution` + `hit_resolved` mitigation chain | IMPLEMENTED | `damage_resolution.gd`, `hurtbox.gd` |
| Backstab via `DamageInfo.classify_arc()` + `Facing` | IMPLEMENTED | `damage_info.gd`, `hurtbox.gd` |
| Flat damage, crit, poise mult from equipment/talents | IMPLEMENTED | `weapon_controller.gd` → `hitbox.set_attack_values` |
| Flat defense from equipment meta | IMPLEMENTED | `hurtbox.gd` + `inventory_service` `combat_defense` |
| Poise meter + authored `stagger_duration` | IMPLEMENTED | `poise.gd` `configure(max, stagger_duration)` |
| Player elemental resistances | IMPLEMENTED | `combat_resistances` meta in `hurtbox.gd` |
| Enemy elemental resistances | IMPLEMENTED | `hurtbox.gd` via `get_enemy_id()` |
| Damage numbers use accessibility colors | IMPLEMENTED | `damage_number.gd` `get_damage_color()` |
| `Health` HP pool, `died` signal | IMPLEMENTED | `health.gd` |

## Related

- Improvement plan: [`../actual_improvements/combat-core.md`](../actual_improvements/combat-core.md) — **FINISHED**
- [`hit-hurtboxes.md`](hit-hurtboxes.md) — how `DamageInfo` is produced and delivered
- [`weapons.md`](weapons.md) — where player `amount` / `poise_damage` come from
- [`guard.md`](guard.md), [`dodge.md`](dodge.md) — the two gates ahead of mitigation
- [`statuses-and-buffs.md`](statuses-and-buffs.md) — step 10 of the pipeline
- [`hit-feedback.md`](hit-feedback.md) — step 11
- [`player-combat-reactions.md`](player-combat-reactions.md) — `poise_broken` consumer
