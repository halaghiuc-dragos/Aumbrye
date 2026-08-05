# Dodge — improvement plan

## Current state

The dash works: 9.0 m/s for 0.45 s, 32 stamina, a 0.25 s i-frame window from 0.05 s to 0.30 s, lock-on-aware direction, and a 0.25 s recovery lockout (see [`../existing_codebase/dodge.md`](../existing_codebase/dodge.md)). It is also the single most correct answer to every threat in the game, and the game never confirms it. `Hurtbox.receive_hit` returns silently on `iframes_active` — no signal, no flash, no sound, no damage number — so a perfect roll and a missed enemy swing look identical. The dash runs at a constant velocity with no gravity, all eleven tuning numbers are GDScript constants with no equip-weight or class input, and `dodge_started` / `dodge_ended` each fire twice per dash because the direct emissions and the `dash_*` relays are both wired.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DDG-01 | P0 | A successful i-frame dodge produces no feedback of any kind — the only defensive action with a 100% payoff is invisible | `hurtbox.gd:37-39` returns before every feedback path |
| DDG-02 | P0 | `dodge_started` and `dodge_ended` fire twice per dash: emitted directly and relayed from `dash_started`/`dash_ended` | `dodge.gd:40-41` vs `dodge.gd:133-134,183-184` |
| DDG-03 | P1 | No gravity during a dash — `_process_dash` writes only `velocity.x`/`.z` and `locomotion.gd:79-83` returns before its own gravity step, so dashing off a ledge floats | `dodge.gd:163-172`, `locomotion.gd:79-88` |
| DDG-04 | P1 | Constant 9.0 m/s for the whole 0.45 s with no ease-in or ease-out, so the roll has no weight and covers a flat 4.05 m | `dodge.gd:165-166` |
| DDG-05 | P1 | Every dodge number is a GDScript constant; equip weight, class and talents cannot change distance, i-frame length or cost | `dodge.gd:5-15` |
| DDG-06 | P1 | `staminaCostReduction` never applies to dodge or jump, only to weapon attacks | `dodge.gd:94,110` vs `weapon_controller.gd:456-457` |
| DDG-07 | P1 | `poison_hazard.gd` applies statuses directly to the body, bypassing the hurtbox and therefore i-frames | `poison_hazard.gd:35-40` |
| DDG-08 | P2 | The dash cannot be steered or cancelled; `_dodge_direction` is fixed at `_start_dash` and never re-read | `dodge.gd:129-132,163-172` |
| DDG-09 | P2 | Jump is bundled into the dodge script, costs 18 stamina, and has no i-frames, air control or data | `dodge.gd:90-98` |
| DDG-10 | P2 | `_start_dash` calls `_stamina.consume` with no null guard while `_can_dash` explicitly tolerates a missing `Stamina` | `dodge.gd:104,110` |

## Target design

### 1. The dodge confirms itself

This is the single highest-value change in the topic. It depends on `hit_resolved` from [`combat-core.md`](combat-core.md): `Hurtbox.receive_hit` builds a `DamageResolution` with `dodged = true` and emits it *before* returning, instead of returning bare.

On the receiving end:

| Cue | Value | Where |
|-----|-------|-------|
| Time dilation | `Engine.time_scale = 0.55` for 0.09 s, eased back over 0.06 s | `HitFeedback` on `hit_resolved` with `dodged` |
| Trail | `VfxService.play_dodge_trail(from, to, direction)` — a new one-shot ribbon along the dash path | `VfxService` |
| Audio | `AudioDirector.play_combat_sfx("dodge_perfect")` | `HitFeedback` |
| Material | `MaterialFlash.flash(body, 0.4)` in `Color(0.6, 0.85, 1.0)` — a cool tint distinct from the red damage flash | `MaterialFlash` gains a `tint` argument |

A **perfect dodge** tier makes the window worth learning: if the negated hit arrives within `PERFECT_DODGE_WINDOW := 0.12` seconds of `IFRAME_START`, the dodge additionally refunds `PERFECT_DODGE_STAMINA_REFUND := 12.0` stamina and grants `PERFECT_DODGE_DAMAGE_WINDOW := 1.2` seconds during which the next attack deals `PERFECT_DODGE_DAMAGE_MULT := 1.5`. This is the dodge's answer to the guard's riposte, and it gives the i-frame window a skill ceiling rather than a binary.

Rejected alternative: a screen-edge vignette flash. It is cheaper but reads as "you were hit", which is the opposite message.

### 2. Dash movement with weight

Replace the flat velocity with a two-phase curve and restore gravity:

```gdscript
const DODGE_BURST_FRACTION := 0.35   # of DODGE_DURATION spent at peak speed
const DODGE_PEAK_SPEED := 11.0
const DODGE_END_SPEED := 3.0
```

`_process_dash` computes `t = elapsed / DODGE_DURATION` and sets speed to `DODGE_PEAK_SPEED` while `t < 0.35`, then `lerpf(DODGE_PEAK_SPEED, DODGE_END_SPEED, (t - 0.35) / 0.65)` afterward. Total distance stays close to today's 4.05 m (integral ≈ 3.9 m) but the roll now snaps out and settles, which is what makes an i-frame window readable at play speed.

