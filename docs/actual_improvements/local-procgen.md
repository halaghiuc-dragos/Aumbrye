# Local procgen — improvement plan

## Current state

`LocalProcgen.generate()` derives `base -> tier -> floor` seeds, calls the GDScript `DungeonProcgen`, and silently falls back to the C# `procgen-cli` when the GDScript result has no rooms (`local_procgen.gd:35-66`). The fallback is not equivalent: the C# generator returns empty `roomContent`, `locks`, and `puzzles` (`DungeonGenerator.cs:122-124`), so a fallback floor loses every locked door, key, and content-typed room, and the player is never told. Rolled seeds come from an unseeded `randi_range` (`local_procgen.gd:144`) and are not reproducible. See [`../existing_codebase/local-procgen.md`](../existing_codebase/local-procgen.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| LPG-01 | P0 | CLI fallback produces a structurally poorer floor (no `roomContent`, `locks`, `puzzles`) and the swap is invisible to caller, HUD, and save | `local_procgen.gd:57-66`, `DungeonGenerator.cs:122-124` |
| LPG-02 | P0 | No validation of the generated `DungeonDefinition` before it reaches `DungeonBuilder`; a malformed definition surfaces as a broken level, not an error | `local_procgen.gd:46` accepts on `rooms` non-empty only |
| LPG-03 | P1 | Rolled seed is not reproducible: `randi_range` on the unseeded global RNG | `local_procgen.gd:144` |
| LPG-04 | P1 | Tier access gate is bypassed whenever `run_seed == null` (the normal "start run" path) | `local_procgen.gd:26` |
| LPG-05 | P1 | Floor seeds are an additive progression `tier_seed + floor*7919`, so adjacent floors are correlated inputs | `run_floor_config.gd:17` |
| LPG-06 | P1 | CLI fallback is non-deterministic: `runId` and `checksum` change every call because no `runId` is passed | `local_procgen.gd:86-98`, `Program.cs:45` |
| LPG-07 | P2 | `--final-floor` suppresses `--floor`, so CLI definitions report `floorIndex: 1` on floor 10 | `local_procgen.gd:90-94`, `Program.cs:48` |
| LPG-08 | P2 | `DungeonSeedService.FLOOR_SEED_MULTIPLIER` is declared and never read; the live constant lives in `RunFloorConfig` | `dungeon_seed_service.gd:7` |
| LPG-09 | P2 | `generator` provenance is returned but never stored, so a fallback floor cannot be diagnosed from a bug report | `local_procgen.gd:55`, no reader in `run_flow.gd` |

## Target design

**Chosen approach: GDScript is the only runtime generator; the CLI becomes a tooling/parity target, never a silent runtime substitute.** The alternative — bringing the C# generator to feature parity so the fallback is safe — was rejected because it doubles the maintenance surface for the graph, content, and lock systems for a path that fires only on a GDScript bug.

### 1. Fail loudly instead of degrading (LPG-01)

`LocalProcgen.generate()` keeps a retry ladder inside GDScript and never reaches for the CLI:

```
attempt 0: DungeonProcgen.generate(biome, floor_seed, ...)
attempt 1: DungeonProcgen.generate(biome, floor_seed ^ 0x9E3779B9, ...)   # seed salvage
attempt 2: DungeonProcgen.generate(biome, floor_seed ^ 0x85EBCA6B, ...)
fail:      { ok = false, error = "procgen_failed", attempts = 3, reason = <last validate reason> }
```

Each retry is deterministic (fixed salt constants), so the same input seed still yields the same output. `reason` is `RoomGraphGenerator.last_validate_reason()` (a new public accessor for `_last_validate_reason`, `room_graph_generator.gd:31`).

`generate()` gains a `allow_cli_fallback := false` parameter. Only `tools/`-facing callers and `cross_stack_parity_suite.gd` pass `true`.

`RunFlow` must surface the failure: on `ok == false` it shows a modal ("Floor generation failed — seed <n>, reason <r>") and returns to the hub rather than building an empty level.

### 2. Definition validation gate (LPG-02)

Add `apps/game/client/scripts/dungeon/dungeon_definition_validator.gd` (`class_name DungeonDefinitionValidator`), pure static, no scene dependencies:

```gdscript
static func validate(definition: Dictionary) -> Dictionary
# -> { ok: bool, errors: Array[String], warnings: Array[String] }
```

Checks, in order, each producing a stable error code string:

