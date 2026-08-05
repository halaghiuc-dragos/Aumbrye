# Combat core — improvement plan

## Current state

`Hurtbox.receive_hit()` is a single 28-line function that runs i-frames, parry, block, backstab, defense and resistances in a fixed order and then writes to `Health` and `Poise` (see [`../existing_codebase/combat-core.md`](../existing_codebase/combat-core.md)). It works, but three of the four multipliers a player can earn never reach it: `flat_damage_bonus`, `crit_chance` and `poise_damage_multiplier` in `combat_stat_modifiers.gd` have no call sites, so `bonusDamage`, `critChance` and `poiseDamage` from equipment, affixes, talents and relics are aggregated, displayed in the inventory tooltip, and then discarded. The backstab multiplier reads a transform that never rotates and rewards the wrong arc. Poise is a meter that triggers a stagger animation but never gates a single point of damage, and hyperarmor is declared on `WeaponController` and never read by the hurtbox.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CMB-01 | P0 | Backstab is doubly wrong: it reads `body.global_transform.basis.z` on a body that never rotates for the player, and it rewards `angle <= 70` between facing and the attacker — that is a *frontal* hit | `hurtbox.gd:70`, `hurtbox.gd:79`, `locomotion.gd:129-135`, `castle_enemy_base.gd:713-717` |
| CMB-02 | P0 | `bonusDamage` never reaches damage — `flat_damage_bonus()` has no call site, so every flat-damage affix, `physicalDamage`/`fireDamage`/etc. item stat and the `relic_poison_vial` relic are inert | `combat_stat_modifiers.gd:25`, `equipment.gd:150-151`, `content/relics/relic_poison_vial.json:6` |
| CMB-03 | P0 | Crit never fires — `Hitbox._crit_chance` defaults to 0.0 and no caller passes the 6th argument of `set_attack_values` | `hitbox.gd:20,72,135`, `weapon_controller.gd:350`, `castle_enemy_base.gd:643-649`, `enemy_projectile.gd:31` |
| CMB-04 | P1 | Two contradictory defense formulas: the live one is 2%/point capped at 90%, the dead helper is 1%/point uncapped | `hurtbox.gd:8,94` vs `combat_stat_modifiers.gd:41-45` |
| CMB-05 | P1 | Poise never gates damage and hyperarmor is never honored on the receiving side — a hyperarmor attack still takes full poise damage and still staggers | `hurtbox.gd:57-58`, `weapon_controller.gd:208`, `player_combat_reactions.gd:94-95` |
| CMB-06 | P1 | Poise-break duration is a side effect of `REGEN_DELAY := 2.0`, not of authored `stagger_duration` — the meter and the stagger animation disagree | `poise.gd:9,51,33-39`, `player_combat_reactions.gd:6`, `content/enemies/frost_knight.json:16` |
| CMB-07 | P1 | Talent `poiseDamage` is inert — `poise_damage_multiplier()` has no call site | `combat_stat_modifiers.gd:29` |
| CMB-08 | P1 | The player has no resistance table; `_get_resistances()` only resolves through `get_enemy_id()`, so all elemental damage hits the player at 100% | `hurtbox.gd:150-156` |
| CMB-09 | P2 | Damage numbers use one hardcoded red tint; `AccessibilitySettings.get_damage_color()` exists and is never called | `damage_number.gd:34-35`, `accessibility_settings.gd:37` |
| CMB-10 | P2 | `DamageInfo.apply_resistance()` has no upper clamp — a negative resistance amplifies without limit | `damage_info.gd:44-49` |
| CMB-11 | P2 | `damage_number.gd` calls `load()` on the scene for every spawn instead of `preload`ing it | `damage_number.gd:11,22` |

## Target design

### 1. A named, ordered, testable mitigation chain

Replace the inline body of `Hurtbox.receive_hit()` with an explicit resolution struct so every stage is inspectable and every stage is unit-testable without a scene tree. Add `apps/game/client/scripts/combat/damage_resolution.gd`:

