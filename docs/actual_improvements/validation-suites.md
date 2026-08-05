# Validation suites — improvement plan

## Current state

24 suites, 304 assertion call sites, all registered (see [`../existing_codebase/validation-suites.md`](../existing_codebase/validation-suites.md)). Two P0 problems: seven assertions demand documentation files that do not exist, so the run fails on every invocation for reasons unrelated to code, and the networking layer has no functional test, which is why a one-word bug has kept cloud save pull broken indefinitely. Beneath those, 116 of the assertions are substring greps or path-existence checks, and 47 percent of the total sits in three milestone-shaped suites that do not localize a failure to a subsystem.

## Gaps

Carried from [`../existing_codebase/validation-suites.md`](../existing_codebase/validation-suites.md): VSU-01 through VSU-17.

## Target design

### 1. Green baseline (VSU-01)

Seven assertions reference paths that are not on disk. Two options, and the choice differs per file:

| Test id | Path | Action |
|---------|------|--------|
| `progression.run_economy_doc` | `docs/plan/systems/13-PROGRESSION.md` | Repoint at `docs/existing_codebase/progression-service.md` |
| `m5.balance.doc_exists`, `m6.balance.doc` | `docs/plan/systems/24-BALANCING.md` | Repoint at `docs/existing_codebase/content-data.md`, and deduplicate: one test, not two |
| `m6.perf.doc` | `docs/plan/systems/20-PERFORMANCE.md` | Delete. The real performance gate is VSU-05 below, not a file's existence |
| `m7.ship.manual_checklist` | `docs/plan/07-EA-DEFINITION-OF-DONE.md` | Repoint at `docs/validation/manual-checklist.md`, created by [`validation-harness.md`](validation-harness.md) step 10 |
| `m7.schema.migration_doc` | `docs/SAVE_MIGRATIONS.md` | Repoint at `docs/existing_codebase/save-migrator.md` |
| `m7.ship.known_issues_doc` | `docs/design/AUDIT_2026-08.md` | Delete. A dated audit file is not a standing invariant |

Then add one durable guard instead of seven brittle ones: `docs_suite.gd` asserts that every path referenced by any suite exists, and that every relative link in `docs/existing_codebase/**` and `docs/actual_improvements/**` resolves. A doc path referenced from a test never rots again, and the check lives in one place.

A green baseline is a precondition for everything else in this plan. Until the run passes, no new failure is distinguishable from the standing seven.

### 2. Test the untested subsystems (VSU-02, VSU-10)

Three new suites, each specified in the owning topic's plan so the assertions and the code land together:

| Suite | Specified in | Covers |
|-------|--------------|--------|
| `net_suite.gd` | [`networking.md`](networking.md) | 18 tests: transport shape, timeout, retry, 426 and 429, session persistence, save round trip, offline no-request guarantee, leaderboard tier |
| `platform_suite.gd` | [`platform-and-net.md`](platform-and-net.md) | 13 tests: Steam stub semantics, app-id priority, shutdown idempotency, crash payload fields, retention, upload opt-out, path scrubbing |
| `export_suite.gd` | [`export-tools.md`](export-tools.md) | Exporter determinism, clip coverage, exit code on failure |

Plus `harness_suite.gd` from [`validation-harness.md`](validation-harness.md), and:

| Suite | Covers |
|-------|--------|
| `debug_suite.gd` | Debug overlay toggles, seed display, the arena teleport, and that debug affordances are absent from a release build |
| `ui_suite.gd` | Focus traversal through every menu, keyboard-only navigation of the main menu, pause menu, inventory, and settings, and that every interactive `Control` has a focus mode and an accessible name |
| `a11y_suite.gd` | Colorblind palette application, text scaling, reduced motion honored by `VfxService`, subtitle rendering |
| `error_paths_suite.gd` | Corrupt save recovery, missing content file, malformed dungeon definition, unwritable save directory, unknown item id in an inventory slot |

Nine new suites brings the total to 33. That is a lot of registration churn; `harness.registration.every_suite_file_is_registered` from [`validation-harness.md`](validation-harness.md) makes the parity self-enforcing.

### 3. Replace grep assertions with behavior (VSU-03, VSU-04, VSU-05, VSU-16)

The rule going forward: a substring or `has_method` assertion is acceptable only when the alternative is impossible headless, and then it must be a `skip` with a reason, not a pass.

Concrete conversions, highest value first:

- `perf.vfx_burst_pool` (`perf_gate_suite.gd:19-26`) currently greps for `_burst_pool` and `_acquire_burst`. Replace with: request 200 bursts through `VfxService`, assert the number of `CPUParticles3D` children never exceeds the pool cap, and assert that releasing and re-requesting reuses an instance rather than allocating.
- `perf.headless_budget_gate` (`perf_gate_suite.gd:36-38`) currently passes `true`. Replace with real headless-measurable budgets, which are not frame time but are still meaningful:

| New test | Budget |
|----------|--------|
| `perf.dungeon_build_ms` | Building a tier-1 dungeon from a definition completes in under 1500 ms |
| `perf.procgen_generate_ms` | `LocalProcgen.generate` for a tier-1 floor completes in under 250 ms |
| `perf.save_write_ms` | A full save write completes in under 50 ms |
| `perf.content_load_ms` | Cold content catalog load completes in under 750 ms |
| `perf.node_count_after_build` | A built dungeon has fewer than 8000 nodes |
| `perf.static_memory_after_build` | `Performance.get_monitor(MEMORY_STATIC)` stays under a recorded ceiling |
| `perf.frame_time_ms` | `skip` with the reason "GPU frame time requires an in-editor profiling harness" |

Budgets are asserted against constants in the suite, and a companion `--baseline` mode writes the measured values to `user://perf_baseline.json` so the numbers can be re-derived on new hardware rather than guessed.

- `m7.steam.achievement_sync_stub` and `m7.steam.auth_ticket_deferred` (`m7_suite.gd:392-410`) are replaced wholesale by `platform_suite.gd`.
- The 15 `has_method` checks in `m7_suite.gd` each become a call plus an assertion on the return value, or move to the owning subsystem suite.

Not every grep is worth converting. Asserting that `.github/workflows/release.yml` exists and mentions `ghcr.io` is a legitimate textual check, because the artifact under test is text. The rule is about assertions on runtime behavior, not assertions on files.

### 4. Reorganize by subsystem (VSU-06)

Dissolve `m5_suite`, `m6_suite`, and `m7_suite`. Their 142 assertions move to the suite that owns the behavior:

| From | To |
|------|-----|
| Biome registration, lighting, theme bosses | `biome_suite.gd` (new) |
| Damage types, resistances, statuses | `combat_suite.gd` |
| Loadout gates, unlock thresholds, talents | `progression_suite.gd` |
| Tier gates, floor and tier seed derivation, secrets cap, final floor | `procgen_suite.gd` |
| Endless mode, waves mode, run modes, retreat, portals | `run_mode_suite.gd` (new) |
| Rarity, global drops, affix caps, blacksmith | `loot_suite.gd` (new) |
| Achievements, leaderboard settings | `meta_suite.gd` (new) |
| Accessibility | `a11y_suite.gd` |
| Steam | `platform_suite.gd` |
| Save migration | `save_suite.gd` |
| CI workflow and documentation checks | `docs_suite.gd` |
| Hub portals and tutorial | `hub_suite.gd` |

Test ids are renamed to `<subsystem>.<area>.<case>` with no milestone prefix. That is a large mechanical rename; do it one source suite at a time, and keep an id-mapping table in the pull request so historical report comparison remains possible.

Milestone tracking moves to `checklist_ref`, which already exists on every record and is the right place for it.

### 5. Determinism beyond two seeds (VSU-08)

Replace the `SEED_A`/`SEED_B` pair with a generated sweep:

```gdscript
const DETERMINISM_SEEDS := [1, 2, 42001, 99999, 2147483647]
const SWEEP_COUNT := 25  # derived from a fixed base so runs are reproducible

func _sweep_seeds() -> Array[int]:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20260805
    var out: Array[int] = DETERMINISM_SEEDS.duplicate()
    for _i in SWEEP_COUNT:
        out.append(rng.randi_range(1, 2147483647))
    return out
```

For each seed: generate twice and assert byte-identical layout signatures, assert the room count is within the configured bounds, assert the critical path from entrance to boss is connected, and assert that every placement lands inside a room. Boundary seeds 1 and `int32` max are explicit members because off-by-one seed derivation bugs cluster there.

The same sweep runs on the C# side through `cross_stack_parity_suite`, comparing the GDScript layout signature against a fixture generated by `tools/procgen-cli`, which extends the four-assertion parity surface (VSU-11) into a real contract test. Generate the fixtures in CI rather than committing them, so the comparison is always against the current C# code.

### 6. Error paths (VSU-09)

`error_paths_suite.gd` asserts recovery, not just absence of crash:

| Test id | Scenario | Expected |
|---------|----------|----------|
| `error.save.corrupt_json_recovers` | Write garbage to `user://aumbrye_save.json`, load | Defaults applied, backup taken, no crash |
| `error.save.truncated_json_recovers` | Half a valid document | Same |
| `error.save.unwritable_directory` | Read-only save path | Failure surfaced through `CrashLogger`, game continues |
| `error.content.missing_item_id` | Inventory slot referencing an unknown item | Slot dropped, warning logged, inventory usable |
| `error.content.missing_content_file` | Rename a required catalog file | Startup reports the missing file rather than failing silently |
| `error.procgen.malformed_definition` | Definition with a room missing `transform` | Builder rejects with a message, no partial scene |
| `error.procgen.unreachable_boss` | Definition whose boss room has no inbound edge | Validation rejects |
| `error.migration.future_schema_version` | Save with `schemaVersion` above current | Refused rather than silently downgraded |

These are the tests that determine whether a player loses a save.

### 7. Input and UI coverage (VSU-13, VSU-14)

`ui_suite.gd` drives real `Control` trees:

- Instantiate each menu scene, call `grab_focus` on the first control, send `ui_down` through `Input.parse_input_event` the number of times equal to the focusable count, and assert focus returns to the first control — a closed focus ring with no dead ends.
- Assert every `Button`, `CheckBox`, `Slider`, and `OptionButton` has `focus_mode != FOCUS_NONE` and a non-empty accessible name.
- Assert the pause menu opens on `pause` and closes on `pause`, and that the tree is actually paused in between.
- Assert the inventory grid moves the selection with the four directional actions and wraps at the edges.

Input simulation with `Input.parse_input_event` works headless as long as the scene is in the tree and a frame is awaited; that is the same mechanism the existing behavioral suites already use for physics.

### 8. Category hygiene (VSU-15, VSU-12)

`pixel_pipeline_suite` and `diorama_anim_suite` both report `graphics`. Split into `pixel_pipeline` and `diorama_anim` so the per-suite report groups correctly.

Remove `ctx.eval_continuable`, `ctx.player_snapshot_allowed`, and `ctx.parse_castle_seed` per [`validation-harness.md`](validation-harness.md) step 9, and repoint `save_suite` and `hub_suite` at the production functions. Where the production function is not callable from a test, extract it; a rule worth testing is a rule worth exposing.

### 9. Duplicate ids (VSU-07)

Loops that record must suffix the id with the loop discriminator: `lock_on.auto_advance_on_death.melee`, `.ranged`, `.shielded`, `.knight`. The harness's duplicate detection from [`validation-harness.md`](validation-harness.md) step 6 turns any remaining collision into a failure.

## Work plan

1. **Green the baseline** — repoint four documentation assertions, delete two, deduplicate one. (VSU-01)
2. **Add `docs_suite.gd`** with the link and referenced-path checks. (VSU-01)
3. **Suffix looped test ids.** (VSU-07)
4. **Split the two `graphics` categories.** (VSU-15)
5. **Add `net_suite.gd`** as specified in [`networking.md`](networking.md), landing with the NET-01 fix. (VSU-02)
6. **Add `platform_suite.gd`** and delete the three `m7.steam.*` tests. (VSU-10, VSU-16)
7. **Add `export_suite.gd`** as specified in [`export-tools.md`](export-tools.md). (VSU-10)
8. **Replace `perf_gate_suite`** with the seven real budgets plus the `--baseline` mode. (VSU-05)
9. **Convert `perf.vfx_burst_pool` and the 15 `m7` `has_method` checks** to behavioral assertions. (VSU-03, VSU-04)
10. **Add `error_paths_suite.gd`.** (VSU-09)
11. **Add the determinism sweep** to `procgen_suite` and `room_graph_suite`, and the CLI-fixture comparison to `cross_stack_parity_suite`. (VSU-08, VSU-11)
12. **Add `ui_suite.gd` and `a11y_suite.gd`.** (VSU-13, VSU-14)
13. **Add `debug_suite.gd`.** (VSU-10)
14. **Dissolve `m5_suite`, `m6_suite`, and `m7_suite`** into subsystem suites, one source suite per pull request, with an id-mapping table. (VSU-06)
15. **Remove the `TestContext` rule copies** and repoint `save_suite` and `hub_suite`. (VSU-12)
16. **Turn on the reachability metric** from [`validation-harness.md`](validation-harness.md) and drive the remaining holes from its output. (VSU-17)

Steps 1-4 are small and unblock honest signal. Steps 5-7 depend on the corresponding subsystem work. Step 14 is the largest and should come after the harness gains filtering (`--suite`), so a partially migrated tree stays workable.

## Data and schema changes

No `content/schemas/` change. No save-format change, so **no `save_migrator.gd` version bump** — `error_paths_suite` writes and restores save files but round-trips them through `TestContext`'s backup helpers.

New tracked files under `apps/game/client/scripts/validation/suites/`: `docs_suite.gd`, `net_suite.gd`, `platform_suite.gd`, `export_suite.gd`, `harness_suite.gd`, `debug_suite.gd`, `ui_suite.gd`, `a11y_suite.gd`, `error_paths_suite.gd`, and later `biome_suite.gd`, `run_mode_suite.gd`, `loot_suite.gd`, `meta_suite.gd`. Each needs a `SUITE_PATHS` entry.