| Code | Condition |
|------|-----------|
| `schema_version` | `schemaVersion == 1` |
| `required_keys` | `runId`, `seed`, `biomeId`, `tier`, `playerLevelSnapshot`, `rooms`, `edges`, `placements`, `budgets` present |
| `room_ids_unique` | no duplicate `rooms[].id` |
| `room_template_resolves` | every `rooms[].templateId` resolves through `BiomeRegistry.get_room_scene()` |
| `edge_endpoints_exist` | every `edges[].from`/`to` is a known room id |
| `entrance_present` | exactly one room with `type == "entrance"`, matching `placements.entrance.roomId` |
| `boss_present` | exactly one `type == "boss"` room when `placements.boss != null` |
| `exit_reachable` | BFS from entrance over non-`secret` edges reaches `placements.exit.roomId` |
| `locks_solvable` | `RoomContentValidator.validate()` returns `ok` |
| `no_room_overlap` | no two room AABBs (position +- template half-extents) intersect |
| `placement_in_room` | every placement's `roomId` exists |

`LocalProcgen` calls it at `local_procgen.gd:46` in place of the `rooms.is_empty()` check. Errors reject the attempt (feeding the retry ladder); warnings are printed once with the seed.

### 3. Deterministic rolled seeds (LPG-03)

Replace `randi_range` with an explicit generator so the roll is logged and replayable:

```gdscript
static func _resolve_seed(run_seed: Variant) -> int:
    if run_seed != null:
        return maxi(1, int(run_seed))
    var rng := RandomNumberGenerator.new()
    rng.seed = int(Time.get_unix_time_from_system() * 1000.0) ^ OS.get_process_id()
    return rng.randi_range(1, 2_147_483_646)
```

`RunFlow` already stores `input_seed`; the acceptance criterion is that re-entering that number reproduces the floor byte-for-byte.

### 4. Unconditional tier gate (LPG-04)

Move the gate above the seed branch (`local_procgen.gd:26`) and drop the `run_seed != null` condition. `DungeonTierService.is_unlocked()` already returns `true` for tier 1, so normal play is unaffected. Debug arenas that need a locked biome pass a new `bypass_tier_lock := false` argument, set only from `scripts/debug/`.

### 5. Hashed floor-seed mixing (LPG-05)

Replace the additive mix in `RunFloorConfig.mix_seed` with a SplitMix64-style finalizer, keeping the `floor <= 1 -> seed` identity so existing floor-1 layouts do not move:

```gdscript
const FLOOR_SEED_MULTIPLIER := 7919   # kept for save compatibility checks

static func mix_seed(seed: int, floor_index: int) -> int:
    if floor_index <= 1:
        return maxi(1, seed)
    var x := (seed * 0x9E3779B1) ^ (floor_index * 0xBF58476D1CE4E5B9)
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9
    x = (x ^ (x >> 27)) * 0x94D049BB133111EB
    x = x ^ (x >> 31)
    return maxi(1, absi(x) & 0x7FFFFFFF)
```

The identical function must be mirrored in `packages/procedural/Generation/DungeonGenerator.cs:42` or the parity suite will fail — that mirroring is the point of the suite.

Delete `DungeonSeedService.FLOOR_SEED_MULTIPLIER` (LPG-08) and keep `RunFloorConfig` as the single owner.

### 6. Deterministic CLI for parity use (LPG-06, LPG-07)

When `allow_cli_fallback` is used by tooling, pass a deterministic run id and always pass `--floor`:

```
generate <biomeId> <tier_seed> <run_id> --floor <n> [--final-floor] --tier <n> --player-level <n>
```

`run_id` is `DungeonProcgen._deterministic_run_id(biome_id, floor_seed, tier)`, promoted to a public static `DungeonProcgen.deterministic_run_id()`. `Program.cs` already accepts a positional `runId` (`Program.cs:45`) and `--floor` and `--final-floor` are independent flags (`Program.cs:48`), so no C# change is needed beyond parity of `mix_seed`.

### 7. Provenance in the run record (LPG-09)

`RunFlow` stores `generator`, `input_seed`, `tier_seed`, `generation_seed`, and validator `warnings` on the active run and writes them into the run snapshot. `docs/existing_codebase/local-save.md` owns the save shape; the addition is additive and needs no migration because unknown keys are ignored on load.

## Work plan

1. **`DungeonDefinitionValidator`** — new file `apps/game/client/scripts/dungeon/dungeon_definition_validator.gd`; the 12 checks above; no other file changes. Landable alone (nothing calls it yet).
2. **Wire the validator + retry ladder** — `local_procgen.gd`: replace the accept check at line 46, add `_attempt_seeds()`, add `allow_cli_fallback` parameter defaulting to `false`, add `reason`/`attempts` to the failure envelope. Add `RoomGraphGenerator.last_validate_reason()` public accessor.
3. **Fail-visible in RunFlow** — `run_flow.gd:160-175`: on `ok == false`, show the failure modal and abort the run instead of continuing.
4. **Seed hygiene** — `_resolve_seed` rewrite (LPG-03); unconditional tier gate with `bypass_tier_lock` (LPG-04).
5. **Hashed floor mix** — `run_floor_config.gd:14-18` and `DungeonGenerator.cs:42` in the same commit; delete `dungeon_seed_service.gd:7`.
6. **Deterministic CLI args** — `local_procgen.gd:86-98`; promote `deterministic_run_id()` in `dungeon_procgen.gd`.
7. **Provenance plumbing** — `run_flow.gd` run record + snapshot keys.