```gdscript
extends RefCounted
class_name DamageResolution

var incoming: float          # info.amount as authored
var outgoing: float          # what Health actually loses
var poise_outgoing: float
var crit: bool
var backstab: bool
var blocked: bool
var parried: bool
var dodged: bool
var absorbed_by_poise: bool
var damage_type: String
var stages: Array[Dictionary] # [{ "stage": "defense", "before": 24.0, "after": 19.2 }, ...]
```

`receive_hit()` builds one of these, appends a `stages` entry per step, and emits it:

```gdscript
signal damaged(info: DamageInfo)                  # kept, unchanged, for existing listeners
signal hit_resolved(resolution: DamageResolution) # new, carries the truth
```

`hit_resolved` fires for **every** outcome including dodges and parries, so feedback systems can confirm a dodge (see [`dodge.md`](dodge.md) DDG-01) and damage numbers can show the applied number (see [`hit-feedback.md`](hit-feedback.md) HFB-01). `damaged` stays for backward compatibility and is deprecated in the same PR that migrates `castle_enemy_base.gd:79` and `training_grunt.gd:70`.

### 2. Directional damage, done once and correctly

Backstab, block arc and shield arc each re-derive facing from a different source today. Consolidate on one static in `damage_info.gd`:

```gdscript
enum HitArc { FRONT, SIDE, BACK }

static func classify_arc(victim: Node3D, attacker_position: Vector3) -> HitArc
```

`classify_arc` resolves victim facing in this order: a `Facing` child's `global_transform.basis.z`, then the body's own `basis.z`. Both the player (`Facing` rotates) and enemies (body rotates) then read correctly with one code path. Arc boundaries, as constants on `DamageInfo`:

| Arc | Half-angle from facing | Damage multiplier | Poise multiplier |
|-----|------------------------|-------------------|------------------|
| `FRONT` | 0-60 deg | 1.0 | 1.0 |
| `SIDE` | 60-125 deg | 1.15 | 1.2 |
| `BACK` | 125-180 deg | 1.6 | 2.0 |

`BACK_ARC_HALF_DEGREES := 55.0` (i.e. the back arc spans 110 deg), `BACKSTAB_DAMAGE_MULT := 1.6`, `BACKSTAB_POISE_MULT := 2.0`, `SIDE_DAMAGE_MULT := 1.15`, `SIDE_POISE_MULT := 1.2`. The side tier exists so flanking reads as meaningfully better than facing a target head-on without being a one-shot; 1.6x on the back is chosen over the current 1.5x because the back arc is now genuinely hard to reach against a tracking enemy (`ENEMY_TURN_SPEED` in `castle_enemy_base.gd`).

Rejected alternative: a dedicated backstab *attack* (animation-locked execution). It needs bespoke per-enemy animation and a grab-point contract the diorama rig does not have; a multiplier tier is honest and lands this milestone.

### 3. Poise that actually gates

Poise becomes the stagger currency it looks like, and hyperarmor becomes real:

- **Hyperarmor.** `Hurtbox.receive_hit()` queries the victim's `WeaponController.has_hyperarmor()` (and enemy equivalent `is_hyperarmor_active()`). While active, incoming poise damage is multiplied by `HYPERARMOR_POISE_MULT := 0.25` and the victim cannot enter stagger even if the meter reaches 0 — the break is deferred until the active window ends.
- **Break window.** `Poise` gains `break_duration: float` set by `configure(max_value, break_duration)`. On break, `_broken` stays true for exactly `break_duration` (default 1.2 s), then the meter refills over `REGEN_REFILL_TIME := 1.0` s rather than at a flat rate. This decouples stagger length from `REGEN_DELAY`, fixing CMB-06.
- **Break bonus.** While `is_broken()`, incoming damage is multiplied by `POISE_BROKEN_DAMAGE_MULT := 1.35`. This is the reward for spending an axe heavy (`content/weapons/axe.json` heavy `poise_damage: 50`) on a 70-poise `frost_knight` instead of chipping with light attacks.
- **Data.** `break_duration` is read from `content/enemies/*.json` `stagger_duration` (already authored: `frost_knight.json:16`) and from a new `poise_break_duration` on the class definition for the player.

