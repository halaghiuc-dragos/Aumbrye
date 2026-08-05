# Combat validation

`combat_suite.gd` is one of 24 suites in `validation_runner.gd:13-38`. Together with `lock_on_suite.gd` and `arena_suite.gd` it is the entire automated combat coverage in the repo. It emits 11 assertions on a clean run, four of which are file-string greps and one of which is a tautology. No test in the repo calls `Hurtbox.receive_hit`, `Hitbox.set_attack_values`, `Guard.modify_incoming_hit` or any attack input.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/validation/validation_runner.gd` | Suite list, execution, JSON report, exit code |
| `apps/game/client/scripts/validation/validation_suite.gd` | Base class: holds `ctx`, declares `run()` and `get_category()` |
| `apps/game/client/scripts/validation/test_context.gd` | `TestContext`: `record`, `timed_record`, `file_contains`, `await_frame`, `await_physics`, `MANUAL_REMAINING` |
| `apps/game/client/scripts/validation/suites/combat_suite.gd` | Category `combat` |
| `apps/game/client/scripts/validation/suites/lock_on_suite.gd` | Category `lock_on` |
| `apps/game/client/scripts/validation/suites/arena_suite.gd` | Category `arena` |

## How it works

`validation_runner.gd:52-94` loads each script in `SUITE_PATHS`, constructs it with the shared `TestContext`, awaits `run()`, and tallies pass/fail deltas per suite. `_write_report()` (`:97`) writes `user://mcp_validation.json` at `schemaVersion: 2` with `passed`, `failed`, per-suite timings, the flat `tests` array and a `coverage` block whose `manual_remaining` is the hardcoded `TestContext.MANUAL_REMAINING` list. `_ready()` quits with exit code 1 if `_ctx.failed > 0`. There is no coverage threshold, no minimum assertion count and no per-suite gate — a suite that records nothing passes.

Assertions are single boolean records. There is no assertion vocabulary (`assert_eq`, `assert_near`, `assert_signal`), no fixture setup or teardown, and no failure diff — `message` is a fixed human string that reads the same whether the test passed or failed.

### combat_suite assertion inventory

| Assertion id | What it actually checks | Kind |
|--------------|-------------------------|------|
| `combat.health_configure_signals` | `Health.new()`, `configure(120)`, `take_damage(10)` -> `current == 110` and `health_changed` fired | Runtime, real |
| `combat.stamina_consume` | `Stamina.new().consume(20)` -> true and `current == 80` | Runtime, real |
| `combat.poise_break` | `Poise.configure(80)`, `take_poise_damage(80)` -> `is_broken()` | Runtime, real |
| `combat.guard_parry_block_api` | `file_contains("guard.gd", "func modify_incoming_hit")` and three more names | File grep |
| `combat.hitbox_team_filter` | Sets `hitbox.team = "player"` and `hurtbox.team = "player"`, then asserts `hitbox.team == hurtbox.team` | Tautology — `combat_suite.gd:76-80` compares two values it just assigned the same literal to; no filtering logic is exercised |
| `combat.dodge_stamina_cost` | Player scene has a `Dodge` node with a script, and `"DODGE_STAMINA_COST" in dodge.gd` | Node presence + file grep |
| `combat.weapon_hitbox_wiring` | `WeaponController.hitbox_path` resolves to a node with an `enable` method | Runtime, structural |
| `combat.player_hitbox_forward` | The hitbox shape sits on the `+Z` side of `Facing` | Runtime, structural |
| `enemy.dies_at_zero_hp` | `castle_shield` overkilled -> `enemy.is_dead()` and `health.is_dead()` | Runtime, real |
| `enemy.no_stagger_revive` | `apply_stagger(1.0)` on a dead shield does not revive it | Runtime, real |
| `enemy.hitbox_disabled_on_death` | `not hitbox.is_active()` after death | Runtime, real |

`enemy.shield_death_guard` (`:152,170`) is a failure-only id recorded when the scene or `Health` node is missing.

### lock_on_suite