## Data and schema changes

- `content/schemas/dungeon-definition.v1.json` must be reconciled with the fields the generator actually emits before LPG-02's `schema_version` check can be tightened into a full schema check. That reconciliation is owned by [`room-graph-procgen.md`](room-graph-procgen.md) (gap RGP-01) — the validator implemented here duplicates none of it, it checks structural invariants only.
- No new `content/` files. No save-format version bump: the provenance keys in step 7 are additive and `save_migrator.gd` ignores unknown keys.

## Acceptance criteria

- [ ] `LocalProcgen.generate()` never invokes `procgen-cli` unless `allow_cli_fallback == true`, and no runtime caller passes `true` (LPG-01).
- [ ] A definition that fails any `DungeonDefinitionValidator` check is rejected, retried at most twice with the fixed salts, then reported as `{ ok = false, error = "procgen_failed", reason = <string> }` (LPG-02).
- [ ] `RunFlow` shows a failure modal and returns to hub on `ok == false`; it never calls `DungeonBuilder.build()` with an unvalidated definition (LPG-01, LPG-02).
- [ ] Typing the seed printed by `[LocalProcgen] Rolled seed:` reproduces the identical layout signature (LPG-03).
- [ ] Starting a run into a locked tier without typing a seed is rejected with the same error as the typed-seed path (LPG-04).
- [ ] `RunFloorConfig.mix_seed(s, 1) == s` for all `s`, and `mix_seed` output matches `DungeonGenerator.MixFloorSeed` for the 100-value cross product of `s in {1, 2, 12345, 2147483646}` and `floor in 1..25` (LPG-05).
- [ ] Two consecutive CLI invocations with the same arguments produce byte-identical JSON including `runId` and `checksum` (LPG-06).
- [ ] CLI output for `--floor 10 --final-floor` reports `floorIndex: 10` (LPG-07).
- [ ] `DungeonSeedService.FLOOR_SEED_MULTIPLIER` no longer exists (LPG-08).
- [ ] A run snapshot records `generator`, `input_seed`, `tier_seed`, `generation_seed` (LPG-09).

## Validation

Extend `apps/game/client/scripts/validation/suites/procgen_suite.gd`:

- `test_seed_determinism_across_tiers` — for `tier in 1..10`, `LocalProcgen.generate("forgotten_castle", 4242, 1, "castle", tier)` twice; assert equal `TestContext.layout_signature()` and equal `generation_seed`.
- `test_tier_seed_uniqueness` — assert the 10 `derive_tier_seed(4242, t)` values are pairwise distinct.
- `test_floor_seed_identity` — assert `RunFloorConfig.mix_seed(s, 1) == s` for `s in {1, 2, 12345, 2147483646}`.
- `test_floor_seed_decorrelation` — for `floor in 2..25`, assert `absi(mix_seed(s, floor) - mix_seed(s, floor - 1)) != 7919` (proves the additive mix is gone).
- `test_no_silent_cli_fallback` — assert `LocalProcgen.generate(...)["generator"] == "gdscript"` for 50 seeds across all 10 biomes.
- `test_validator_rejects_broken_definitions` — hand-build definitions violating each of `room_ids_unique`, `edge_endpoints_exist`, `exit_reachable`, `no_room_overlap`, `room_template_resolves`; assert `validate().errors` contains the matching code.
- `test_rolled_seed_replay` — call with `run_seed = null`, read `input_seed`, call again with that value, assert identical layout signature.

Extend `apps/game/client/scripts/validation/suites/cross_stack_parity_suite.gd`:

- `test_mix_seed_parity` — table-compare the 100 GDScript/C# `mix_seed` values above (requires the CLI to expose a `mix-seed` verb, or a checked-in fixture generated by CI).
- `test_cli_determinism` — run the CLI twice with a fixed `run_id` and assert identical `checksum`.

Manual: none required; every criterion above is automatable.

## Related

- [`../existing_codebase/local-procgen.md`](../existing_codebase/local-procgen.md)
- [`room-graph-procgen.md`](room-graph-procgen.md) — schema reconciliation (RGP-01) and generator retries
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) — tier unlock source of truth
- [`run-flow.md`](run-flow.md) — failure UX and run record
- [`validation-suites.md`](validation-suites.md)
