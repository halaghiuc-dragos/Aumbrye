## Status: FINISHED (WEP-01 lunge)

`get_attack_lunge_velocity()` reads per-attack `lunge_distance`; `locomotion.gd` applies it during attacks including movement-locked commits.

## Current state

Eight weapon JSONs drive a working startup/active/recovery machine with combos, buffering, stamina costs and per-archetype hitbox reach (see [`../existing_codebase/weapons.md`](../existing_codebase/weapons.md)). Three authored features do nothing at runtime: `lunge_distance` is written into six weapons and read by no code, no weapon has an `"art"` key so the `weapon_art` button is permanently dead, and the `scaling` block is applied as a blanket damage coefficient so `dagger.json`'s `critChance: 2.0` silently multiplies raw damage instead of granting crit. Reach, weight and stance behavior live as GDScript constants rather than content, and the schema's `additionalProperties: false` currently forbids every key the controller would need to read.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| WEP-01 | P0 | `get_attack_lunge_velocity()` returns `Vector3.ZERO` and has zero callers; all authored `lunge_distance` values are inert | `weapon_controller.gd:238-239`; no match for `get_attack_lunge_velocity` outside its own definition; `content/weapons/spear.json:7,17,26,35,45` |
| WEP-02 | P0 | The `weapon_art` input is unreachable: no weapon JSON has an `"art"` key and the schema forbids adding one | `weapon_controller.gd:124-125,282-285`; no `"art"` match under `content/weapons/`; `content/schemas/weapon-definition.v1.json:7` |
| WEP-03 | P0 | `scaling` is applied as a damage coefficient for every key, so non-damage stats inflate damage | `combat_stat_modifiers.gd:14-22`, `content/weapons/dagger.json:9`, `content/weapons/staff.json:8`, `content/weapons/bow.json:8` |
| WEP-04 | P0 | Weapons cannot crit — `_enable_hitbox_for_attack` passes five arguments and never the `crit_chance` parameter | `weapon_controller.gd:350`, `hitbox.gd:72,135` |
| WEP-05 | P1 | Hitbox reach and shape are hardcoded per archetype in GDScript; adding a weapon type means editing code | `weapon_controller.gd:531-561` |
| WEP-06 | P1 | Weapon hyperarmor is unreachable: the controller reads `hyperarmor` and `poise_threshold` from attack data but the schema forbids both keys | `weapon_controller.gd:352-354` vs `content/schemas/weapon-definition.v1.json:33-45` |
| WEP-07 | P1 | Two-handing is a pure upside — +25% damage, +10% reach, no stamina, speed or guard cost; `TWO_HAND_POISE_MULT` is dead | `weapon_controller.gd:15-16,428-437` |
| WEP-08 | P1 | The bow fires no projectile: it sweeps an 8 m box hitbox anchored to the player and hardcodes `_phase_timer = 0.08`, ignoring the authored `startup` | `weapon_controller.gd:400-418,553-555`; `enemy_projectile.tscn` exists but is enemy-only |
| WEP-09 | P1 | No attack has authored per-hit windows: one box is active for the entire `active` duration, so a greatsword sweep and a dagger jab confirm identically | `weapon_controller.gd:322-325`, `hitbox.gd:62-63` |
| WEP-10 | P2 | Any item can be equipped as any weapon; `weaponId` silently falls back to `sword_basic.json` with no warning | `grid_inventory.gd:315-321`, `equipment.gd:31-47` |
| WEP-11 | P2 | The post-dodge buffer flush block is duplicated and unreachable — the second block already covers it | `weapon_controller.gd:133-138` |

## Target design

### 1. Attack lunge as authored displacement

`lunge_distance` is already in the schema and in six weapons. Make it a real, frame-accurate displacement applied during `STARTUP` and the first half of `ACTIVE` — that is where a committed swing should carry you and where the animation reads as forward motion.

```gdscript
# weapon_controller.gd
const LUNGE_FRACTION_OF_STARTUP := 1.0   # lunge spans all of startup...
const LUNGE_FRACTION_OF_ACTIVE := 0.5    # ...and the first half of active
const LUNGE_MIN_SPEED := 0.5             # m/s floor so a 0.2 m lunge is still visible

func get_attack_lunge_velocity() -> Vector3
```