### 4. All earned stats reach the hit

Wire the four dead statics and delete the duplicate defense math:

```gdscript
# combat_stat_modifiers.gd — signatures unchanged, call sites added
static func flat_damage_bonus(equipment_stats: Dictionary) -> float
static func crit_chance(talent_stats: Dictionary) -> float
static func crit_multiplier(talent_stats: Dictionary) -> float   # new: 1.5 + critDamage
static func poise_damage_multiplier(talent_stats: Dictionary) -> float
```

- `WeaponController._enable_hitbox_for_attack()` adds `flat_damage_bonus(_equipment_stats)` to `dmg` **after** multipliers, multiplies `poise` by `poise_damage_multiplier(_talent_stats)`, and passes `crit_chance(_talent_stats)` as the sixth argument of `set_attack_values`. This requires `WeaponController` to retain `_equipment_stats` (it currently keeps only `_talent_stats` and `_class_stats`, `weapon_controller.gd:72-73`).
- `Hitbox._try_hit()` sets `info.crit = true` when the roll succeeds and uses `crit_multiplier` instead of the hardcoded `1.5` at `hitbox.gd:136`.
- `incoming_damage_multiplier()` is **deleted**. `Hurtbox._apply_defense()` stays the single defense path, and `DEFENSE_PER_POINT := 0.02` with a `DEFENSE_CAP := 0.9` remains the documented number. Rejected alternative: keep the helper and route `_apply_defense` through it — it would require the hurtbox to hold live stat dictionaries, which is exactly what the meta indirection was introduced to avoid.

### 5. Player resistances

`Hurtbox._get_resistances()` gets a second branch: if the body is in the `player` group, read `InventoryService.get_equipment_stats()` keys `resistPhysical`, `resistFire`, `resistFrost`, `resistPoison`, `resistLightning`, `resistArcane` (each a 0.0-0.85 fraction) and return them keyed by `DamageInfo` type constants. `Equipment.STAT_KEYS` gains the six keys. To avoid a per-hit service call, `InventoryService.apply_equipment_to_player_node()` writes the resolved dictionary to a `combat_resistances` meta alongside `combat_defense`, exactly as it already does for defense (`inventory_service.gd:213`), and the hurtbox reads the meta.

### 6. Readable damage numbers

`DamageNumberSpawner` gains a typed entry point and `preload`s the scene:

```gdscript
const SCENE := preload("res://scenes/combat/damage_number.tscn")

static func spawn_resolution(world_position: Vector3, res: DamageResolution, parent: Node) -> void
```

Presentation rules, all driven by `AccessibilitySettings.get_damage_color(res.damage_type)`:

| Outcome | Text | Scale | Lifetime |
|---------|------|-------|----------|
| Normal | `int(round(outgoing))` | 1.0 | 0.65 s |
| Crit | `int(round(outgoing))` + `!` | 1.45 | 0.85 s |
| Backstab | `int(round(outgoing))` | 1.25 | 0.75 s |
| Blocked | `BLOCKED` then chip number | 0.85 | 0.5 s |
| Parried | `PARRIED` | 1.3 | 0.9 s |
| Dodged | `` (no number, VFX only) | — | — |
| Poise break | `STAGGER` | 1.4 | 0.9 s |

At most one number per `hit_resolved`, which also fixes the triple-label case documented as HFB-03.

## Work plan

