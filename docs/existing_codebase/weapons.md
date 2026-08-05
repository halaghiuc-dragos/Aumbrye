# Weapons

`WeaponController` is the player's entire offensive input path: it reads a weapon JSON, runs a startup/active/recovery state machine, spends stamina, resizes the hitbox by archetype, and enables it. It is on the live play path — `player.tscn` mounts it and `InventoryService` swaps its data on every equipment change.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/combat/weapon_controller.gd` | Attack state machine, input, stamina, hitbox profile, soft lock |
| `content/weapons/*.json` | Eight weapon definitions (`sword_basic`, `castle_sword`, `greatsword`, `axe`, `spear`, `dagger`, `staff`, `bow`) |
| `content/schemas/weapon-definition.v1.json` | Schema; `additionalProperties: false` at both object levels |
| `apps/game/client/scripts/items/equipment.gd` | Slot map and stat aggregation feeding `set_combat_stat_modifiers()` |
| `apps/game/client/scripts/inventory/grid_inventory.gd` | `get_equipped_weapon_data_path()` maps an item's `weaponId` to a JSON path |

## How it works

### Loading

`_ready()` (`weapon_controller.gd:77`) resolves `_body` (parent `CharacterBody3D`), `Stamina`, `CombatReactions`, `Guard`, `LockOn`, connects to `Dodge.dodge_started` / `dodge_ended`, resolves the hitbox from the `hitbox_path` export, then calls `_load_weapon_data()` → `load_weapon_from_path("content/weapons/sword_basic.json")` (`WEAPON_DATA_RELATIVE`, `weapon_controller.gd:6`).

`load_weapon_from_path()` (`:141`) reads through `ContentLoader.load_json()`, falls back to the inline `FALLBACK_WEAPON_DATA` dictionary (`:18-40`) with a `push_warning`, recomputes `_weapon_scaling_multiplier`, refreshes `_damage_multiplier`, applies the hitbox profile, and emits `weapon_changed(archetype)`.

`InventoryService.apply_equipment_to_player_node()` (`inventory_service.gd:199-205`) drives the swap: `load_weapon_from_path(inventory.get_equipped_weapon_data_path())` then `set_combat_stat_modifiers(equip_stats, talent_stats, get_class_stats())`. `grid_inventory.gd:315-321` returns `content/weapons/sword_basic.json` when nothing is equipped and otherwise `content/weapons/<def.weaponId>.json`, defaulting `weaponId` to `sword_basic`.

### Input and phases

`_physics_process(delta)` (`:109`) each frame:

1. Ticks `_combo_idle_timer` (resets `_combo_index` to 0 when it expires) and `_post_dodge_attack_buffer`.
2. Returns early if `_is_action_blocked()` (`:564`): dodging, `Guard.is_guard_active`, `CombatReactions.can_act() == false` while not in hyperarmor, or `StatusController.is_stunned()`.
3. Branches to `_process_bow_input(delta)` when `archetype == "bow"`.
4. Handles `two_hand` and `weapon_art` actions.
5. If attacking, advances the phase; otherwise reads `light_attack` / `heavy_attack` and flushes `_buffered_attack`.

`_try_attack(kind)` (`:255`): while already attacking, it stores the input in `_buffered_attack` if `_phase_timer <= buffer_window` or the phase is `RECOVERY`. Otherwise it picks `heavy_attack` or `light_attacks[_combo_index % size]`, computes `cost = stamina_cost * CombatStatModifiers.stamina_cost_multiplier(_talent_stats)`, checks `Stamina.has(cost)`, consumes, snaps facing to a soft-lock target, and starts the attack.

`_process_attack_phase(delta)` (`:316`) counts `_phase_timer` down and transitions `STARTUP -> ACTIVE -> RECOVERY -> idle`. Entering `ACTIVE` re-snaps soft-lock facing and calls `_enable_hitbox_for_attack()`; entering `RECOVERY` disables the hitbox. `_end_attack()` (`:366`) sets `_combo_idle_timer = buffer_window + recovery` and increments `_combo_index` only for light attacks.

`_enable_hitbox_for_attack()` (`:336`) computes:

```
dmg   = attack.damage       * _damage_multiplier
poise = attack.poise_damage * _damage_multiplier
```

then, if `Guard.get_riposte_damage_multiplier()` exceeds 1.0, multiplies both by it and calls `Guard.consume_riposte()`. It resolves `damage_type` from the attack then the weapon, `status` from the attack then the weapon's `status_on_hit`, and `status_stacks`, then calls `Hitbox.set_attack_values(dmg, poise, dmg_type, status_id, status_stacks)` — five arguments; the sixth `crit_chance` parameter is left at its 0.0 default. Finally it sets `_hyperarmor_active` from the attack's `hyperarmor` flag or a nonzero `poise_threshold`, and plays `VfxService.play_attack_swing`.

`_damage_multiplier = _base_damage_multiplier * _weapon_scaling_multiplier * stance_mult` (`:435-437`), where `stance_mult` is `TWO_HAND_DAMAGE_MULT := 1.25` when two-handing.

