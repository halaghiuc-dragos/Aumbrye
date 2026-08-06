# Combat validation — improvement plan

## Status: FINISHED

Current state: [`../existing_codebase/combat-validation.md`](../existing_codebase/combat-validation.md)

## Problem

The combat suite is green and the combat system is broken. Every P0 defect documented across the other eight combat topics — the lunge stub, the inverted backstab, statuses dropped on every enemy, damage numbers showing the wrong figure, mana with no consumer, weapon arts with no data — passes validation today. Eight of the 22 combat-adjacent assertions are `file_contains` greps that a stub function body satisfies, and one asserts that a string literal equals itself.

The fix is not "add more tests". It is to build the two things the harness lacks — a combat fixture that can drive the real pipeline, and a content-vs-code drift check — and then write assertions that would have caught each known defect.

## Gaps

| ID | Priority | Gap | Evidence | Status |
|----|----------|-----|----------|--------|
| CVA-1 | P0 | No test exercises `Hurtbox.receive_hit`; the entire mitigation pipeline is untested | No `receive_hit` reference anywhere under `scripts/validation/` | FINISHED — `combat_fixture.gd` + `combat.damage_reaches_health` |
| CVA-2 | P0 | `combat.hitbox_team_filter` asserts `"player" == "player"` and tests nothing | `combat_suite.gd:76-80` | FINISHED — `combat.team_filter_blocks_friendly` / `combat.team_filter_allows_hostile` |
| CVA-3 | P0 | `combat.guard_parry_block_api` is four `func <name>` greps; empty bodies pass | `combat_suite.gd:56-73` | FINISHED — `guard.block_*` behavioral tests; grep removed |
| CVA-4 | P0 | No content-vs-code drift check; a status, weapon key or relic stat with no reader fails nothing | `m5_suite.gd:263-309` checks definitions load, not that they are consumed | FINISHED — `content_drift_suite.gd` |
| CVA-5 | P1 | `combat.dodge_stamina_cost` greps for a constant name and never verifies the deduction | `combat_suite.gd:97-98` | FINISHED — `dodge.stamina_deducted` |
| CVA-6 | P1 | No attack-input coverage: combo chain, cancel windows, stamina refusal, stun refusal | Nothing drives `WeaponController` | FINISHED — `weapon.*` behavioral tests in `combat_suite.gd` |
| CVA-7 | P1 | No i-frame, backstab, crit, defense or poise-gate assertions | `combat_suite.gd` has no `receive_hit` path | FINISHED — `combat.iframes_block_all_damage`, `combat.defense_reduces_damage`, `combat.crit_applies_multiplier` |
| CVA-8 | P1 | `lock_on_suite` drives private `_set_lock`/`_update_lock` instead of the input path | `lock_on_suite.gd:116,132` | FINISHED — `LockOn.request_lock()` / `cycle_target()`; runtime aim and FP tests |
| CVA-9 | P2 | `TestContext` has no assertion vocabulary; failures report a fixed string with no observed-vs-expected diff | `test_context.gd:89-127` | FINISHED — `assert_eq`, `assert_near`, `assert_true`, `observed` |
| CVA-10 | P2 | Suites leak `Node`s created with `.new()` and never freed | `combat_suite.gd:15,31,43,76,78` | FINISHED — `CombatFixture.teardown()`; unit nodes `.free()` |
| CVA-11 | P2 | No suite covers `HitFeedback`, damage numbers, hitstop or `AttackTokenService` | Not referenced under `scripts/validation/` | FINISHED — `feedback.*` and `tokens.*` in `combat_suite.gd` |
| CVA-12 | P2 | Three `arena_suite` records are file greps | `arena_suite.gd:83,92-93,103` | FINISHED — runtime reset, death-restore, and loadout sync tests |
| CVA-13 | P3 | No coverage gate; a suite that records nothing passes | `validation_runner.gd:48` | FINISHED — `MIN_ASSERTIONS` in `validation_runner.gd` |

## Target design

### 1. A combat fixture

Add `apps/game/client/scripts/validation/combat_fixture.gd`, a `RefCounted` that builds a deterministic two-body arena and exposes the pipeline directly. Everything below depends on it.

