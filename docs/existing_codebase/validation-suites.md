# Validation suites

24 suite files in `apps/game/client/scripts/validation/suites/`, all 24 registered in `validation_runner.gd` `SUITE_PATHS`. 304 `ctx.record`/`ctx.timed_record` call sites, some inside loops so the recorded test count is higher. Coverage is broad by subsystem name and thin by depth: roughly a third of the assertions are file-existence checks or substring greps over source text rather than executed behavior.

The harness these run on is documented in [`validation-harness.md`](validation-harness.md).

## Files

All under `apps/game/client/scripts/validation/suites/`. Each has a matching `.gd.uid`.

| Suite | Category | Record call sites | Focus |
|-------|----------|-------------------|-------|
| `setup_suite.gd` | `setup` | 7 | Main scene, autoloads, MCP plugin, input actions |
| `content_suite.gd` | `content` | 9 | Enemy and item JSON, shield stats, folder layout |
| `inventory_suite.gd` | `inventory` | 10 | Grid placement, stacking, equip slots, sort, filter, affix determinism, compare |
| `progression_suite.gd` | `progression` | 7 | XP grant, death XP, relic buffs, talent unlock, CharacterService |
| `procgen_suite.gd` | `procgen` | 13 | Determinism, variation, template mix, offline path, CLI JSON, builder guards |
| `room_graph_suite.gd` | `room_graph` | 7 | Phase-1 graph determinism, ASCII dump, validation, variation, full pipeline |
| `cross_stack_parity_suite.gd` | `cross_stack_parity` | 4 | Biome id prefixes, GDScript-vs-C# schema, affix determinism across stacks |
| `room_content_suite.gd` | `room_content` | 4 | Room type assignment, critical path, definition fields, world-state reset |
| `save_suite.gd` | `save` | 13 | Backup API, continuable-run rules, v1-to-v4 migrations, storage and world flags |
| `hub_suite.gd` | `hub` | 6 | Hub menu buttons, portal and arena, continue enable/disable, seed parsing |
| `hub_m4_suite.gd` | `hub_m4` | 15 | Landmarks, NPCs, collision, dialogue, quests, blacksmith, merchant, storage, portal |
| `arena_suite.gd` | `arena` | 7 | Training dummy, HP bar, return area, walls, duel reset, global controls |
| `camera_suite.gd` | `camera` | 5 | Toggle action, first-person API, overlay hint, persisted preference round trip |
| `lock_on_suite.gd` | `lock_on` | 8 | Center-aim API, first-person policy, reticle source, auto-advance on target death |
| `combat_suite.gd` | `combat` | 13 | Health signals, stamina, poise, guard and parry, hitbox team filter, dodge cost, death guards |
| `dungeon_suite.gd` | `dungeon` | 11 | Build from definition, rooms, enemies, loot, boss door, exit portal, snapshot round trip |
| `player_suite.gd` | `player` | 5 | Facing yaw and direction, sprint constants, combat reactions, weapon controller |
| `flow_suite.gd` | `flow` | 10 | Death and escape API, results UI, offline procgen, continue, portal, loot ids, cloud sync, overlay seed |
| `m5_suite.gd` | `m5` | 35 | Three biomes, six damage types, five statuses, loadout gates, tier gates, theme bosses, audio, epic affixes |
| `m6_suite.gd` | `m6` | 37 | Ten biomes, enemy and boss rosters, item cap, achievements, accessibility, leaderboards, perf docs |
| `m7_suite.gd` | `m7` | 70 | Floor chunking, endless mode, waves mode, rarity, skip items, seeds, final boss, Steam, CI, docs |
| `pixel_pipeline_suite.gd` | `graphics` | 3 (14 recorded) | Pipeline asset paths, two autoload paths, surface shader uniforms |
| `diorama_anim_suite.gd` | `graphics` | 3 | Authored libraries, required clips, controller markers |
| `perf_gate_suite.gd` | `performance` | 2 | VFX pooling substring check, hardcoded frame-budget pass |