Gravity: `_process_dash` applies `_body.velocity += _body.get_gravity() * delta` before `move_and_slide()` and clamps `velocity.y` to `<= 0.0` when `_body.is_on_floor()`. A dash off a ledge then arcs instead of floating.

### 3. Dodge as data

Move the eleven constants into the class definition and the equip-weight model:

```json
"dodge": {
  "distance": 4.0,
  "duration": 0.45,
  "recovery": 0.25,
  "stamina_cost": 32,
  "iframe_start": 0.05,
  "iframe_end": 0.30,
  "backstep_distance": 2.7
}
```

Equip weight then modulates it. `Equipment` gains a `weight` stat key summed across the nine slots; `InventoryService.apply_equipment_to_player_node()` computes a `dodge_weight_class` and passes it to `Dodge.configure(dodge_data, weight_class)`:

| Weight class | Total `weight` | i-frame duration | Distance | Stamina cost |
|--------------|----------------|------------------|----------|--------------|
| Light | < 25 | 0.30 s | 1.15x | 0.85x |
| Medium | 25-55 | 0.25 s | 1.0x | 1.0x |
| Heavy | > 55 | 0.18 s | 0.8x | 1.25x |

This makes armor a real choice rather than a pure stat gain, and it is the standard idiom for the genre. `staminaCostReduction` applies to dodge and jump through the same `CombatStatModifiers.stamina_cost_multiplier()` the weapon controller already uses, closing DDG-06.

### 4. Steering and cancel

`_process_dash` re-reads the movement input each frame and rotates `_dodge_direction` toward the camera-relative input by at most `DODGE_STEER_DEGREES_PER_SECOND := 90.0`. Full steering would remove the commitment; 90 deg/s over 0.45 s gives roughly 40 deg of correction, which is enough to track a moving target and not enough to reverse a bad read.

A dash may be cancelled into an attack once `elapsed > IFRAME_END` (0.30 s), reusing the existing `_post_dodge_attack_buffer` path in `weapon_controller.gd:452-453`. Cancelling forfeits the remaining dash distance and starts `DODGE_RECOVERY` immediately.

### 5. Jump moves out

Jump is not a dodge and does not belong in this file. Extract `apps/game/client/scripts/player/jump.gd` with `JUMP_VELOCITY`, `COYOTE_TIME`, `JUMP_BUFFER_TIME` and `JUMP_STAMINA_COST` read from the same class `resources`/`movement` block, add a `Jump` node to `player.tscn`, and have `locomotion.gd` call `Jump.process_jump(delta)` where it currently relies on `Dodge._physics_process`. `Dodge` keeps only dash concerns. This is a pure refactor with no behavior change and makes both nodes testable in isolation.

### 6. Hazards respect i-frames

`poison_hazard.gd` stops reaching into `StatusController` directly. It builds a `DamageInfo` with `status_id = poison_status` and `amount = 0.0` and calls `receive_hit` on the body's `Hurtbox`, exactly as `trap_damage_area.gd:31-33` already does. Rolling through a poison pool then works the way a player expects.

## Work plan

1. **Deduplicate the signals** — remove the two direct emissions at `dodge.gd:133-134,183-184` and keep the `dash_*` relays, or vice versa. One-line change, no dependencies. (DDG-02)
2. **Null-guard `_start_dash`** — mirror the `_can_dash` tolerance. (DDG-10)
3. **Hazards through the hurtbox** — rewrite `poison_hazard._apply_poison` to build a `DamageInfo` and call `receive_hit`. (DDG-07)
4. **Gravity and the speed curve** — `DODGE_BURST_FRACTION`, `DODGE_PEAK_SPEED`, `DODGE_END_SPEED`, and the gravity step in `_process_dash`. (DDG-03, DDG-04)
5. **Dodge confirmation** — depends on `hit_resolved` from [`combat-core.md`](combat-core.md) step 1. Add `VfxService.play_dodge_trail`, a `tint` argument on `MaterialFlash.flash`, the `dodge_perfect` audio cue, and the `HitFeedback` handler. (DDG-01)
6. **Perfect dodge tier** — `PERFECT_DODGE_*` constants on `Dodge`, refund through `Stamina`, and a `get_dodge_damage_multiplier()` read by `WeaponController._enable_hitbox_for_attack` alongside the existing riposte multiplier. (DDG-01)
7. **Dodge as data and equip weight** — `dodge` block in the class schema, `weight` in `Equipment.STAT_KEYS`, `Dodge.configure()`, and `stamina_cost_multiplier` applied to dodge and jump. (DDG-05, DDG-06)
8. **Steering and cancel** — `DODGE_STEER_DEGREES_PER_SECOND` in `_process_dash`, cancel window in `weapon_controller.gd`. (DDG-08)
9. **Extract `jump.gd`** — new script and node, `locomotion.gd` call site, `player.tscn` change. (DDG-09)