```gdscript
class_name CombatFixture extends RefCounted

func _init(ctx: TestContext) -> void
func setup(attacker_id := "player", defender_id := "training_grunt") -> void
func teardown() -> void

var attacker: CharacterBody3D
var defender: CharacterBody3D
var attacker_hitbox: Hitbox
var defender_hurtbox: Hurtbox
var defender_health: Health
var defender_poise: Poise

func place(attacker_pos: Vector3, defender_pos: Vector3, defender_yaw := 0.0) -> void
func strike(overrides := {}) -> Dictionary   # configures the hitbox, enables it, awaits contact, returns the observed result
func hp_lost() -> float                      # defender_health delta since the last strike
func labels() -> Array[Node]                 # damage_number instances spawned since the last strike
func last_cue() -> String                    # last AudioDirector combat cue
```

`strike(overrides)` accepts `{damage, poise_damage, damage_type, crit_chance, status_id, status_stacks, knockback}`, calls `attacker_hitbox.set_attack_values(...)`, `enable()`, awaits two physics frames, and `disable()`. It seeds `RandomNumberGenerator` from a fixed constant so crit rolls are reproducible.

`teardown()` frees every node it created and asserts the arena node count returned to its pre-setup value, which also closes CVA-10.

### 2. Assertion vocabulary

`TestContext` gains helpers that produce real diffs. `message` currently reads identically on pass and fail, which makes a red run useless in CI logs.

```gdscript
func assert_eq(id: String, category: String, actual: Variant, expected: Variant, what: String, ref := "") -> bool
func assert_near(id: String, category: String, actual: float, expected: float, tol: float, what: String, ref := "") -> bool
func assert_true(id: String, category: String, value: bool, what: String, ref := "") -> bool
func assert_in_range(id: String, category: String, value: float, lo: float, hi: float, what: String, ref := "") -> bool
func assert_signal_emitted(id: String, category: String, emitter: Object, sig: String, within_frames: int, what: String, ref := "") -> bool
```

On failure the recorded message becomes `"<what>: expected <expected>, got <actual>"`. `record` gains an optional `observed` field written into the JSON report so the report is diagnosable without a rerun.

`file_contains` is retained but restricted: a new suite may use it only for CI config and documentation existence, never for a behavioral claim. Enforce with a meta-test — see CVA-3 below.

### 3. Combat pipeline assertions

Replace `combat_suite._test_combat_components` with a set built on `CombatFixture`. Numbers below assume `training_grunt` with 60 HP, 40 poise, `combat_defense` 0 unless the test sets it.

| Assertion id | Setup | Expected | Gap |
|--------------|-------|----------|-----|
| `combat.damage_reaches_health` | `strike({damage: 12})` | `hp_lost() == 12.0` within 0.001 | CVA-1 |
| `combat.team_filter_blocks_friendly` | Attacker and defender both `team = "player"` | `hp_lost() == 0.0` and the hurtbox never emits `hit_received` | CVA-2 |
| `combat.team_filter_allows_hostile` | Attacker `player`, defender `enemy` | `hp_lost() == 12.0` | CVA-2 |
| `combat.defense_reduces_damage` | `defender.set_meta("combat_defense", 20)`, `strike({damage: 30})` | `hp_lost()` equals `DamageInfo.apply_defense(30, 20)` within 0.001, and is strictly less than 30 | CVA-7 |
| `combat.resistance_applies_after_defense` | `combat_defense` 10, `frost` resistance 0.5, `strike({damage: 40, damage_type: "frost"})` | Matches defense-then-resistance ordering, not the reverse | CVA-7 |
| `combat.iframes_block_all_damage` | Force `Dodge.is_invulnerable()`, `strike({damage: 40})` | `hp_lost() == 0.0` and no damage number spawned | CVA-7 |
| `combat.backstab_requires_rear_hit` | Attacker at the defender's back, defender facing away | `hp_lost()` equals `12 * BACKSTAB_MULT`; the mirrored front-hit case equals `12` | CVA-7 |
| `combat.backstab_uses_visual_facing` | Rotate only the `Facing` node, keep the body yaw at 0, hit from visual rear | Backstab multiplier applies — fails today, see [`hit-hurtboxes.md`](hit-hurtboxes.md) | CVA-7 |
| `combat.crit_applies_multiplier` | `strike({damage: 10, crit_chance: 1.0})` | `hp_lost() > 10.0` and the resolution reports `crit == true` | CVA-7 |
| `combat.poise_gates_stagger` | `strike({damage: 1, poise_damage: 10})` x3 on 40 poise | No stagger after three; stagger on the fourth | CVA-7 |
| `combat.hyperarmor_survives_stagger` | Defender in a hyperarmor window, `strike({poise_damage: 100})` | Damage lands, no stagger reaction | CVA-7 |
| `combat.status_lands_on_enemy` | `strike({status_id: "bleed", status_stacks: 1})` | Defender's `StatusController.get_active_statuses()` contains `bleed` | CVA-1 |
| `combat.dead_target_absorbs_nothing` | Kill the defender, `strike({damage: 20})` | `hp_lost() == 0.0` and no damage number | CVA-1 |

