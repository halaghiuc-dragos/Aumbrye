# Stamina and mana — improvement plan

## Status: FINISHED

## Current state

`Stamina` works and is genuinely load-bearing: eight call sites spend it and equipment scales both its cap and its regen (see [`../existing_codebase/stamina-mana.md`](../existing_codebase/stamina-mana.md)). `Mana` is a complete resource node with a HUD bar and zero spenders — `consume`, `drain`, `has`, `configure` and `reset_mana` have no callers anywhere under `apps/game/client/scripts/`, so the bar sits at 100% for an entire run. Beyond that, stamina has no teeth: regen is not suppressed while attacking or blocking, the `depleted` and `insufficient` signals have no listeners so a refused attack is silent, and `drain()` bypasses the exhaustion gate that `consume()` enforces.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| RES-01 | P0 | `Mana` is a dead resource with a live HUD bar: no gameplay caller for `consume`, `drain`, `has`, `configure` or `reset_mana`; the bar renders permanently full | `mana.gd:22,39,51,62,66`; only reader is `combat_hud.gd:365-374,473-477` |
| RES-02 | P0 | Nothing tells the player a spend was refused — `insufficient` and `depleted` are declared on both nodes and connected nowhere | `stamina.gd:6-7`, `mana.gd:6-7`; no `.insufficient.connect` or `.depleted.connect` under `apps/` |
| RES-03 | P1 | Stamina regenerates during attacks, blocks and dodges; the only brake is a flat 0.7 s post-spend delay, so mashing never runs the bar dry the way the costs imply | `stamina.gd:33-41` |
| RES-04 | P1 | `drain()` ignores `_exhausted` and never emits `insufficient`, so sprinting can pull the bar from 14 to 0 while `consume()` would refuse the same spend | `stamina.gd:60-69` vs `stamina.gd:44-50` |
| RES-05 | P1 | Exhaustion has no consequence other than refusal — no slowed regen, no stagger vulnerability, no animation, no HUD state | `stamina.gd:34,73-79`; `_exhausted` is read only by `consume()` and `has()` |
| RES-06 | P1 | The bow shot bypasses `staminaCostReduction` while every other attack honors it | `weapon_controller.gd:402` vs `weapon_controller.gd:273,456-457` |
| RES-07 | P1 | `Mana` is never scaled by equipment, class or talents, unlike `Health`, `Stamina` and `Poise` | `inventory_service.gd:187-198` |
| RES-08 | P2 | `configure()` clamps `current` down but never up, so equipping a `staminaMax` item leaves the new headroom empty until natural regen fills it | `stamina.gd:26`, `mana.gd:24` |
| RES-09 | P2 | Regen rate, delay and exhaustion threshold are GDScript constants; classes and weapons cannot express a stamina identity | `stamina.gd:8-11` |
| RES-10 | P2 | `mana_potion` appears in waves reward tables with no consumption path that restores mana | `waves_run_service.gd:28-29,34` |

## Target design

### 1. Mana becomes the cost of everything that is not a swing

Deleting `Mana` would be the cheap answer. It is the wrong one: the game already ships a `staff` weapon with `damage_type: "arcane"`, five statuses including `burn` and `freeze` with nobody to apply them, a `relic` equipment slot, and a talent tree. Mana is the resource those systems need. Make it real by giving it three spenders:

**Weapon arts.** Every art authored in [`weapons.md`](weapons.md) gains a `mana_cost` alongside `stamina_cost`. Physical archetypes cost 0 mana and full stamina; the `staff` art costs 0 stamina and 35 mana. This makes the staff play differently rather than being a reskinned sword.

**Casting from the staff archetype.** When `get_archetype() == "staff"`, `WeaponController` routes `heavy_attack` through a cast path that spends `mana_cost` instead of `stamina_cost` and applies the weapon's `status_on_hit`. `staff.json` gains `"mana_cost": 18` on its heavy and `"status": "burn"`.

**Healing.** `player_heal.gd` currently spends `HEAL_STAMINA_COST`. Move it to mana: a heal that competes with dodging for the same bar is a design that punishes the correct defensive answer. `PlayerHeal` spends `HEAL_MANA_COST := 40.0` and keeps a small `HEAL_STAMINA_COST := 10.0` so it is not free while exhausted.

`Mana` also gets the equipment wiring `Stamina` already has:

```gdscript
# inventory_service.gd, alongside the existing Stamina block
var mana := player.get_node_or_null("Mana") as Mana
if mana:
    var max_mana := Mana.MAX_MANA + CombatStatModifiers.max_mana_bonus(equip_stats, talent_stats)
    mana.configure(max_mana, CombatStatModifiers.mana_regen_multiplier(talent_stats))
```

with two new statics in `combat_stat_modifiers.gd` reading `manaMax` and `manaRegen`, and both keys added to `Equipment.STAT_KEYS`.

Rejected alternative: repurpose the mana bar as a "focus" meter that fills on hits. It is a second economy to tune and balance before the first one (stamina) is honest, and it orphans the `mana_potion` item and the `arcane` damage type that already exist.

### 2. Regen that respects combat