Four records. `lock_on.center_aim_api` (`:19`) and `lock_on.fp_policy` (`:28`) are `file_contains` checks for `func get_target_aim_point` and `func _update_lock_on_frame_fp`. `lock_on.reticle_uses_center` (`:60`) is a real runtime check that `LockOn.get_target_aim_point` differs from a naive `+1.5 Y` offset by more than 5 cm. `lock_on.auto_advance_on_death` (`:116-135`) spawns two grunts, calls the private `lock_on._set_lock(enemy_a)`, kills A, then calls the private `lock_on._update_lock(0.0)` and asserts the lock moved to B. It bypasses the public input path entirely, so nothing verifies that pressing `lock_on` acquires a target.

### arena_suite

Seven records. `arena.training_grunt_present`, `arena.grunt_hp_bar`, `arena.hub_return_area` and `arena.wall_collision` instantiate `combat_arena.tscn` and check node structure — six dummies, a `HealthBar` child, a `HubReturn/InteractArea`, four wall `CollisionShape3D`s. `arena.reset_duel_api`, `arena.training_death_reset` and `arena.global_player_controls` are file greps for `func reset_duel`, `func reset_training_player`, `_on_training_player_died` and `func sync_player_loadout`. Nothing swings a weapon in the arena.

### Combat assertions outside these three suites

| Suite | Assertion | Covers |
|-------|-----------|--------|
| `m5_suite.gd:229` | `m5.damage.six_types` | `DamageInfo.ALL_TYPES.size() == 6` |
| `m5_suite.gd:241` | `m5.damage.resistance_pipeline` | `apply_resistance(100, fire, {fire: 0.5}) == 50` and full resist is 0 |
| `m5_suite.gd:253` | `m5.damage.enemy_resistances_data` | `crystal_golem` has a `frost` resistance key |
| `m5_suite.gd:270` | `m5.status.five_definitions` | `StatusCatalog.all_ids()` contains the five expected ids |
| `m5_suite.gd:289` | `m5.status.apply_burn` | `StatusController.debug_apply("burn")` on the player produces one active status |
| `m5_suite.gd:301` | `m5.status.hud_icon_row` | File grep for `_status_row` and `_refresh_status_icons` |
| `m6_suite.gd:281` | Accessibility damage color | The only caller of `AccessibilitySettings.get_damage_color()` in the project |
| `m7_suite.gd:878` | `m7.boss.phase_api` | `is_immune` method exists and `enum Phase` appears in the source |

## Contracts

