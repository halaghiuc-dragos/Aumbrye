# Combat validation

`combat_suite.gd`, `lock_on_suite.gd`, and `arena_suite.gd` are registered in `validation_runner.gd` with category minimums (`combat: 30`, `lock_on: 4`, `arena: 7`). Behavioral coverage uses `CombatFixture` (`combat_fixture.gd`) to drive `Hurtbox.receive_hit`, team filtering, guard block/parry, dodge stamina, weapon attack input, crit/defense/iframes, hit feedback labels, attack tokens, lock-on public API, and arena reset flows. `content_drift_suite.gd` guards content-vs-code drift. `TestContext` exposes `assert_eq`, `assert_near`, `assert_true`, and an `observed` diff field.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/validation/validation_runner.gd` | Suite list, execution, JSON report, exit code |
| `apps/game/client/scripts/validation/validation_suite.gd` | Base class: holds `ctx`, declares `run()` and `get_category()` |
| `apps/game/client/scripts/validation/test_context.gd` | `TestContext`: `record`, `timed_record`, `assert_eq` / `assert_near` / `assert_true`, `observed`, `file_contains` |
| `apps/game/client/scripts/validation/combat_fixture.gd` | Two-body arena: `strike()`, `direct_hit()`, `teardown()` |
| `apps/game/client/scripts/validation/suites/combat_suite.gd` | Category `combat` — fixture pipeline + weapon/feedback/token tests |
| `apps/game/client/scripts/validation/suites/lock_on_suite.gd` | Category `lock_on` |
| `apps/game/client/scripts/validation/suites/arena_suite.gd` | Category `arena` |

## How it works

`validation_runner.gd` loads suites from `SUITE_PATHS`, awaits `run()`, enforces `MIN_ASSERTIONS` per category (`combat`, `lock_on`, `arena`, `drift`, `quality`, `docs`, …), writes `user://mcp_validation.json`, and quits non-zero on failure.

### combat_suite (behavioral)

Uses `CombatFixture` for `combat.damage_reaches_health`, team filter, defense/resistance, iframes, crit, backstab (including visual-facing case), guard block/parry, dodge stamina deduction, weapon light/heavy/art input, combo reset, lunge motion, and feedback/token assertions (`feedback.one_label_per_hit`, `tokens.concurrent_attackers_capped`, etc.). Legacy tautology `combat.hitbox_team_filter` and guard name greps were removed.

### lock_on_suite

Drives `LockOn.request_lock()` and `cycle_target()`; runtime aim-point and FP-tracking tests replace `file_contains` greps.

### arena_suite

Runtime `reset_duel()`, training death restore, and `PlayerControls.sync_player_loadout()` tests replace file greps for those symbols.

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
| Suite runner, JSON report, exit code | IMPLEMENTED | `validation_runner.gd` |
| `MIN_ASSERTIONS` category gates | IMPLEMENTED | `validation_runner.gd:52`, `:273-274` |
| End-to-end `receive_hit` pipeline | IMPLEMENTED | `combat_fixture.gd` + `combat.damage_reaches_health` |
| Team filter, defense, crit, iframes | IMPLEMENTED | `combat_suite.gd` fixture tests |
| Guard block/parry behavioral | IMPLEMENTED | `guard.block_*` tests; name greps removed |
| Dodge stamina deduction | IMPLEMENTED | `dodge.stamina_deducted` |
| Weapon attack input / combo / lunge | IMPLEMENTED | `weapon.*` tests via `WeaponController` public API |
| Lock-on public input path | IMPLEMENTED | `LockOn.request_lock()` / `cycle_target()` in `lock_on_suite.gd` |
| Arena reset / death restore / loadout | IMPLEMENTED | Runtime tests in `arena_suite.gd` |
| Hit feedback + attack tokens | IMPLEMENTED | `feedback.*`, `tokens.*` in `combat_suite.gd` |
| Content drift checks | IMPLEMENTED | `content_drift_suite.gd` |
| Assertion helpers with diffs | IMPLEMENTED | `test_context.gd` `assert_eq`, `assert_near`, `observed` |
| Fixture teardown / leak hygiene | IMPLEMENTED | `CombatFixture.teardown()` |
| Backstab visual-facing | PARTIAL | `combat.backstab_uses_visual_facing` may fail until [`hit-hurtboxes.md`](hit-hurtboxes.md) HTB gap closed |
| Strict feedback label tests | PARTIAL | `feedback.one_label_per_hit` / `label_matches_hp_lost` are strict regressions |
| Manual combat checklist | IMPLEMENTED | `docs/validation/manual-checklist.md` |

Some strict assertions are intentional regressions for known feel bugs; a fully green run requires the underlying combat-feedback paths to match the documented contract.

## Related

- Improvement plan: [`../actual_improvements/combat-validation.md`](../actual_improvements/combat-validation.md)
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md)
- [`combat-core.md`](combat-core.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`guard.md`](guard.md), [`dodge.md`](dodge.md), [`weapons.md`](weapons.md), [`hit-feedback.md`](hit-feedback.md), [`statuses-and-buffs.md`](statuses-and-buffs.md)
- [`lock-on.md`](lock-on.md), [`debug-arenas.md`](debug-arenas.md)
- [`ci-cd.md`](ci-cd.md) — where the runner exit code is consumed