### 4. Guard and dodge assertions

Replace the four-name grep entirely.

| Assertion id | Setup | Expected | Gap |
|--------------|-------|----------|-----|
| `guard.block_reduces_damage` | Defender guarding, frontal `strike({damage: 30})` | `hp_lost()` equals the authored chip fraction, strictly between 0 and 30 | CVA-3 |
| `guard.block_requires_frontal` | Defender guarding, hit from behind | Full 30 damage | CVA-3 |
| `guard.block_costs_stamina` | Defender guarding at full stamina, one block | Stamina strictly decreased, and the amount scales with incoming damage | CVA-3 |
| `guard.guard_break_on_empty_stamina` | Block until stamina hits 0 | Guard drops and a guard-break reaction fires | CVA-3 |
| `guard.parry_window_timing` | Raise guard, strike at 0.05 s, 0.15 s and 0.40 s after | Parry succeeds inside the authored window and fails outside it, asserted against the constant rather than a literal | CVA-3 |
| `guard.parry_emits_signal` | Successful parry | `parry_success` emitted within 2 frames | CVA-3 |
| `dodge.stamina_deducted` | Read stamina, call the dodge entry point, read again | Delta equals `Dodge.DODGE_STAMINA_COST` within 0.001 — reads the constant's value, not its name | CVA-5 |
| `dodge.refused_without_stamina` | Drain stamina below the cost, request a dodge | No dodge state, no stamina change | CVA-5 |
| `dodge.iframe_window_bounds` | Start a dodge, sample `is_invulnerable()` each physics frame | True inside the authored window, false before and after, tolerance one frame | CVA-7 |

### 5. Attack input and weapon binding

| Assertion id | Setup | Expected | Gap |
|--------------|-------|----------|-----|
| `weapon.light_attack_enables_hitbox` | Drive the attack entry point | `Hitbox.is_active()` becomes true during the active window and false outside it | CVA-6 |
| `weapon.combo_advances` | Two attacks inside the chain window | The second attack uses index 1 of the weapon's attack list | CVA-6 |
| `weapon.combo_resets` | Two attacks separated by more than the chain window | Both use index 0 | CVA-6 |
| `weapon.attack_refused_without_stamina` | Drain stamina, attack | No hitbox activation, no state change | CVA-6 |
| `weapon.attack_refused_while_stunned` | Apply `stun`, attack | No hitbox activation | CVA-6 |
| `weapon.json_values_reach_hitbox` | Equip `greatsword`, run its first attack | The hitbox's damage equals the JSON `damage` times the equipment multiplier, within 0.001 | CVA-6 |
| `weapon.lunge_moves_the_body` | Attack with an authored `lunge_distance` | The body's XZ displacement during startup is at least 70 percent of `lunge_distance` — fails today, see [`weapons.md`](weapons.md) | CVA-6 |
| `weapon.art_input_produces_an_attack` | Equip a weapon with an authored `art`, press the art input | Hitbox activates with the art's damage — currently unreachable, see [`weapons.md`](weapons.md) | CVA-4 |

### 6. Content-vs-code drift suite

New suite `apps/game/client/scripts/validation/suites/content_drift_suite.gd`, category `drift`, registered in `validation_runner.gd:SUITE_PATHS` after `content_suite`. This is the assertion class that would have caught most of the documented defects, and it is the highest-value item here.