### Movement coupling

| Method | Value | Consumer |
|--------|-------|----------|
| `locks_movement()` | true in `STARTUP`/`ACTIVE`/`RECOVERY`/`DRAWING`, except the last 45% of recovery | `player_combat_reactions.gd:61-63` |
| `get_move_speed_multiplier()` | `COMMIT_SPEED_MULT := 0.2` in startup/active/drawing, `RECOVERY_SPEED_MULT := 0.65` in recovery | `locomotion.gd:99-100` |
| `get_rotation_cap_multiplier()` | `ATTACK_ROT_CAP_MULT := 0.15` in startup/active/drawing | `locomotion.gd:101-102` |
| `get_attack_lunge_velocity()` | `Vector3.ZERO`, unconditionally | none |

### Soft lock

`_snap_soft_lock_facing()` (`:460`) fires on attack start and again on entering `ACTIVE`. With `LockOn` engaged it faces the locked target; otherwise `_find_soft_lock_target()` scores every node in the `lockable` group by `(cone_deg - angle) / distance` within `SOFT_LOCK_RANGE := 14.0` and a cone of `SOFT_LOCK_CONE_DEG := 100.0` degrees (narrowed to 88 while moving). Facing is applied by setting `Facing.rotation.y` through `LockOnMovement.world_direction_to_local_facing_y`.

### Hitbox profile

`_apply_hitbox_profile(for_bow_shot)` (`:531`) hardcodes a `BoxShape3D` size and Z offset per archetype:

| Archetype | Size | Offset Z |
|-----------|------|----------|
| default / `sword` | `(1.2, 0.8, 1.4)` | 0.55 (y -0.12) |
| `spear` | `(1.0, 0.75, 1.65)` | 0.72 |
| `dagger` | `(0.8, 0.6, 0.9)` | 0.4 |
| `greatsword` | `(1.6, 1.0, 1.8)` | 0.85 |
| `axe` | `(1.4, 0.9, 1.5)` | 0.75 |
| `staff` | `(0.8, 0.7, 2.0)` | 1.1 |
| `bow` | `(0.6, 0.6, 1.0)`, or `(0.6, 0.6, 8.0)` for a shot | 0.5, or 4.0 for a shot |

Two-handing multiplies size by 1.1 and offset Z by 1.08 for every archetype except `bow`.

### Bow

`_process_bow_input()` (`:378`) sets `is_bow_aiming` from `block` or `light_attack` being held. Holding `heavy_attack` enters `DRAWING` and accumulates `_draw_charge` over `draw_time` (0.75 s for `bow.json`). Releasing above 0.05 charge calls `_fire_bow_shot()` (`:400`), which spends the heavy attack's stamina, scales heavy damage by `lerpf(0.5, 1.5, _draw_charge)`, sets `_phase_timer = 0.08` (a literal, not the authored `startup`), swaps in the 8 m long hitbox and starts an `ACTIVE`-bound attack named `bow_shot`. There is no projectile node in this path; `enemy_projectile.tscn` is used only by enemies.

### Weapon data shape

