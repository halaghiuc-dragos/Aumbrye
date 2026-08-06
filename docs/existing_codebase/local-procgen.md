# Local procgen

`LocalProcgen` is the single entry point every client run uses to obtain a `DungeonDefinition`. It derives per-floor seeds, runs the GDScript two-phase generator with a three-attempt retry ladder and `DungeonDefinitionValidator`, and only reaches for the C# `procgen-cli` when `allow_cli_fallback == true` (tooling / parity tests only). It is on the live play path: `RunFlow._generate_dungeon()` calls it for every floor of every mode.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/local_procgen.gd` | Seed resolution, GDScript generation, optional CLI, result envelope |
| `apps/game/client/scripts/dungeon/dungeon_definition_validator.gd` | Structural `DungeonDefinition` validation gate (LPG-02) |
| `apps/game/client/scripts/dungeon/dungeon_seed_service.gd` | Base seed â†’ tier seed â†’ floor seed derivation, tier access gate |
| `apps/game/client/scripts/dungeon/run_floor_config.gd` | `mix_seed` (SplitMix64 via `floor_seed_mix.gd`), floor caps |
| `apps/game/client/scripts/dungeon/floor_seed_mix.gd` | uint64-safe `FloorSeedMix.mix` shared by `RunFloorConfig` |
| `apps/game/client/scripts/dungeon/procgen/dungeon_procgen.gd` | GDScript generator; public `deterministic_run_id()` |
| `packages/procedural/Generation/DungeonSeedDeriver.cs` | C# `MixFloorSeed` parity with GDScript |
| `tools/procgen-cli/Program.cs` | CLI `generate`, `mix-seed-table`, `room-kit-specs` |

## How it works

Entry point is `LocalProcgen.generate()` (`local_procgen.gd:14`), signature
`generate(biome_id := "forgotten_castle", run_seed: Variant = null, floor_index := 1, run_mode := "castle", dungeon_tier := 1, player_level := 1, debug_ascii := false, allow_cli_fallback := false, bypass_tier_lock := false)`.

1. **Seed resolution.** `_resolve_seed()` (`local_procgen.gd:168`) returns `maxi(1, int(run_seed))` for an explicit seed; otherwise seeds a `RandomNumberGenerator` with `int(Time.get_unix_time_from_system() * 1000.0) ^ OS.get_process_id()` and rolls `randi_range(1, 2_147_483_646)`. Rolled seeds print as `[LocalProcgen] Rolled seed: %d` (`local_procgen.gd:27`).
2. **Tier gate.** `DungeonSeedService.can_access_tier(dungeon_tier)` runs unconditionally unless `bypass_tier_lock` is true (`local_procgen.gd:29-34`). `RunFlow.start_new_run()` also checks tier access before starting (`run_flow.gd:99`).
3. **Seed derivation.** `tier_seed = DungeonSeedService.derive_tier_seed(base_seed, dungeon_tier)` (`local_procgen.gd:35`), then `floor_seed = DungeonSeedService.mix_floor_seed(tier_seed, floor_index)` via `RunFloorConfig.mix_seed` â†’ `FloorSeedMix.mix` (`local_procgen.gd:36`).
4. **Final-floor flag.** `is_final = RunFloorConfig.is_final_floor(floor_index, run_mode)` (`local_procgen.gd:37`).
5. **GDScript generation + validation.** Up to three attempts with salts `[0, 0x9E3779B9, 0x85EBCA6B]` XORed into `floor_seed` (`local_procgen.gd:40-76`). Each success path runs `DungeonDefinitionValidator.validate()`; failures record `RoomGraphGenerator.last_validate_reason()` when graph generation fails.
6. **CLI fallback (tooling only).** When `allow_cli_fallback == true` and GDScript exhausts retries, `_generate_via_cli()` passes deterministic `run_id`, `--floor <n>`, and optional `--final-floor` (`local_procgen.gd:78-164`). Runtime callers never pass `allow_cli_fallback == true`.

### Seed math