**Registered 24, on disk 24.** No unregistered suite exists and no registered path is missing.

## How it works

### Assertion styles

Three styles dominate, in descending order of value.

**Behavioral** — instantiate real nodes or call real service methods and assert on the result. `combat_suite.gd` builds a health component and drives it to zero; `inventory_suite.gd` places, stacks, equips, sorts, and filters through `InventoryService`; `save_suite.gd` runs real payloads through `SaveMigrator`; `dungeon_suite.gd` builds a dungeon from a definition and counts the instantiated rooms, enemies, and chests; `hub_m4_suite.gd` performs blacksmith upgrades, merchant buys and sells, and storage transfers against real services.

**Reflective** — `has_method` on a script or instance. 36 occurrences across 11 suites, 15 of them in `m7_suite.gd`. These prove an API exists and nothing about what it does.

**Textual** — `FileAccess.get_file_as_string(...)` followed by an `in` test, or `ctx.file_contains`. 72 occurrences across 15 suites, 27 of them in `m7_suite.gd`. Plus 44 `FileAccess.file_exists`/`ResourceLoader.exists` calls that assert only that a path resolves.

`perf_gate_suite.gd:19-26` is the clearest example of the textual style:

```gdscript
ctx.timed_record(
    "perf.vfx_burst_pool",
    get_category(),
    "_burst_pool" in text and "_acquire_burst" in text,
    "VfxService pools CPUParticles3D bursts",
    ...
)
```

This passes if those two identifiers appear anywhere in `vfx_service.gd`, including in a comment or a dead branch. It does not verify that pooling works.

### The milestone suites

`m5_suite`, `m6_suite`, and `m7_suite` hold 142 of the 304 call sites, 47 percent. They are organized by delivery milestone rather than by subsystem, so a single suite spans biomes, damage types, save migration, Steam, CI workflow files, and documentation existence. `m7_suite.gd` alone is 964 lines covering floor chunking, endless mode, waves mode, rarity, blacksmith caps, hub portals, global drops, boss phases, Steam stubs, the release workflow, and four documentation files.

The consequence is that a failure in `m7` says nothing about which subsystem broke, and the subsystem suites (`combat`, `player`, `flow`) do not own the behavior their milestone counterparts also assert.

### Documentation assertions

Seven tests assert that a documentation file exists at a repo-root-relative path:

| Test id | Path asserted | On disk |
|---------|---------------|---------|
| `progression.run_economy_doc` | `docs/plan/systems/13-PROGRESSION.md` | **No** |
| `m5.balance.doc_exists` | `docs/plan/systems/24-BALANCING.md` | **No** |
| `m6.balance.doc` | `docs/plan/systems/24-BALANCING.md` | **No** |
| `m6.perf.doc` | `docs/plan/systems/20-PERFORMANCE.md` | **No** |
| `m7.ship.manual_checklist` | `docs/plan/07-EA-DEFINITION-OF-DONE.md` | **No** |
| `m7.schema.migration_doc` | `docs/SAVE_MIGRATIONS.md` | **No** |
| `m7.ship.known_issues_doc` | `docs/design/AUDIT_2026-08.md` | **No** |

All seven paths were checked directly and none exists. Evidence: `progression_suite.gd:86`, `m5_suite.gd:625`, `m6_suite.gd:324,495`, `m7_suite.gd:513,527,952`, resolved through `_content_root()` at `m5_suite.gd:650`, `m6_suite.gd:595`, `m7_suite.gd:963`, all of which point at the repository root. `README.md:62-64` links three of the same missing paths; see [`repository-root.md`](repository-root.md) gap REP-01.

These seven assertions therefore fail on every run, in CI and locally, for reasons unrelated to game code.

### Duplicate test ids