- **Suite base:** `extends "res://scripts/validation/validation_suite.gd"`, implement `run()` and `get_category()`; the constructor receives the shared `TestContext`.
- **Registration:** add the path to `validation_runner.gd:SUITE_PATHS`. There is no auto-discovery.
- **Recording:** `ctx.timed_record(id, category, passed, message, start_ms, checklist_ref)`. Ids are free-form dotted strings with no uniqueness check.
- **Awaiting:** `ctx.await_frame(n)` and `ctx.await_physics(n)`; nodes are parented to `ctx.owner`.
- **Report:** `user://mcp_validation.json`, `schemaVersion` 2.
- **Headless entry:** `res://scenes/debug/mcp_validation.tscn` or `res://scripts/validation/validation_main.gd` (`validation_runner.gd:5-8`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Suite runner, JSON report, exit code | IMPLEMENTED | `validation_runner.gd:44-124` |
| `Health` / `Stamina` / `Poise` unit behavior | IMPLEMENTED | `combat_suite.gd:15-53` |
| Enemy death guards on `castle_shield` | IMPLEMENTED | `combat_suite.gd:180-217` |
| Player rig structural checks | IMPLEMENTED | `combat_suite.gd:108-143` |
| `combat.hitbox_team_filter` | FAKE | `combat_suite.gd:76-80` asserts `"player" == "player"` after assigning both; passes regardless of `Hitbox._try_hit` behavior |
| `combat.guard_parry_block_api` | FAKE | `combat_suite.gd:56-73` — four `file_contains("func <name>")` greps; passes with empty function bodies |
| `combat.dodge_stamina_cost` | FAKE | `combat_suite.gd:97-98` — greps the source for the constant name; does not read its value or verify it is deducted |
| `lock_on.center_aim_api`, `lock_on.fp_policy` | FAKE | `lock_on_suite.gd:19,28` — file greps |
| `arena.reset_duel_api`, `arena.training_death_reset`, `arena.global_player_controls` | FAKE | `arena_suite.gd:83,92-93,103` — file greps |
| End-to-end damage pipeline | ABSENT | No file under `scripts/validation/` references `receive_hit`, `set_attack_values` or `modify_incoming_hit` outside the four grep string literals at `combat_suite.gd:57-58` |
| Attack input, combo chain, attack cancels | ABSENT | Nothing calls `WeaponController` input or drives `_state` |
| Stamina gating of attacks and dodges | ABSENT | `combat_suite.gd:31-40` tests `Stamina.consume` in isolation; no test drains stamina and asserts an attack is refused |
| Dodge i-frame window | ABSENT | No test sets `is_invulnerable()` and lands a hit |
| Guard block reduction, chip damage, parry window | ABSENT | Only the four-name grep above |
| Backstab multiplier and its direction | ABSENT | Would fail today — see [`hit-hurtboxes.md`](hit-hurtboxes.md) |
| Crit rolls | ABSENT | `Hitbox` supports crits; nothing configures `crit_chance` in a test |
| Defense and `combat_defense` meta | ABSENT | `m5.damage.resistance_pipeline` covers resistances only |
| Poise-gated stagger and hyperarmor | ABSENT | `combat.poise_break` tests `Poise` alone, disconnected from `receive_hit` |
| Status application through combat (as opposed to `debug_apply`) | ABSENT | `m5_suite.gd:286` calls `debug_apply` directly on the player |
| `AttackTokenService` | ABSENT | No suite references it |
| Hit feedback, damage numbers, hitstop | ABSENT | No suite references `HitFeedback` or `damage_number.gd` |
| Weapon JSON to runtime binding | PARTIAL | `m5_suite.gd:312` checks definitions load; nothing asserts the equipped weapon's numbers reach `Hitbox` |
| Content-vs-code drift checks | ABSENT | Nothing fails when a status, weapon stat or relic stat has no reader |
| Leak hygiene | PARTIAL | `combat_suite.gd:15,31,43,76,78` construct `Health`, `Stamina`, `Poise`, `Hitbox` and `Hurtbox` `Node`s that are never added to the tree and never freed |
| Assertion helpers (`assert_eq`, tolerance, diffs) | ABSENT | `test_context.gd` exposes only `record`, `timed_record` and `file_contains` |
| Coverage or minimum-assertion gate | ABSENT | `validation_runner.gd:48` fails only on a recorded failure |
| Manual combat checklist | IMPLEMENTED | `test_context.gd:46-77` lists `M5.weapons.feel`, `M5.status.feel`, `M7.combat.hp_bar_visual`, `M7.combat.shield_feel`, `M7.traps.damage_feel`, `M7.arena.combat_feel` as manual-only |

The net effect: every P0 defect recorded in [`combat-core.md`](combat-core.md), [`weapons.md`](weapons.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`hit-feedback.md`](hit-feedback.md) and [`statuses-and-buffs.md`](statuses-and-buffs.md) is present in a fully green validation run.

## Related

- Improvement plan: [`../actual_improvements/combat-validation.md`](../actual_improvements/combat-validation.md)
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md)
- [`combat-core.md`](combat-core.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`guard.md`](guard.md), [`dodge.md`](dodge.md), [`weapons.md`](weapons.md), [`hit-feedback.md`](hit-feedback.md), [`statuses-and-buffs.md`](statuses-and-buffs.md)
- [`lock-on.md`](lock-on.md), [`debug-arenas.md`](debug-arenas.md)
- [`ci-cd.md`](ci-cd.md) — where the runner exit code is consumed