| Function | Formula | Evidence |
|----------|---------|----------|
| `derive_tier_seed(base, tier)` | `tier <= 1` â†’ `base`; else `maxi(1, base ^ (clampi(tier,1,DungeonCatalog.count()) * 104729))` | `dungeon_seed_service.gd:9-15` |
| `mix_floor_seed(tier_seed, floor)` | `RunFloorConfig.mix_seed` â†’ `FloorSeedMix.mix` (SplitMix64; floor 1 identity) | `run_floor_config.gd:14-17`, `floor_seed_mix.gd:6-14` |
| `generation_seed(base, tier, floor)` | `mix_floor_seed(derive_tier_seed(base, tier), floor)` | `dungeon_seed_service.gd:22-23` |
| C# parity | `DungeonSeedDeriver.MixFloorSeed` matches GDScript for 100 fixture rows | `content/fixtures/mix_seed_parity.json`, `cross_stack_parity_suite.gd` |

`DungeonSeedService.TIER_SEED_MULTIPLIER := 104729` (`dungeon_seed_service.gd:6`) is used. `RunFloorConfig.FLOOR_SEED_MULTIPLIER := 7919` (`run_floor_config.gd:9`) is retained for decorrelation tests only.

### CLI invocation

`_resolve_cli_invocation()` (`local_procgen.gd:180`) probes published exe, debug exe, then `dotnet run`. Arguments: `generate <biomeId> <tier_seed> <run_id> --floor <n> [--final-floor] --tier <n> --player-level <n>` (`local_procgen.gd:119-132`). `run_id` is `DungeonProcgen.deterministic_run_id(floor_seed, biome_id, floor_index)`.

## Contracts

Success envelope from the GDScript path (`local_procgen.gd:63-75`):

| Key | Type | Meaning |
|-----|------|---------|
| `ok` | bool | Generation succeeded |
| `definition` | Dictionary | Validated `DungeonDefinition` |
| `input_seed` | int | Base run seed (typed or rolled) |
| `tier_seed` | int | After `derive_tier_seed` |
| `generation_seed` | int | Floor seed fed to the generator |
| `floor_index` | int | Echoed floor |
| `run_id` | String | `DungeonProcgen.deterministic_run_id` |
| `generator` | String | `"gdscript"` or `"cli"` |
| `warnings` | Array | Validator warnings (may be empty) |
| `attempts` | int | Successful attempt index (1â€“3) |

Failure envelope: `{ ok: false, error: "procgen_failed", reason: String, attempts: 3, input_seed, tier_seed, generation_seed }` (`local_procgen.gd:89-96`).

`RunFlow` stores `generator`, `input_seed`, `tier_seed`, `generation_seed`, and `generationWarnings` on the active run snapshot (`run_flow.gd:300-305`, `run_flow.gd:688-693`). On `ok == false` it shows `Floor generation failed â€” seed <n>, reason <r>` and `return_to_hub()` (`run_flow.gd:172-178`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| GDScript primary generation | IMPLEMENTED | `local_procgen.gd:40-76` |
| Definition validation gate | IMPLEMENTED | `dungeon_definition_validator.gd`, `local_procgen.gd:56` |
| Retry ladder (no silent CLI) | IMPLEMENTED | `local_procgen.gd:40-96` |
| Rolled-seed replay | IMPLEMENTED | `_resolve_seed` + `input_seed` in envelope |
| Tier access gate | IMPLEMENTED | unconditional in `local_procgen.gd:29`; `run_flow.gd:99` |
| CLI fallback determinism | IMPLEMENTED | deterministic `run_id` + `--floor` always (`local_procgen.gd:119-132`) |
| CLI fallback content parity | PARTIAL | CLI still omits full `roomContent`/`locks`; runtime never uses CLI |
| Floor-seed decorrelation | IMPLEMENTED | `floor_seed_mix.gd`, `DungeonSeedDeriver.MixFloorSeed` |
| Generator provenance in save | IMPLEMENTED | `run_flow.gd:300-305` |
| Procgen failure UX | IMPLEMENTED | `run_flow.gd:172-178` |

## Related

- Improvement plan: [`../actual_improvements/local-procgen.md`](../actual_improvements/local-procgen.md) - **FINISHED**
- [`room-graph-procgen.md`](room-graph-procgen.md) â€” generator internals
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) â€” tier unlocks
- [`run-flow.md`](run-flow.md) â€” caller and failure UX
- [`packages.md`](packages.md) â€” C# `packages/procedural`