Implementation: on `_start_attack`, cache `_lunge_distance = attack.get("lunge_distance", _weapon_data.get("lunge_distance", 0.0))` and `_lunge_duration = startup + active * 0.5`. `get_attack_lunge_velocity()` returns `facing_forward * maxf(LUNGE_MIN_SPEED, _lunge_distance / _lunge_duration)` while `_lunge_elapsed < _lunge_duration` and in `STARTUP` or `ACTIVE`, otherwise `Vector3.ZERO`. Direction is the `Facing` node's forward *after* `_snap_soft_lock_facing()`, so a lunge tracks the soft-lock target.

`locomotion.gd:112-123` becomes the single caller: after the accel/decel blend, add `_weapon.get_attack_lunge_velocity()` to `horizontal` before writing `velocity.x/z`. Because it is additive to a horizontal velocity that is already scaled by `COMMIT_SPEED_MULT := 0.2`, the lunge dominates during the commit window, which is the intent.

Sanity numbers with the authored data: `spear` heavy `lunge_distance: 0.75` over `startup 0.28 + active*0.5 0.08 = 0.36 s` → 2.08 m/s. `dagger` light 1 `0.25` over `0.08 + 0.04 = 0.12 s` → 2.08 m/s. `axe` heavy `0.6` over `0.48 + 0.11 = 0.59 s` → 1.02 m/s. The heavy weapons lunge slower and further, the dagger snaps — that is the correct feel and it falls out of the existing data.

Rejected alternative: a root-motion curve baked into the diorama animation. The anim library is a procedural keyframe table (`diorama_anim_library.gd`) with no root-motion track; a data-driven velocity is deterministic and testable today.

### 2. Weapon arts as authored content

Add an `art` object to the schema and author one per archetype. Shape:

```json
"art": {
  "id": "spear_charge",
  "name": "Charging Thrust",
  "stamina_cost": 26,
  "damage": 34,
  "poise_damage": 40,
  "startup": 0.32,
  "active": 0.2,
  "recovery": 0.5,
  "lunge_distance": 2.4,
  "hyperarmor": true,
  "damage_type": "physical",
  "status": "",
  "status_stacks": 1,
  "cooldown": 6.0
}
```

`_try_weapon_art()` gains a `_art_cooldown` timer (new, currently absent) so an art is a resource *and* a timing commitment, and emits `attack_started("weapon_art")` as it already does. Authoring targets, one per archetype, chosen so each art expresses that weapon's identity:

| Weapon | Art | Effect | Cost | Cooldown |
|--------|-----|--------|------|----------|
| `sword_basic` / `castle_sword` | Guard Break | 1.4x damage, 2.5x poise damage, ignores `ShieldHurtbox` mitigation | 22 | 5 s |
| `greatsword` | Stance Slam | 1.8x damage, hyperarmor for the full startup+active | 34 | 8 s |
| `axe` | Rend | Applies `bleed` x3 regardless of weapon `status_on_hit` | 26 | 6 s |
| `spear` | Charging Thrust | `lunge_distance: 2.4`, narrow hitbox | 26 | 6 s |
| `dagger` | Shadowstep | Backward lunge, 0.25 s i-frames, next attack forced back-arc | 20 | 7 s |
| `staff` | Arcane Nova | Radial hitbox, `arcane` type, applies `stun` x1 | 30 | 9 s |
| `bow` | Piercing Shot | Ignores the `_hit_targets` dedupe so one shot hits a line | 24 | 7 s |

Two of these (Shadowstep i-frames, Nova radial shape) need controller support beyond the current attack dictionary, so the art object also carries `shape` (`"forward" \| "radial" \| "line"`) and `iframes` (seconds, default 0). `_apply_hitbox_profile` gains an art branch keyed on `shape`.

### 3. `scaling` split into damage scaling and granted stats

The current one-dictionary design cannot express "this dagger crits more" without also making it hit harder. Split:

```json
"scaling": { "physicalDamage": 1.0 },
"grants":  { "critChance": 0.12, "moveSpeed": 0.05 }
```