1. **Add `DamageResolution` and `hit_resolved`** — new `scripts/combat/damage_resolution.gd`; `hurtbox.gd` builds and emits it while keeping `damaged` intact. No behavior change. (CMB-01 prerequisite)
2. **Add `DamageInfo.classify_arc()` and rewrite `_apply_backstab`** — `damage_info.gd` gains `HitArc`, `classify_arc()`, and the five arc constants; `hurtbox.gd:64-81` becomes a table lookup writing `res.backstab`. (CMB-01)
3. **Wire the dead stat helpers** — `weapon_controller.gd` stores `_equipment_stats`, applies `flat_damage_bonus` and `poise_damage_multiplier`, passes `crit_chance`; `hitbox.gd` sets `info.crit` and uses `crit_multiplier`; add `crit_multiplier` to `combat_stat_modifiers.gd`. (CMB-02, CMB-03, CMB-07)
4. **Delete `incoming_damage_multiplier`** and add `DEFENSE_CAP` as a named constant in `hurtbox.gd`. (CMB-04)
5. **Poise gating** — `poise.gd` gains `break_duration`, `POISE_BROKEN_DAMAGE_MULT`, `REGEN_REFILL_TIME`; `hurtbox.gd` queries hyperarmor and applies `HYPERARMOR_POISE_MULT` and the broken-damage bonus; `inventory_service.gd` and `castle_enemy_base.gd` pass `stagger_duration` into `configure()`. (CMB-05, CMB-06)
6. **Player resistances** — six keys into `Equipment.STAT_KEYS`, a `combat_resistances` meta in `inventory_service.gd`, a player branch in `Hurtbox._get_resistances()`, and an upper clamp in `DamageInfo.apply_resistance()`. (CMB-08, CMB-10)
7. **Damage number rework** — `preload` the scene, add `spawn_resolution()`, route color through `AccessibilitySettings.get_damage_color()`, and migrate `hit_feedback.gd` to the single-number path. (CMB-09, CMB-11)

Each step leaves the game runnable: steps 1-2 are additive, 3-6 change tuning behind existing signatures, 7 is presentation only.

## Data and schema changes

| Change | File |
|--------|------|
| `poise_break_duration` (number, seconds, default 1.2) on class definitions | `content/schemas/class-definition.v1.json` |
| `stagger_duration` promoted from convention to a documented required-if-present property, and `poise_break_duration` added | `content/schemas/enemy-definition.v1.json` |
| `resistPhysical`, `resistFire`, `resistFrost`, `resistPoison`, `resistLightning`, `resistArcane` (number, 0-0.85) as item stat keys | `content/schemas/item-catalog.v1.json`, `content/schemas/affix-definition.v1.json` |
| `critDamage` (number, additive to the 1.5 base) as a talent stat key | `content/schemas/talent-tree.v1.json` |

No save-format change: the new stats live on item definitions and talent nodes, both of which are content, and `Equipment.aggregate_stats()` defaults every unknown key to 0.0. `save_migrator.gd` `CURRENT_VERSION` stays at 4.

## Acceptance criteria

- [ ] Attacking a `castle_grunt` from directly behind deals between 1.55x and 1.65x the damage of the same attack from directly in front, and the front attack deals exactly the unmodified figure. (CMB-01)
- [ ] Equipping an item with `bonusDamage: 10` raises the observed light-attack damage on a training dummy by exactly 10 before defense. (CMB-02)
- [ ] With `critChance` forced to 1.0, 20 consecutive light attacks all report `crit == true` on `hit_resolved` and deal `crit_multiplier` times base. (CMB-03)
- [ ] `combat_stat_modifiers.gd` contains no function without a call site under `apps/game/client/scripts/`. (CMB-02, CMB-03, CMB-04, CMB-07)
- [ ] An attack landing during a hyperarmor window transfers at most 25% of its authored `poise_damage` and does not trigger `stagger_started`. (CMB-05)
- [ ] A `frost_knight` broken at 0 poise stays broken for `stagger_duration` seconds (1.0 s from `frost_knight.json:16`), not 2.0 s. (CMB-06)
- [ ] Damage taken while poise-broken is 1.35x the same damage taken at full poise. (CMB-05)
- [ ] With `resistFire: 0.5` equipped, a 40-damage fire hit reduces player HP by 20 before defense. (CMB-08)
- [ ] A single hit produces exactly one damage-number node, and a fire hit's label color equals `AccessibilitySettings.get_damage_color("fire")`. (CMB-09)
- [ ] `apply_resistance(100.0, "fire", {"fire": -5.0})` returns at most 200.0. (CMB-10)