`lock_on_suite.gd` records `lock_on.reticle_uses_center` at both `:47` and `:63`, and `lock_on.auto_advance_on_death` at `:80`, `:104`, `:121`, and `:137`. `save_suite.gd` records `save.zero_hp_not_continuable` (`:88`), `save.valid_midrun_continuable` (`:128`), and `save.player_dead_not_continuable` (`:166`) from inside loops. The harness appends unconditionally (`test_context.gd:110`), so the report contains repeated ids and any consumer keyed on id sees only one of them.

### Fixture sharing

Suites draw shared constants from `TestContext`: `SEED_A` = 42001 and `SEED_B` = 99999 for determinism checks, `FIXTURE_BOSS` for the M2 layout fixture, `REQUIRED_INPUT_ACTIONS`, `REQUIRED_ENEMIES`, `REQUIRED_ITEMS`, `KEY_SCENES`, and `ROOM_TEMPLATE_SCENES`. Several suites assert against `TestContext`'s own reimplementations of game rules rather than production code — `save_suite.gd` uses `ctx.eval_continuable` and `ctx.player_snapshot_allowed` (`test_context.gd:163-182`), `hub_suite.gd` uses `ctx.parse_castle_seed` (`test_context.gd:225-232`). See [`validation-harness.md`](validation-harness.md) gap VHA-12.

### What each suite actually asserts

`setup_suite` — main scene is the hub, the autoload list matches an expected roster including `ApiConfig` (`:27`), the `godot_mcp` plugin is present, and the 13 `REQUIRED_INPUT_ACTIONS` plus arena reset and dodge exist.

`content_suite` — the four `REQUIRED_ENEMIES` and four `REQUIRED_ITEMS` load, shield enemies carry block stats, and item JSON sits in the expected folder layout.

`procgen_suite` — the same seed produces the same layout, different seeds differ, the result is not the M2 fixture, hall or arena templates appear, a random seed works, `run_flow.gd` contains no live API call on the generation path, the CLI JSON has debug fields stripped, `castle_run` has no fixture fallback, placements carry an offset field, and the builder rejects an empty definition.

`cross_stack_parity_suite` — biome id prefixes agree between GDScript and the C# catalog, the GDScript dungeon schema matches the C# one, and affix rolling is deterministic and sourced from the same JSON on both stacks. Four assertions; this is the only suite guarding the client-against-server procgen contract described in [`packages.md`](packages.md).

`save_suite` — backup API exists and is callable, continuable-run rules for mid-run, cleared, zero-HP, empty-snapshot, legacy-no-snapshot, and dead-player cases, v1-to-v2, v2-to-v3, v3-to-v4 migrations plus idempotency, storage payload round trip, and world-flag restore.

`combat_suite` — health configure and signals, stamina consumption, poise break, guard and parry API, hitbox team filtering, dodge stamina cost, weapon hitbox wiring, player hitbox forward direction, shield enemy death guard, death at zero HP, no stagger revive, and hitbox disabled on death.

`dungeon_suite` — a definition builds, rooms instantiate, enemies spawn, loot places, the boss door and exit portal are wired, the room scene registry resolves, and a snapshot captures and restores.

`flow_suite` — death and escape API surface, results outcome UI, offline procgen on the run path, continue and hub API, portal completion, loot id collection on completion, hub cloud sync wiring, debug overlay seed, and the results screen script.

`hub_m4_suite` — the deepest behavioral suite: landmarks, NPC group and count, tent and wall collision, dialogue load and conditions, quest accept and kill tracking, blacksmith upgrade with and without gold, merchant buy and sell, storage transfer, and the always-open portal.

`m5_suite` — three biomes registered with distinct lighting, six damage types with a resistance pipeline and enemy resistance data, five status definitions with burn application and a HUD icon row, loadout level gates and unlock thresholds, hub biome buttons and selection, tier-1 gate and tier-2 unlock, theme boss scenes, audio biome switch, epic affix counts, save integer normalization, a balance doc, and that the online path is optional.