Replace the single 0.7 s delay with an explicit gate:

```gdscript
# stamina.gd
const REGEN_DELAY := 0.7
const REGEN_RATE := 25.0
const REGEN_RATE_EXHAUSTED := 12.0     # half rate until the exhaustion threshold clears
const REGEN_RATE_BLOCKING := 6.0       # a trickle while the guard is up
const EXHAUSTION_RECOVERY := 15.0

func set_regen_state(state: RegenState) -> void   # NORMAL, BLOCKING, SUPPRESSED
```

`RegenState.SUPPRESSED` (rate 0) is set by `WeaponController` for the whole attack (`_start_attack` → `_end_attack`) and by `Dodge` for the dodge duration. `RegenState.BLOCKING` is set by `Guard` between `_enter_guard` and `_end_guard`. Everything else is `NORMAL`. The callers already have exact start/stop points, so no polling is needed.

With this in place the numbers finally mean something: a `greatsword` heavy costs 38 and suppresses regen for `0.5 + 0.22 + 0.55 = 1.27 s` plus the 0.7 s delay, so back-to-back heavies drain the bar in three swings. Today they drain it in five and refill between each.

### 3. Exhaustion is a state, not a boolean

While `is_exhausted()`:

- Regen runs at `REGEN_RATE_EXHAUSTED := 12.0` until `current >= EXHAUSTION_RECOVERY`.
- `Locomotion` caps movement at `WALK_SPEED * 0.75` (a new `get_speed_multiplier()` query on `Stamina`, so the coupling is one-directional).
- Incoming poise damage is multiplied by `EXHAUSTED_POISE_MULT := 1.5` — read by `Hurtbox.receive_hit` alongside the hyperarmor query from [`combat-core.md`](combat-core.md).
- The HUD stamina bar tints to `Color(0.55, 0.22, 0.18)` and `AudioDirector.play_combat_sfx("exhausted")` fires once on the `depleted` signal.

### 4. Refusals are audible and visible

`Stamina.insufficient` and `Mana.insufficient` gain real listeners in `combat_hud.gd`:

```gdscript
func _on_stamina_insufficient() -> void:
    _flash_bar(_stamina_bar, Color(0.9, 0.3, 0.25), 0.18)
    AudioDirector.play_combat_sfx("resource_denied")
```

`drain()` is aligned with `consume()`: it refuses while `_exhausted`, emits `insufficient` on failure, and keeps its distinguishing behavior (per-frame partial spend without the full-cost check). Sprinting into exhaustion then drops to walk speed with a bar flash instead of silently continuing.

### 5. Tuning as data

Move the six constants into class definitions so a heavy class and a rogue class differ:

```json
"resources": {
  "stamina_max": 100, "stamina_regen": 25.0, "stamina_regen_delay": 0.7, "exhaustion_recovery": 15.0,
  "mana_max": 100, "mana_regen": 20.0, "mana_regen_delay": 0.7
}
```

The GDScript constants stay as defaults for scenes without a class (arena, validation), so nothing breaks when the block is absent.

### 6. Consumables

`mana_potion` becomes functional in the same pass: the item consumption path restores `40.0` mana, and `configure()` gains a `preserve_ratio: bool = false` argument so raising the cap can optionally scale `current` proportionally instead of leaving the new headroom empty.

## Work plan

1. **Refusal feedback** — connect `insufficient` and `depleted` in `combat_hud.gd`, add `_flash_bar`, add the two `AudioDirector` cues. Purely additive. (RES-02)
2. **Align `drain()` with `consume()`** — exhaustion check plus `insufficient` emission in `stamina.gd:60`. (RES-04)
3. **Fix the bow cost** — route `weapon_controller.gd:402` through `_scaled_stamina_cost()`. (RES-06)
4. **Regen states** — `RegenState` enum and `set_regen_state()` on `Stamina`; calls from `WeaponController._start_attack`/`_end_attack`, `Dodge._start_dash`/`_end_dash`, `Guard._enter_guard`/`_end_guard`. (RES-03)
5. **Exhaustion consequences** — `REGEN_RATE_EXHAUSTED`, `get_speed_multiplier()` read by `locomotion.gd`, `EXHAUSTED_POISE_MULT` read by `hurtbox.gd`, HUD tint. (RES-05)
6. **Mana wiring** — `max_mana_bonus` / `mana_regen_multiplier` statics, `manaMax` / `manaRegen` in `Equipment.STAT_KEYS`, the `Mana` block in `inventory_service.gd`. Mana is still unspent at this point but is now scalable. (RES-07)
7. **Mana spenders** — `mana_cost` on weapon arts, the staff cast path, and `player_heal.gd` moving to mana. This is the step that closes RES-01 and depends on [`weapons.md`](weapons.md) step 7. (RES-01)
8. **Resource tuning as data** — `resources` block in the class schema, read at `apply_equipment_to_player_node()` time. (RES-09)
9. **Potions and `preserve_ratio`** — consumable restoration path plus the `configure()` argument. (RES-08, RES-10)

Steps 1-6 are independently shippable and leave mana visibly unused but honestly scaled; step 7 is the one that must not ship before weapon arts exist, or the mana bar would still be decorative.