- `scaling` keeps its current meaning but is restricted by the schema to an enum of damage-scaling stats: `physicalDamage`, `fireDamage`, `frostDamage`, `poisonDamage`, `arcaneDamage`, `strength`, `dexterity`, `intellect`. `weapon_scaling_multiplier()` gains an early `continue` for any key outside `DAMAGE_SCALING_KEYS` plus a `push_warning`, so bad content is loud rather than silent.
- `grants` is a flat stat bag merged into the player's talent-stat dictionary by `InventoryService.apply_equipment_to_player_node()` before it calls `set_combat_stat_modifiers`, so a dagger's crit chance flows through the same `crit_chance()` helper as talents.

Migration of the four affected files: `dagger.json` `scaling` becomes `{"physicalDamage": 0.8}` with `grants: {"critChance": 0.15, "moveSpeed": 0.05}`; `staff.json` becomes `scaling: {"arcaneDamage": 1.2}` with `grants: {"staminaRegen": 0.2}`; `bow.json` becomes `scaling: {"dexterity": 1.2}` with `grants: {"critChance": 0.1}`; `greatsword`/`axe`/`spear` keep `physicalDamage` and move `poiseDamage` into `grants`.

### 4. Reach as data

Delete the `match archetype` block and read reach from the weapon:

```json
"hitbox": { "size": [1.0, 0.75, 1.65], "offset": [0.0, 0.0, 0.72] },
"two_hand": { "size_scale": 1.1, "offset_scale": 1.08, "damage_mult": 1.25, "poise_mult": 1.35, "stamina_mult": 1.3, "move_speed_mult": 0.85 }
```

`_apply_hitbox_profile()` reads `hitbox` with the current sword values as the fallback, so removing the block is behavior-preserving once the eight JSONs carry their existing numbers. `two_hand` makes the stance a trade instead of a freebie: `TWO_HAND_POISE_MULT := 1.35` finally gets used, stamina costs rise 30%, and movement during commit drops another 15%.

### 5. Bow as a real projectile

Reuse `scenes/combat/enemy_projectile.tscn` by renaming it `scenes/combat/projectile.tscn` and giving `enemy_projectile.gd` a `team` passthrough (its `Hitbox` child already carries `team`). `_fire_bow_shot()` instantiates it, sets `team = "player"`, and launches with `speed = lerpf(18.0, 34.0, _draw_charge)` and `damage = heavy.damage * lerpf(0.5, 1.5, _draw_charge)`. `_phase_timer` uses the authored `heavy_attack.startup` (0.05 in `bow.json`) instead of the literal `0.08`. The 8 m box branch in `_apply_hitbox_profile` is deleted.

### 6. Per-hit active windows

Replace the single `active` float with an optional `hits` array so a greatsword sweep can confirm twice and a dagger jab once:

```json
"hits": [
  { "at": 0.0,  "damage_scale": 1.0, "poise_scale": 1.0 },
  { "at": 0.12, "damage_scale": 0.6, "poise_scale": 0.4 }
]
```

`at` is an offset in seconds from the start of `ACTIVE`. When `hits` is absent the controller behaves exactly as today (one hit at `at: 0.0`). Each entry calls `Hitbox.reset_swing()` and `set_attack_values()` with the scaled figures, which is also the only way to get multi-hit out of the current dedupe (`hitbox.gd:127-130`).

## Work plan