`m6_suite` — ten biomes registered, enemy and boss rosters, item catalog cap, achievement count, service, unique ids, required ids and toast scene, accessibility settings class, damage colors and UI settings, balance and performance docs, M6 theme boss scenes, leaderboard settings, API client wiring and escape submit, enemy pooling, the balance CLI, and escape achievements.

`m7_suite` — the largest, 70 call sites across floor chunking and unload, endless mode constants, difficulty scaling, menu and scene, waves mode scene, milestones, save persistence, isolated inventory, reward and equip UI, lobby ready gate and HUD restore, rarity registry and Aumbral alias, skip items, floor and tier seed derivation, secrets cap, final floor and final boss, stair collision and lever, indoor ceiling lighting, spawn facing, Steam stubs, save migration, controller glyphs, hub tutorial, crash logger, enemy pool, the release workflow file, three documentation files, run-mode helpers, hub portals, global drops, boss phases, retreat API, and the cannon flow.

## Absent

Subsystem directories under `apps/game/client/scripts/` with no dedicated suite and no behavioral coverage:

| Directory | Coverage today |
|-----------|----------------|
| `net/` | None functional. `m6_suite.gd:456` greps `api_client.gd` for a substring; no request, response, or error path is executed. See [`networking.md`](networking.md) NET-11 |
| `platform/` | Three `m7_suite` tests, two of which cannot fail. `crash_logger.gd` has zero tests. See [`platform-and-net.md`](platform-and-net.md) PLT-13, PLT-15 |
| `tools/` | None. The diorama exporter has no test; see [`export-tools.md`](export-tools.md) |
| `debug/` | None. The debug overlay is checked only by a seed-hint substring at `flow_suite.gd:134` |
| `accessibility/` | Class and settings existence only (`m6.a11y.*`), no behavior |
| `audio/` | One test, `m5.audio.set_biome` |
| `ui/` | Scattered scene-existence and button-presence checks; no input-driven UI interaction, no focus traversal, no keyboard navigation |
| `items/`, `loot/` | Catalog counts and global-drop schema only; no drop-rate or roll-distribution assertions |
| `quests/`, `dialogue/`, `npc/` | Only through `hub_m4_suite`, which is genuinely behavioral but hub-scoped |

Test capabilities absent from every suite:

- **Performance measurement.** `perf.headless_budget_gate` passes a literal `true` (`perf_gate_suite.gd:36-38`); nothing samples frame time, memory, load time, or draw calls.
- **Failure and error-path testing.** Nothing asserts what happens on a corrupt save, a missing content file, a malformed dungeon definition beyond the empty case, or a disk-full write.
- **Property-based or fuzz testing.** Determinism checks use two hardcoded seeds, `SEED_A` and `SEED_B`.
- **Visual or screenshot comparison.** No golden images.
- **Input simulation.** No `Input.parse_input_event` driven test; input coverage is action-existence only.
- **Localization.** No suite references translations; see [`project-config-autoloads.md`](project-config-autoloads.md).
- **Multiplayer or networking-layer tests**, because no such code exists.
- **Long-session or soak tests.** Nothing runs more than a few frames.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| VSU-01 | P0 | Seven assertions require documentation files that do not exist, so the suite fails on every run for reasons unrelated to code. | `progression_suite.gd:86`, `m5_suite.gd:625`, `m6_suite.gd:324,495`, `m7_suite.gd:513,527,952`; none of the seven paths exists on disk |
| VSU-02 | P0 | `scripts/net/` has no functional test. The permanently broken `get_save()` body/definition mismatch shipped and stayed. | Only `m6_suite.gd:456` references `ApiClient`, as a substring grep; see [`networking.md`](networking.md) NET-01 |
| VSU-03 | P1 | 72 substring-over-source assertions and 44 path-existence assertions across 15 suites. A comment mentioning the identifier satisfies them; deleting the function body does not. | `perf_gate_suite.gd:19-26` is representative; counts from `FileAccess.get_file_as_string`/`file_contains` and `file_exists`/`ResourceLoader.exists` across `suites/` |
| VSU-04 | P1 | 36 `has_method` assertions prove an API exists and nothing about behavior. 15 are in `m7_suite.gd`. | `has_method(` across `suites/` |
| VSU-05 | P1 | `perf.headless_budget_gate` passes a hardcoded `true`, so the only performance gate in the project cannot fail. | `perf_gate_suite.gd:36-38` |
| VSU-06 | P1 | 47 percent of assertions live in three milestone suites organized by delivery date, not subsystem, so a failure does not localize. `m7_suite.gd` is 964 lines. | `m5_suite.gd`, `m6_suite.gd`, `m7_suite.gd`: 142 of 304 call sites |
| VSU-07 | P1 | Duplicate test ids are recorded from loops, so the report contains repeated ids and any id-keyed consumer loses results. | `lock_on_suite.gd:47,63` and `:80,104,121,137`; `save_suite.gd:88,128,166` |
| VSU-08 | P1 | Determinism is checked against two hardcoded seeds. A seed-dependent generation bug outside 42001 and 99999 is invisible. | `test_context.gd:9-10`; `procgen_suite.gd:48,60`, `room_graph_suite.gd:38,153` |
| VSU-09 | P1 | No error-path or corrupt-input coverage anywhere. Nothing asserts recovery from a corrupt save, a missing content file, or a malformed definition beyond the empty-definition guard. | `procgen_suite.gd:209` is the only negative-input test in the tree |
| VSU-10 | P1 | `crash_logger.gd`, `scripts/tools/`, and `scripts/debug/` have no test of any kind. | No matching test id in `suites/` |
| VSU-11 | P2 | Only four assertions guard the client-against-server procgen contract, which is the correctness boundary that makes server-authoritative runs possible. | `cross_stack_parity_suite.gd:42,63,83,103` |
| VSU-12 | P2 | Several suites assert against `TestContext`'s copies of game rules instead of production code, so production can diverge while the tests pass. | `save_suite.gd` uses `ctx.eval_continuable`/`ctx.player_snapshot_allowed`; `hub_suite.gd` uses `ctx.parse_castle_seed` |
| VSU-13 | P2 | No input simulation. Input coverage is limited to asserting that action names are declared. | `setup_suite.gd:70,80,90`; no `parse_input_event` in `suites/` |
| VSU-14 | P2 | No UI interaction coverage: no focus traversal, no keyboard navigation, no menu-flow test, despite 20-plus UI docs under `docs/existing_codebase/ui/`. | No suite drives a `Control` |
| VSU-15 | P2 | Two suites share the `graphics` category, so the per-suite report groups them under one label alongside distinct concerns. | `pixel_pipeline_suite.gd:5`, `diorama_anim_suite.gd:7` |
| VSU-16 | P2 | `m7.steam.achievement_sync_stub` asserts `synced >= 0` on an `int` and cannot fail; `m7.steam.auth_ticket_deferred` asserts a feature is missing. | `m7_suite.gd:392-410` |
| VSU-17 | P2 | Nothing measures which of the 271 GDScript files are exercised, so the coverage holes above were found by directory inspection, not by the harness. | No instrumentation; see [`validation-harness.md`](validation-harness.md) VHA-18 |

## Related

- Improvement plan: [`../actual_improvements/validation-suites.md`](../actual_improvements/validation-suites.md)
- [`validation-harness.md`](validation-harness.md) — the runner, `TestContext`, and the report
- [`combat-validation.md`](combat-validation.md) — combat assertions in depth
- [`networking.md`](networking.md), [`platform-and-net.md`](platform-and-net.md), [`export-tools.md`](export-tools.md) — the three uncovered subsystems
- [`ci-cd.md`](ci-cd.md) — how these run and why failures are hard to read
- [`repository-root.md`](repository-root.md) — the missing documentation paths