Steps 1-4 are self-contained. Step 5 is the payoff step and should not be split from step 6, or the perfect-dodge tier ships without a way to perceive it.

## Data and schema changes

| Change | File |
|--------|------|
| `dodge` object: `distance`, `duration`, `recovery`, `stamina_cost`, `iframe_start`, `iframe_end`, `backstep_distance` (all numbers, all optional) | `content/schemas/class-definition.v1.json` |
| `movement` object: `jump_velocity`, `coyote_time`, `jump_buffer_time`, `jump_stamina_cost` | `content/schemas/class-definition.v1.json` |
| `weight` (number, min 0) as an item stat key | `content/schemas/item-catalog.v1.json`, `content/schemas/affix-definition.v1.json` |
| `weight` authored on every armor and weapon item so the three weight classes are reachable | `content/items/*.json` |

The GDScript constants stay as defaults so the arena, the validation suites and any scene without a class continue to work unchanged. No save-format change; `save_migrator.gd` `CURRENT_VERSION` stays at 4.

## Acceptance criteria

- [ ] Dodging through a `castle_knight` swing produces a visible trail, a distinct audio cue, and a brief slowdown. (DDG-01)
- [ ] Dodging within 0.12 s of the i-frame window opening refunds 12 stamina and makes the next attack deal 1.5x damage within 1.2 s. (DDG-01)
- [ ] `dodge_started` fires exactly once per dash. (DDG-02)
- [ ] Dashing off a 3 m ledge results in a downward arc, not horizontal float. (DDG-03)
- [ ] Dash speed at `t = 0.1 s` is higher than at `t = 0.4 s`, and total distance is between 3.7 m and 4.2 m. (DDG-04)
- [ ] Equipping items totaling `weight` above 55 shortens the i-frame window to 0.18 s and raises the stamina cost to 40. (DDG-05)
- [ ] A talent granting `staminaCostReduction: 0.25` lowers the dodge cost from 32 to 24. (DDG-06)
- [ ] Dashing through a poison pool during i-frames applies no `poison` stacks. (DDG-07)
- [ ] Holding a perpendicular input during a dash changes the landing point by at least 1.5 m relative to no input. (DDG-08)
- [ ] `dodge.gd` contains no jump code and `player.tscn` has a `Jump` node. (DDG-09)

## Validation

Extend `apps/game/client/scripts/validation/suites/combat_suite.gd`, replacing `combat.dodge_stamina_cost` (`combat_suite.gd:90-106`), which today only asserts that the string `DODGE_STAMINA_COST` appears in the file.

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `combat.dodge_emits_resolution` | Start a dash, land a hit during i-frames, assert exactly one `hit_resolved` with `dodged == true` and `outgoing == 0.0` | DDG-01 |
| `combat.perfect_dodge_refund` | Land the hit 0.10 s into i-frames → stamina rises by 12 and `get_dodge_damage_multiplier()` returns 1.5 | DDG-01 |
| `combat.dodge_signal_once` | Count `dodge_started` emissions across one dash → 1 | DDG-02 |
| `combat.dodge_applies_gravity` | Start a dash in mid-air, await 0.2 s → `velocity.y < 0.0` | DDG-03 |
| `combat.dodge_speed_curve` | Sample `_dodge_speed` at 0.1 s and 0.4 s → first is strictly greater; integrate distance → within `[3.7, 4.2]` | DDG-04 |
| `combat.dodge_weight_classes` | `configure(data, "heavy")` → i-frame span 0.18 s and cost 40.0; `"light"` → 0.30 s and 27.2 | DDG-05 |
| `combat.dodge_cost_scaled` | `staminaCostReduction: 0.25` → observed spend of 24.0 | DDG-06 |
| `combat.hazard_respects_iframes` | Place the player inside a `poison_hazard`, force `iframes_active`, tick past `tick_interval` → no `poison` in `get_active_statuses()` | DDG-07 |
| `combat.dodge_steering_bounded` | Full perpendicular input for the whole dash → final direction differs from the start by no more than 45 deg | DDG-08 |
| `combat.jump_node_exists` | `player.tscn` has a `Jump` child exposing `process_jump`, and `dodge.gd` contains no `JUMP_VELOCITY` | DDG-09 |

## Related

- Current behavior: [`../existing_codebase/dodge.md`](../existing_codebase/dodge.md)
- [`combat-core.md`](combat-core.md) — `hit_resolved` carries `dodged`
- [`hit-feedback.md`](hit-feedback.md) — dodge confirmation cues
- [`guard.md`](guard.md) — the option dodge is measured against
- [`stamina-mana.md`](stamina-mana.md) — cost and refund
- [`locomotion.md`](locomotion.md) — drives `process_dash_physics`, gains the `Jump` call
- [`weapons.md`](weapons.md) — dodge cancel and the perfect-dodge damage window
- [`combat-hazards.md`](combat-hazards.md) — `poison_hazard` routing
- [`loot-and-equipment.md`](loot-and-equipment.md) — the `weight` stat