1. **Land the lunge** — `weapon_controller.gd` caches `_lunge_distance` / `_lunge_duration` in `_start_attack`, implements `get_attack_lunge_velocity()`, and `locomotion.gd:112-123` adds it to `horizontal`. No content change; six weapons come alive immediately. (WEP-01)
2. **Delete the dead buffer block** at `weapon_controller.gd:133-135`. (WEP-11)
3. **Pass crit chance** — `weapon_controller.gd` retains `_equipment_stats` and passes `CombatStatModifiers.crit_chance(_talent_stats)` as the sixth `set_attack_values` argument. Depends on [`combat-core.md`](combat-core.md) step 3. (WEP-04)
4. **Split `scaling` / `grants`** — schema enum + `DAMAGE_SCALING_KEYS` guard in `combat_stat_modifiers.gd`, `grants` merge in `inventory_service.gd`, and migrate the eight weapon JSONs. (WEP-03)
5. **Reach and stance as data** — add `hitbox` and `two_hand` objects to the schema and all eight weapons, then delete the `match archetype` block and the bare `TWO_HAND_*` constants. (WEP-05, WEP-07)
6. **Hyperarmor keys** — allow `hyperarmor` (bool) and `poise_threshold` (number) on `attack_frame_data`, author them on `greatsword` and `axe` heavies. (WEP-06)
7. **Weapon arts** — schema `art` object, `_art_cooldown` in the controller, `shape` branch in `_apply_hitbox_profile`, and the seven authored arts. (WEP-02)
8. **Bow projectile** — generalize `enemy_projectile.tscn`, rewrite `_fire_bow_shot`, delete the 8 m box branch. (WEP-08)
9. **Multi-hit windows** — optional `hits` array plus the `ACTIVE`-phase scheduler. (WEP-09)
10. **Weapon slot validation** — `Equipment.can_equip_in_slot` checks that `weaponId` resolves to an existing file, and `grid_inventory.get_equipped_weapon_data_path()` `push_warning`s on fallback. (WEP-10)

Steps 1-3 are code-only and independently shippable. Steps 4-6 pair a schema change with a content migration in the same commit so `scripts/validate-content` never sees an inconsistent tree.

## Data and schema changes

All changes are to `content/schemas/weapon-definition.v1.json`, which currently sets `additionalProperties: false` at both the root and `$defs/attack_frame_data`.

| Key | Where | Type | Notes |
|-----|-------|------|-------|
| `scaling` | root | object, `additionalProperties: false`, enum'd keys | Restricted to damage-scaling stats |
| `grants` | root | object of numbers | Merged into talent stats at equip time |
| `hitbox` | root | `{ size: [3 numbers], offset: [3 numbers] }` | Replaces the archetype `match` |
| `two_hand` | root | `{ size_scale, offset_scale, damage_mult, poise_mult, stamina_mult, move_speed_mult }` | All numbers, all optional with the current constants as defaults |
| `art` | root | object | `id`, `name`, `stamina_cost`, `damage`, `poise_damage`, `startup`, `active`, `recovery`, `cooldown`, `lunge_distance`, `hyperarmor`, `shape`, `iframes`, `damage_type`, `status`, `status_stacks` |
| `hyperarmor` | `attack_frame_data` | boolean | Already read by `weapon_controller.gd:352` |
| `poise_threshold` | `attack_frame_data` | number, min 0 | Already read by `weapon_controller.gd:354` |
| `hits` | `attack_frame_data` | array of `{ at, damage_scale, poise_scale }` | Optional; absent means one hit at offset 0 |

`content/schemas/item-catalog.v1.json` gains no keys — `weaponId` already exists. No save-format change; `save_migrator.gd` `CURRENT_VERSION` stays at 4. `scripts/validate-content/validate.mjs` picks up the schema automatically.

## Acceptance criteria

- [x] Attacking with `spear` while standing still moves the player forward over startup + half active (authored `lunge_distance`). (WEP-01)
- [x] Attacking with `sword_basic` (no `lunge_distance` on attacks) moves the player 0 m. (WEP-01)
- [x] `locomotion.gd` calls `get_attack_lunge_velocity`. (WEP-01)
- [ ] Pressing `weapon_art` with each of the eight weapons equipped starts an attack named `weapon_art`, spends the authored `stamina_cost`, and is refused for `cooldown` seconds afterward. (WEP-02)
- [ ] Raising the player's class `critChance` stat changes crit frequency and does not change the dagger's non-crit damage figure. (WEP-03, WEP-04)
- [ ] `weapon_controller.gd` contains no `match archetype` block sizing a shape. (WEP-05)
- [ ] A `greatsword` heavy authored with `hyperarmor: true` survives a 30-poise enemy hit without entering stagger. (WEP-06)
- [ ] Two-handing raises light-attack stamina cost from 12 to 15.6 and lowers commit-phase movement speed by 15% relative to one-handing. (WEP-07)
- [ ] A fully drawn bow shot spawns a projectile node that travels and can be blocked by world geometry; no hitbox longer than 1.0 m is ever attached to the player. (WEP-08)
- [ ] An attack authored with two `hits` entries produces two `hit_resolved` emissions against a single stationary target. (WEP-09)
- [ ] Equipping an item whose `weaponId` has no matching file logs a warning and keeps the previous weapon rather than silently loading `sword_basic`. (WEP-10)