Top level (all optional except the schema's required set): `id`, `name`, `archetype`, `damage_type`, `status_on_hit`, `draw_time`, `lunge_distance`, `buffer_window`, `scaling`, `light_attacks[]`, `heavy_attack`. Per attack: `damage`, `poise_damage`, `stamina_cost`, `startup`, `active`, `recovery`, `lunge_distance`, `damage_type`, `status`, `status_stacks`.

Authored coverage:

| Weapon | Archetype | Lights | Heavy damage | `scaling` | `lunge_distance` | `status` |
|--------|-----------|--------|--------------|-----------|------------------|----------|
| `sword_basic` | sword | 3 | 28 | `physicalDamage: 1.0` | absent | absent |
| `castle_sword` | sword | 3 | 38 | `physicalDamage: 1.0`, `armor: 0.02` | 0.42 | absent |
| `greatsword` | greatsword | 2 | 48 | `physicalDamage: 1.5`, `poiseDamage: 1.0` | 0.35 | absent |
| `axe` | axe | 3 | 44 | `physicalDamage: 1.8`, `poiseDamage: 1.2` | 0.45 | absent |
| `spear` | spear | 3 | 32 | `poiseDamage: 1.0`, `physicalDamage: 0.8` | 0.6 | absent |
| `dagger` | dagger | 3 | 18 | `critChance: 2.0`, `moveSpeed: 0.5` | 0.3 | `bleed` on every attack |
| `staff` | staff | 3 | 24 | `staminaRegen: 1.0`, `physicalDamage: 0.6` | 0.25 | absent |
| `bow` | bow | 1 | 28 | `critChance: 1.5` | absent | absent |

`weapon_scaling_multiplier()` (`combat_stat_modifiers.gd:14-22`) iterates every key in `scaling` and treats the value as a *damage* coefficient against the matching class stat, regardless of what the key means.

### Equipment

`equipment.gd` defines `SLOT_ORDER` (9 slots, `weapon` and `secondary` among them) and 21 `STAT_KEYS`. `aggregate_stats()` sums base stats per slot, folds the five `FLAT_DAMAGE_STAT_KEYS` (`physicalDamage`, `fireDamage`, `frostDamage`, `arcaneDamage`, `poisonDamage`) into `bonusDamage` (`equipment.gd:150-151`), and adds affix values through the resolver callable. `slot_for_item_def()` routes by explicit `equipmentSlot`, then `itemType == "weapon"`, then `runRelicId` to the `relic` slot. There is no archetype validation anywhere in the slot logic.

## Contracts

- **Node names:** parent must be a `CharacterBody3D` with children named `Stamina`, `Guard`, `Dodge`, `LockOn`, `CombatReactions`, `StatusController`, `Facing`, and (for soft lock through the camera) `CameraPivot`.
- **`@export var hitbox_path: NodePath`** — set to `../Facing/WeaponPivot/Hitbox` in `player.tscn:95`. The target must expose `enable()`, `disable()`, `reset_swing()`, `set_attack_values()`.
- **Signals emitted:** `attack_started(attack_name)`, `attack_ended`, `weapon_changed(archetype)`. Attack names are `light_1`..`light_N`, `heavy`, `weapon_art`, `bow_shot`.
- **Public state read by others:** `is_attacking` (`locomotion.gd:125`), `current_phase`, `is_bow_aiming`, `has_hyperarmor()`, `get_debug_state()`, `get_attack_phase_progress()`.
- **Input actions:** `light_attack`, `heavy_attack`, `block`, `two_hand`, `weapon_art`.
- **Content contract:** `ContentLoader.load_json("content/weapons/<id>.json")`; the item's `weaponId` must match a filename.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Light/heavy/combo state machine | IMPLEMENTED | `weapon_controller.gd:255-334` |
| Stamina gating and talent cost reduction | IMPLEMENTED | `weapon_controller.gd:273-277,456-457` |
| Per-archetype hitbox reach | PARTIAL | `weapon_controller.gd:531-561` — hardcoded in GDScript, not in `content/weapons/` or the schema |
| Attack lunge | STUB | `weapon_controller.gd:238-239` returns `Vector3.ZERO`; no caller anywhere under `apps/`. `lunge_distance` is authored in 6 of 8 weapons (`content/weapons/spear.json:45` = 0.75) and read by nothing |
| Weapon art | STUB | `_try_weapon_art()` (`weapon_controller.gd:282-285`) returns when `_weapon_data.art` is empty. No `content/weapons/*.json` has an `"art"` key, and `weapon-definition.v1.json:7` sets `additionalProperties: false`, so one cannot be added without a schema change |
| `scaling` block semantics | BROKEN | `combat_stat_modifiers.gd:14-22` multiplies *damage* by every scaling key; `dagger.json:9` `critChance: 2.0` and `staff.json:8` `staminaRegen: 1.0` therefore inflate raw damage |
| Crit from weapons | ABSENT | `weapon_controller.gd:350` passes five arguments to `set_attack_values`; the `crit_chance` parameter (`hitbox.gd:72`) stays 0.0 |
| Two-hand stance | PARTIAL | `weapon_controller.gd:428-437` — +25% damage and +10% reach with no stamina, speed or guard cost. `TWO_HAND_POISE_MULT := 1.35` (`:16`) is declared and never read |
| Hyperarmor on weapon attacks | PARTIAL | `weapon_controller.gd:352-354` reads `hyperarmor` / `poise_threshold` from attack data, but `weapon-definition.v1.json:34-45` forbids both keys, so only the dead weapon-art path (`:299`) can set it |
| Bow | PARTIAL | `weapon_controller.gd:400-418` — no projectile; an 8 m box hitbox on the player for one `_phase_timer = 0.08` frame budget; the authored `startup` is ignored |
| Weapon-to-item archetype validation | ABSENT | `equipment.gd:31-47` and `grid_inventory.gd:315-321` accept any `weaponId` and fall back to `sword_basic` |
| Weapon visuals | PLACEHOLDER | Box meshes from `scripts/art/characters/diorama_weapon_kit.gd`; see [`diorama-weapon-kit.md`](diorama-weapon-kit.md) |

## Related

- Improvement plan: [`../actual_improvements/weapons.md`](../actual_improvements/weapons.md)
- [`combat-core.md`](combat-core.md) — what happens to the damage this file produces
- [`hit-hurtboxes.md`](hit-hurtboxes.md) — `Hitbox.set_attack_values` and overlap scanning
- [`stamina-mana.md`](stamina-mana.md) — the resource every attack spends
- [`guard.md`](guard.md) — riposte multiplier consumer
- [`loot-and-equipment.md`](loot-and-equipment.md), [`inventory-service.md`](inventory-service.md) — where `weaponId` and stats come from
- [`player-combat.md`](player-combat.md), [`lock-on.md`](lock-on.md)