## Validation

Extend `apps/game/client/scripts/validation/suites/combat_suite.gd`. Every assertion below must drive a real `Hurtbox.receive_hit()`, not a string grep — add a `_make_test_victim()` helper that instantiates `res://scenes/enemies/training_grunt.tscn`, adds it to `ctx.owner`, and awaits two physics frames.

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `combat.arc_back_multiplier` | Hit `training_grunt` from `global_position - forward * 2` → `hit_resolved.outgoing` is within 1% of `base * 1.6`; from `+ forward * 2` → equal to `base` | CMB-01 |
| `combat.arc_player_uses_facing` | Rotate the player's `Facing` node 180 deg, hit from world +Z, assert `res.backstab == false` | CMB-01 |
| `combat.flat_damage_bonus_applied` | `set_combat_stat_modifiers({"bonusDamage": 10.0}, {}, {})` then compare `hit_resolved.incoming` deltas | CMB-02 |
| `combat.crit_rolls_and_multiplies` | `crit_chance` 1.0 over 20 hits → all `res.crit`, and `outgoing / base` equals `crit_multiplier` | CMB-03 |
| `combat.defense_single_formula` | `combat_defense` meta 20 → exactly 40% reduction; meta 60 → capped at 90% | CMB-04 |
| `combat.hyperarmor_reduces_poise` | Force `has_hyperarmor()` true, land a 50-poise hit, assert `Poise.current` fell by at most 12.5 and `is_broken()` is false | CMB-05 |
| `combat.poise_break_duration` | `configure(50.0, 1.0)`, break, await 1.1 s → `is_broken()` false; at 0.9 s → still true | CMB-06 |
| `combat.poise_broken_damage_bonus` | Break poise, land a 20-damage hit, assert HP fell by 27 | CMB-05 |
| `combat.player_resistances` | Write `combat_resistances` meta `{"fire": 0.5}`, land a 40-damage fire hit, assert HP fell by 20 | CMB-08 |
| `combat.resistance_upper_clamp` | `DamageInfo.apply_resistance(100.0, "fire", {"fire": -5.0}) <= 200.0` | CMB-10 |
| `combat.one_damage_number_per_hit` | Count `damage_number.tscn` instances under `ctx.owner` before and after a single hit → delta is exactly 1 | CMB-09 |

The suite currently leaks every component it creates (`Health.new()`, `Stamina.new()`, `Poise.new()`, `Hitbox.new()`, `Hurtbox.new()` are `Node`s never freed, `combat_suite.gd:15,31,43,76,78`). Each new test must `free()` what it creates; see [`combat-validation.md`](combat-validation.md) CVA-09.

## Related

- Current behavior: [`../existing_codebase/combat-core.md`](../existing_codebase/combat-core.md)
- [`hit-hurtboxes.md`](hit-hurtboxes.md) — `DamageInfo` production, `damaged` vs `hit_resolved` migration
- [`weapons.md`](weapons.md) — the damage the pipeline receives
- [`guard.md`](guard.md), [`dodge.md`](dodge.md) — pipeline stages 3-4 and 2
- [`hit-feedback.md`](hit-feedback.md) — consumer of `hit_resolved`
- [`statuses-and-buffs.md`](statuses-and-buffs.md) — pipeline stage 10
- [`combat-validation.md`](combat-validation.md) — suite structure
- [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)