## Data and schema changes

| Change | File |
|--------|------|
| `resources` object: `stamina_max`, `stamina_regen`, `stamina_regen_delay`, `exhaustion_recovery`, `mana_max`, `mana_regen`, `mana_regen_delay` (all numbers, all optional) | `content/schemas/class-definition.v1.json` |
| `manaMax`, `manaRegen` as item stat keys | `content/schemas/item-catalog.v1.json`, `content/schemas/affix-definition.v1.json` |
| `mana_cost` (number, min 0) on the weapon `art` object and on `attack_frame_data` | `content/schemas/weapon-definition.v1.json` |
| `"mana_cost": 18` and `"status": "burn"` on the staff heavy | `content/weapons/staff.json` |
| `manaRestore` (number) on consumable item definitions | `content/schemas/item-catalog.v1.json` |

No save-format change: resource values are runtime state restored from `Health`/`Stamina` reset on run start (`run_flow.gd:455`), and the new keys are content. `save_migrator.gd` `CURRENT_VERSION` stays at 4.

## Acceptance criteria

- [ ] Casting the staff heavy reduces the mana bar by 18 and refuses when mana is below 18. (RES-01)
- [ ] The mana bar is observably below 100% at some point in a normal castle run. (RES-01)
- [ ] Attempting a dodge with 10 stamina flashes the stamina bar and plays a denial cue. (RES-02)
- [ ] Holding light attack against a training dummy with `sword_basic` drains stamina to 0 within 9 swings and does not regenerate between them. (RES-03)
- [ ] Sprinting from 14 stamina stops at the exhaustion gate and drops to walk speed rather than draining to 0. (RES-04)
- [ ] While exhausted, movement speed is 75% of walk and incoming poise damage is 1.5x. (RES-05)
- [ ] A talent granting `staminaCostReduction: 0.25` reduces the bow shot cost from 18 to 13.5. (RES-06)
- [ ] Equipping an item with `manaMax: 30` raises the mana bar's maximum to 130. (RES-07)
- [ ] Equipping a `staminaMax: 20` item with `preserve_ratio` enabled keeps the fill percentage constant. (RES-08)
- [ ] A class definition with `"stamina_regen": 40.0` regenerates measurably faster than one with 25.0. (RES-09)
- [ ] Using a `mana_potion` restores 40 mana. (RES-10)

## Validation

Extend `apps/game/client/scripts/validation/suites/combat_suite.gd` — it currently contains exactly one stamina assertion (`combat.stamina_consume`, `combat_suite.gd:30-40`) and none for mana.

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `combat.mana_has_gameplay_caller` | Grep `apps/game/client/scripts/` for `Mana` `consume(` outside `mana.gd` and the HUD → at least one hit | RES-01 |
| `combat.staff_cast_spends_mana` | Load `staff.json`, drive the heavy, assert `Mana.current` fell by the authored `mana_cost` and `Stamina.current` did not | RES-01 |
| `combat.insufficient_signal_connected` | `Stamina.insufficient.get_connections()` is non-empty after `combat_hud` binds the player | RES-02 |
| `combat.regen_suppressed_during_attack` | Spend 20, start an attack, await the full attack duration, assert `current` is unchanged | RES-03 |
| `combat.drain_respects_exhaustion` | Force `_exhausted`, `drain(1.0)` returns false and emits `insufficient` | RES-04 |
| `combat.exhausted_speed_and_poise` | Force exhaustion → `get_speed_multiplier() == 0.75`; land a 20-poise hit → `Poise.current` fell by 30 | RES-05 |
| `combat.bow_cost_scaled` | `set_combat_stat_modifiers({}, {"staminaCostReduction": 0.25}, {})`, fire a bow shot, assert the spend was 13.5 | RES-06 |
| `combat.mana_scales_with_equipment` | `apply_equipment_to_player_node` with `manaMax: 30` → `Mana.max_mana == 130.0` | RES-07 |
| `combat.configure_preserves_ratio` | `current = 50`, `configure(200.0, 1.0, true)` → `current == 100.0` | RES-08 |
| `combat.class_resources_applied` | Fixture class with `stamina_regen: 40.0` → `Stamina._regen_multiplier * REGEN_RATE == 40.0` | RES-09 |

Every component the suite creates with `.new()` must be `free()`d; see [`combat-validation.md`](combat-validation.md) CVA-09.

## Related

- Current behavior: [`../existing_codebase/stamina-mana.md`](../existing_codebase/stamina-mana.md)
- [`weapons.md`](weapons.md) — `mana_cost` on arts, the staff cast path
- [`dodge.md`](dodge.md), [`guard.md`](guard.md) — regen-state callers
- [`combat-core.md`](combat-core.md) — `EXHAUSTED_POISE_MULT` in the hurtbox
- [`player-heal.md`](player-heal.md) — moves from stamina to mana
- [`ui/combat_hud.md`](ui/combat_hud.md) — bar tint and denial feedback
- [`content-data.md`](content-data.md), [`inventory-service.md`](inventory-service.md)