| Assertion id | Rule |
|--------------|------|
| `drift.every_status_has_an_applier` | Every id in `StatusCatalog.all_ids()` appears as a `status_on_hit` or `status` value in `content/enemies/`, `content/bosses/`, `content/weapons/` or `content/hazards/`, or in an `apply_status("<id>"` call outside `combat_hud.gd` and `scripts/validation/`. Fails today for `burn` and `stun` |
| `drift.every_relic_stat_is_read` | The union of keys across every `content/relics/*.json` `stats` object is a subset of a `READ_STATS` constant maintained in the suite. Fails today for `attackSpeed`, `lifesteal`, `healthRegen`, `frostDamage`, `poisonDamage` |
| `drift.every_weapon_key_is_read` | Every property name in `content/schemas/weapon-definition.v1.json` appears in a `get("<key>"` or `["<key>"]` access under `apps/game/client/scripts/`. Fails today for the authored-but-unread keys listed in [`weapons.md`](weapons.md) |
| `drift.every_schema_property_is_authored` | Every non-required schema property is used by at least one content file, or is listed in an explicit `PLANNED` allowlist with a doc link |
| `drift.no_stubbed_public_returns` | Public functions returning a bare `Vector3.ZERO`, `{}` or `0.0` with no other statement are listed in a `KNOWN_STUBS` constant; a new one fails the build. Catches `WeaponController.get_attack_lunge_velocity()` |
| `drift.every_component_node_exists` | For each `(scene_glob, required_child)` pair — every enemy scene needs `Health`, `Hurtbox`, `StatusController`, `HitFeedback` — assert the child exists. Fails today for `StatusController` and `HitFeedback` on every enemy |
| `drift.no_behavioral_file_greps` | Scan `scripts/validation/suites/*.gd` for `file_contains(` calls whose needle starts with `"func "`; the set must be a subset of a shrinking `LEGACY_GREPS` allowlist. Enforces CVA-3 and prevents regression |

Each drift failure must name the offending id or key in `observed`, so the CI log is actionable without a local run.

### 7. Feedback assertions

Add to `combat_suite` once `DamageResolution` exists (see [`hit-feedback.md`](hit-feedback.md)):

| Assertion id | Expected |
|--------------|----------|
| `feedback.one_label_per_hit` | `labels().size() == 1` after a blocked hit; 2 today |
| `feedback.label_matches_hp_lost` | `int(labels()[0].text) == int(round(hp_lost()))` for normal, crit, backstab, resisted and blocked hits |
| `feedback.dodge_produces_a_cue` | An i-frame dodge produces a non-empty `last_cue()` |
| `feedback.hitstop_scales_with_damage` | Hitstop duration for 48 damage strictly exceeds that for 12 |
| `tokens.concurrent_attackers_capped` | Six enemies request attack tokens against one player; at most the configured cap hold one simultaneously |
| `tokens.released_on_death` | Kill a token holder; the token count returns to its pre-acquisition value |

### 8. Lock-on through the public path

`lock_on_suite` stops calling `_set_lock` and `_update_lock`. Add `LockOn.request_lock()` and `LockOn.cycle_target(direction: int)` as the public API the input handler already needs, and drive those. Keep the existing death-advance assertion but reach the initial lock through `request_lock()`. Replace `lock_on.center_aim_api` and `lock_on.fp_policy` with runtime checks: call `get_target_aim_point` and assert it lies inside the target's visual AABB, and switch to first-person and assert the camera basis tracks the target within 2 degrees after 0.5 s. (CVA-8, CVA-12)

### 9. Coverage gate

`validation_runner.gd` gains a per-category minimum:

```gdscript
const MIN_ASSERTIONS := {"combat": 30, "drift": 7, "lock_on": 4, "arena": 7}
```

`_write_report()` records a `runner.coverage_<category>` failure when a category records fewer than its minimum, so deleting or short-circuiting a suite turns CI red instead of green. (CVA-13)

## Sequencing

1. `CombatFixture` and the assertion vocabulary. Nothing else can be written without them. (CVA-9, CVA-10)
2. Section 3 pipeline assertions, replacing `combat.hitbox_team_filter`. (CVA-1, CVA-2, CVA-7)
3. `content_drift_suite`, including `drift.no_behavioral_file_greps`. (CVA-4, CVA-3)
4. Sections 4 and 5 — guard, dodge, attack input, weapon binding. (CVA-3, CVA-5, CVA-6)
5. Section 7 feedback and token assertions, after `DamageResolution` lands.
6. Sections 8 and 9. (CVA-8, CVA-12, CVA-13)

Steps 2 and 3 are the ones that turn the suite red. Expect roughly 15 new failures on the first green-to-red transition, one per P0 documented across the combat topics; that is the point.

## Related

- [`combat-core.md`](combat-core.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`guard.md`](guard.md), [`dodge.md`](dodge.md), [`weapons.md`](weapons.md), [`stamina-mana.md`](stamina-mana.md), [`hit-feedback.md`](hit-feedback.md), [`statuses-and-buffs.md`](statuses-and-buffs.md) — every assertion above maps to a gap in one of these
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md) — runner and suite conventions
- [`ci-cd.md`](ci-cd.md) — where the exit code and coverage gate are enforced
