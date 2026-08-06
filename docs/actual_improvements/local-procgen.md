# Local procgen — improvement plan

## Status: FINISHED

## Current state

`LocalProcgen.generate()` derives seeds, runs GDScript procgen behind a three-attempt retry ladder and `DungeonDefinitionValidator`, fails loudly with `{ error: "procgen_failed", reason }` when all attempts fail, and only invokes `procgen-cli` when `allow_cli_fallback == true` (tooling / parity only). `RunFlow` surfaces failures to the hub and records generator provenance on the run snapshot. See [`../existing_codebase/local-procgen.md`](../existing_codebase/local-procgen.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| LPG-01 | P0 | CLI fallback produced poorer floors silently | **FINISHED** — retry ladder; `allow_cli_fallback` default false; `RunFlow` aborts on failure (`local_procgen.gd:40-96`, `run_flow.gd:172-178`) |
| LPG-02 | P0 | No definition validation before `DungeonBuilder` | **FINISHED** — `dungeon_definition_validator.gd`; wired at `local_procgen.gd:56` |
| LPG-03 | P1 | Rolled seed not reproducible | **FINISHED** — seeded `RandomNumberGenerator` in `_resolve_seed` (`local_procgen.gd:168-172`); replay via `input_seed` |
| LPG-04 | P1 | Tier gate bypassed when `run_seed == null` | **FINISHED** — unconditional gate + `bypass_tier_lock` for debug (`local_procgen.gd:29-34`) |
| LPG-05 | P1 | Additive floor-seed mix | **FINISHED** — `FloorSeedMix.mix` + `DungeonSeedDeriver.MixFloorSeed`; fixture `content/fixtures/mix_seed_parity.json` |
| LPG-06 | P1 | CLI fallback non-deterministic | **FINISHED** — `deterministic_run_id` passed to CLI (`local_procgen.gd:119-132`) |
| LPG-07 | P2 | `--final-floor` suppressed `--floor` | **FINISHED** — `--floor` always emitted (`local_procgen.gd:125-128`) |
| LPG-08 | P2 | Duplicate `FLOOR_SEED_MULTIPLIER` in `DungeonSeedService` | **FINISHED** — removed from `dungeon_seed_service.gd`; owner is `RunFloorConfig` |
| LPG-09 | P2 | `generator` provenance not stored | **FINISHED** — `run_flow.gd:300-305`, `run_flow.gd:688-693` |

## Target design

**Chosen approach: GDScript is the only runtime generator; the CLI becomes a tooling/parity target, never a silent runtime substitute.**

### 1. Fail loudly instead of degrading (LPG-01)

`LocalProcgen.generate()` retry ladder: base seed, then XOR salts `0x9E3779B9`, `0x85EBCA6B`. Failure returns `{ ok = false, error = "procgen_failed", attempts = 3, reason = <validator or graph reason> }`. `allow_cli_fallback := false` by default.

### 2. Definition validation gate (LPG-02)

`DungeonDefinitionValidator.validate(definition)` — 12 structural checks including `RoomContentValidator.validate_definition()` for `locks_solvable`.

### 3. Deterministic rolled seeds (LPG-03)

`_resolve_seed` uses `RandomNumberGenerator` seeded from wall-clock ms XOR process id; `input_seed` in the envelope enables replay.

### 4. Unconditional tier gate (LPG-04)

`bypass_tier_lock := false` default; set only from debug callers when needed.

### 5. Hashed floor-seed mixing (LPG-05)

`FloorSeedMix.mix` / `DungeonSeedDeriver.MixFloorSeed`; floor 1 identity preserved.

### 6. Deterministic CLI for parity (LPG-06, LPG-07)

CLI receives `run_id` and always `--floor <n>` plus optional `--final-floor`.

### 7. Provenance in the run record (LPG-09)

`generator`, `input_seed`, `tier_seed`, `generation_seed`, `generationWarnings` on active run (additive; no save migrator bump).

## Work plan

1. **`DungeonDefinitionValidator`** — `dungeon_definition_validator.gd` — **DONE**
2. **Wire validator + retry ladder** — `local_procgen.gd`, `room_graph_generator.gd:last_validate_reason()` — **DONE**
3. **Fail-visible in RunFlow** — `run_flow.gd` — **DONE**
4. **Seed hygiene** — `_resolve_seed`, tier gate — **DONE**
5. **Hashed floor mix** — `floor_seed_mix.gd`, `run_floor_config.gd`, `DungeonSeedDeriver.cs`, fixture — **DONE**
6. **Deterministic CLI args** — `local_procgen.gd`, `dungeon_procgen.gd:deterministic_run_id()` — **DONE**
7. **Provenance plumbing** — `run_flow.gd` — **DONE**

## Data and schema changes

- No save-format version bump: provenance keys are additive.
- `content/fixtures/mix_seed_parity.json` regenerated from `procgen-cli mix-seed-table`.

## Acceptance criteria

- [x] `LocalProcgen.generate()` never invokes CLI unless `allow_cli_fallback == true` (LPG-01).
- [x] Failed validation retries with salts, then `{ ok = false, error = "procgen_failed", reason }` (LPG-02).
- [x] `RunFlow` shows failure modal and returns to hub on `ok == false` (LPG-01, LPG-02).
- [x] Replaying `input_seed` reproduces layout signature (LPG-03).
- [x] Locked tier rejected without typed seed (LPG-04).
- [x] `mix_seed(s, 1) == s`; GDScript matches C# fixture for 100 samples (LPG-05).
- [x] CLI duplicate invocations share `runId` and `checksum` (LPG-06).
- [x] CLI `--floor 10 --final-floor` reports `floorIndex: 10` (LPG-07).
- [x] `DungeonSeedService.FLOOR_SEED_MULTIPLIER` removed (LPG-08).
- [x] Run snapshot records `generator`, `input_seed`, `tier_seed`, `generation_seed` (LPG-09).

## Validation

Extended `procgen_suite.gd`: tier determinism, tier seed uniqueness, floor identity/decorrelation, no silent CLI, validator rejection cases, rolled-seed replay.

Extended `cross_stack_parity_suite.gd`: `mix_seed_parity` (fixture), `cli_determinism`.

## Related

- [`../existing_codebase/local-procgen.md`](../existing_codebase/local-procgen.md)
- [`room-graph-procgen.md`](room-graph-procgen.md)
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md)
- [`run-flow.md`](run-flow.md)
- [`validation-suites.md`](validation-suites.md)