## Validation

New suite `apps/game/client/scripts/validation/suites/weapon_suite.gd`, registered in `validation_runner.gd` `SUITE_PATHS` (currently 24 entries, `validation_runner.gd:13-38`), category `"weapons"`.

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `weapon.lunge_matches_data` | Instantiate `player.tscn`, `load_weapon_from_path("content/weapons/spear.json")`, drive `_try_attack("heavy")`, integrate `get_attack_lunge_velocity()` over the startup+half-active window → total displacement within 0.05 m of 0.75 | WEP-01 |
| `weapon.no_lunge_without_data` | Same with `sword_basic.json` → `get_attack_lunge_velocity()` is `Vector3.ZERO` in every phase | WEP-01 |
| `weapon.lunge_has_caller` | `ctx.file_contains("res://scripts/player/locomotion.gd", "get_attack_lunge_velocity")` | WEP-01 |
| `weapon.every_weapon_has_art` | For each file in `content/weapons/`, `ContentLoader.load_json` has a non-empty `art` with `stamina_cost > 0` and `cooldown > 0` | WEP-02 |
| `weapon.art_fires_and_cools_down` | Press-equivalent call to `_try_weapon_art()` twice → first returns an attack, second is refused while `_art_cooldown > 0` | WEP-02 |
| `weapon.scaling_keys_are_damage_only` | For each weapon JSON, every `scaling` key is in `CombatStatModifiers.DAMAGE_SCALING_KEYS` | WEP-03 |
| `weapon.grants_reach_talent_stats` | Equip dagger, assert the dictionary passed to `set_combat_stat_modifiers` contains `critChance >= 0.15` | WEP-03 |
| `weapon.crit_chance_forwarded` | Spy on `Hitbox.set_attack_values` argument count → 6, and the sixth equals `crit_chance(talent_stats)` | WEP-04 |
| `weapon.hitbox_size_from_data` | For each weapon, load it and assert the `BoxShape3D.size` equals the JSON `hitbox.size` | WEP-05 |
| `weapon.hyperarmor_key_allowed` | Author `hyperarmor: true` on a fixture attack and assert `has_hyperarmor()` is true during `ACTIVE` | WEP-06 |
| `weapon.two_hand_costs_more` | Compare `_scaled_stamina_cost` one-handed vs two-handed → ratio equals `two_hand.stamina_mult` | WEP-07 |
| `weapon.bow_spawns_projectile` | Fire a bow shot, count children of `ctx.owner` matching the projectile script → 1; assert no hitbox on the player exceeds 1.0 m on Z | WEP-08 |
| `weapon.multi_hit_windows` | Fixture attack with two `hits` against a stationary `training_grunt` → two `hit_resolved` emissions | WEP-09 |
| `weapon.unknown_weapon_id_warns` | `get_equipped_weapon_data_path()` with a bogus `weaponId` → returns `""` and does not silently return `sword_basic.json` | WEP-10 |

Extend `combat_suite.gd` with `combat.weapon_phase_timings`: drive one full light attack and assert the measured startup/active/recovery durations match `content/weapons/sword_basic.json` within one physics frame — the suite currently asserts nothing about phase timing at all (see [`combat-validation.md`](combat-validation.md) CVA-04).

## Related

- Current behavior: [`../existing_codebase/weapons.md`](../existing_codebase/weapons.md)
- [`combat-core.md`](combat-core.md) — CMB-02/CMB-03 must land for WEP-04
- [`hit-hurtboxes.md`](hit-hurtboxes.md) — `set_attack_values` signature, dedupe behavior for `hits`
- [`stamina-mana.md`](stamina-mana.md) — stamina cost model
- [`guard.md`](guard.md) — riposte multiplier
- [`combat-validation.md`](combat-validation.md), [`content-data.md`](content-data.md), [`content-catalog.md`](content-catalog.md)
- [`diorama-weapon-kit.md`](diorama-weapon-kit.md) — visual half of a weapon