Removed after step 14: `m5_suite.gd`, `m6_suite.gd`, `m7_suite.gd`.

New generated file: `user://perf_baseline.json`, written only under `--baseline`, never committed.

New documentation file: `docs/validation/manual-checklist.md`, created by [`validation-harness.md`](validation-harness.md) step 10 and referenced by `m7.ship.manual_checklist`.

Test ids change in step 14. Any external consumer of `mcp_validation.json` keyed on the `m5.`, `m6.`, or `m7.` prefixes breaks; the only known consumer is the stale `reports/validation-summary.json` artifact described in [`repository-root.md`](repository-root.md), which is untracked and already out of date.

## Acceptance criteria

- [ ] A clean checkout runs the full validation with zero failures.
- [ ] No test asserts the existence of a documentation file that is not also link-checked by `docs_suite`.
- [ ] A pull request that deletes a documentation file referenced by a test fails `docs_suite`, not seven unrelated tests.
- [ ] `net_suite`, `platform_suite`, and `export_suite` exist, are registered, and pass with no network and no Steam.
- [ ] The NET-01 cloud-save bug, reintroduced deliberately, fails `net.transport.get_returns_body_key`.
- [ ] `perf_gate_suite` measures seven real budgets; deliberately adding a 2-second sleep to dungeon build fails `perf.dungeon_build_ms`.
- [ ] `perf.frame_time_ms` reports `skip`, not `pass`.
- [ ] Emptying the body of `VfxService._acquire_burst` fails `perf.vfx_burst_pool`.
- [ ] Corrupting `user://aumbrye_save.json` and launching recovers to defaults with a backup, asserted by `error_paths_suite`.
- [ ] The determinism sweep covers at least 30 seeds including 1 and `int32` max, and passes.
- [ ] `cross_stack_parity_suite` compares the GDScript layout signature against a fixture generated by `tools/procgen-cli` in the same CI run.
- [ ] Every menu scene has a closed focus ring, asserted by `ui_suite`.
- [ ] Every interactive `Control` has a focus mode and an accessible name.
- [ ] No `m5.`, `m6.`, or `m7.` prefixed test id remains.
- [ ] No two records share a test id.
- [ ] `pixel_pipeline` and `diorama_anim` report distinct categories.
- [ ] `TestContext` contains no game-rule reimplementation and `save_suite`/`hub_suite` call production code.
- [ ] The reachability metric reports above 70 percent of `apps/game/client/scripts/**/*.gd` referenced by at least one suite.

## Validation

This plan is itself about tests, so validation is meta: the guards that keep the suite honest.

| Test id | Suite | Asserts |
|---------|-------|---------|
| `harness.registration.every_suite_file_is_registered` | `harness_suite` | On-disk and registered suite sets are identical, in both directions |
| `harness.record.duplicate_id_is_reported` | `harness_suite` | A collision fails rather than silently appending |
| `docs.referenced_paths_exist` | `docs_suite` | Every documentation path referenced by any suite resolves |
| `docs.relative_links_resolve` | `docs_suite` | Every relative link under `docs/existing_codebase/` and `docs/actual_improvements/` resolves |
| `docs.checklist_refs_resolve` | `docs_suite` | Every `checklist_ref` has a heading in `docs/validation/manual-checklist.md` |
| `harness.reachability.reports_untested_scripts` | `harness_suite` | The metric is computed and the report lists the unreferenced files by path |

CI additions, specified in [`ci-cd.md`](ci-cd.md): upload `mcp_validation.json` and `mcp_validation.xml` always, write every failing id and message to the job summary, and set `timeout-minutes: 30` on the `godot` job.

Mutation spot-checks, performed once per quarter by hand rather than automated: delete the body of five randomly chosen production functions that suites claim to cover and confirm the corresponding test fails. Any that still passes is a grep assertion that survived step 9.

## Related

- Existing behavior: [`../existing_codebase/validation-suites.md`](../existing_codebase/validation-suites.md)
- [`validation-harness.md`](validation-harness.md) — filtering, timeouts, assertions, registration parity
- [`networking.md`](networking.md) — `net_suite.gd`
- [`platform-and-net.md`](platform-and-net.md) — `platform_suite.gd`
- [`export-tools.md`](export-tools.md) — `export_suite.gd`
- [`ci-cd.md`](ci-cd.md) — artifact upload, failure summary, job timeout
- [`repository-root.md`](repository-root.md) — the missing documentation paths and the stale report artifact
- [`combat-validation.md`](combat-validation.md) — combat assertions, owned separately
