# Local procgen

`LocalProcgen` is the single entry point every client run uses to obtain a `DungeonDefinition`. It derives the per-floor seed, calls the GDScript two-phase generator, and falls back to the C# `procgen-cli` process only if the GDScript path returns no rooms. It is on the live play path: `RunFlow._generate_dungeon()` calls it for every floor of every mode.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/local_procgen.gd` | Seed resolution, GDScript-first generation, CLI fallback, result envelope |
| `apps/game/client/scripts/dungeon/dungeon_seed_service.gd` | base seed -> tier seed -> floor seed derivation, tier access gate |
| `apps/game/client/scripts/dungeon/procgen/dungeon_procgen.gd` | The GDScript generator itself (see [`room-graph-procgen.md`](room-graph-procgen.md)) |
| `tools/procgen-cli/Program.cs` | Fallback CLI over `packages/procedural` |

## How it works

Entry point is `LocalProcgen.generate()` (`local_procgen.gd:14`), signature
`generate(biome_id := "forgotten_castle", run_seed: Variant = null, floor_index := 1, run_mode := "castle", dungeon_tier := 1, player_level := 1, debug_ascii := false)`.

1. **Seed resolution.** `_resolve_seed()` (`local_procgen.gd:141`) returns `maxi(1, int(run_seed))` for an explicit seed, otherwise `randi_range(1, 2_147_483_646)`. A rolled seed is printed as `[LocalProcgen] Rolled seed: %d` (`local_procgen.gd:25`). Godot's global RNG is not seeded here, so a rolled seed is not reproducible across sessions.
2. **Tier gate.** `DungeonSeedService.can_access_tier(dungeon_tier)` is checked **only when `run_seed != null`** (`local_procgen.gd:26`). A locked tier entered without a typed seed is not rejected here; `RunFlow.start_run_with_seed()` performs the same conditional check at `run_flow.gd:84`.
3. **Seed derivation.** `tier_seed = DungeonSeedService.derive_tier_seed(base_seed, dungeon_tier)` (`local_procgen.gd:31`), then `floor_seed = DungeonSeedService.mix_floor_seed(tier_seed, floor_index)` (`local_procgen.gd:32`).
4. **Final-floor flag.** `is_final = RunFloorConfig.is_final_floor(floor_index, run_mode)` (`local_procgen.gd:33`) — true only when `run_mode != "endless"` and the clamped floor is >= `RunFloorConfig.MAX_FLOORS` (10).
5. **GDScript generation.** `DungeonProcgen.generate(biome_id, floor_seed, maxi(1, dungeon_tier), maxi(1, player_level), floor_index, is_final, debug_ascii)` (`local_procgen.gd:35`). The result is accepted only if `ok` is true **and** `definition.rooms` is non-empty (`local_procgen.gd:46`).
6. **CLI fallback.** If the GDScript result is rejected, `_generate_via_cli()` (`local_procgen.gd:68`) runs the C# generator. Note it is passed `tier_seed`, not `floor_seed` — the C# side re-applies the same `seed + floorIndex * 7919` mix (`DungeonGenerator.cs:42`), so the effective seed matches.

### Seed math

| Function | Formula | Evidence |
|----------|---------|----------|
| `derive_tier_seed(base, tier)` | `tier <= 1` -> `base`; else `maxi(1, base ^ (clampi(tier,1,DungeonCatalog.count()) * 104729))` | `dungeon_seed_service.gd:10-16` |
| `mix_floor_seed(tier_seed, floor)` | delegates to `RunFloorConfig.mix_seed` | `dungeon_seed_service.gd:19` |
| `RunFloorConfig.mix_seed(seed, floor)` | `floor <= 1` -> `seed`; else `maxi(1, seed + floor * 7919)` | `run_floor_config.gd:14-18` |
| `generation_seed(base, tier, floor)` | `mix_floor_seed(derive_tier_seed(base, tier), floor)` | `dungeon_seed_service.gd:23` |

`DungeonSeedService.TIER_SEED_MULTIPLIER := 104729` (`dungeon_seed_service.gd:6`) is used. `DungeonSeedService.FLOOR_SEED_MULTIPLIER := 7919` (`dungeon_seed_service.gd:7`) is never read — the value actually used is `RunFloorConfig.FLOOR_SEED_MULTIPLIER` (`run_floor_config.gd:9`).

Because `mix_seed` adds rather than hashes, floor seeds inside one tier are `tier_seed + 7919*n` — an arithmetic progression, not a decorrelated sequence.

### CLI invocation

`_resolve_cli_invocation()` (`local_procgen.gd:151`) probes, in order:

1. `tools/procgen-cli/publish/procgen-cli.exe`
2. `tools/procgen-cli/bin/Debug/net8.0/procgen-cli.exe`
3. `dotnet run --project tools/procgen-cli/ProcgenCli.csproj --`

Repo root is `ContentLoader.content_path("content").get_base_dir()` (`local_procgen.gd:147`). If none resolve, the error string is `"Local dungeon generator not found. Build with: dotnet build tools/procgen-cli/ProcgenCli.csproj"` (`local_procgen.gd:80-83`).

Arguments built at `local_procgen.gd:86-98`: `generate <biomeId> <tier_seed>` then either `--final-floor` or `--floor <n>`, then `--tier <n> --player-level <n>`. The optional `runId` positional argument is **never** supplied, so `Program.cs:45` falls back to `Guid.NewGuid()`; CLI output therefore has a different `runId` (and different `checksum`) on every invocation for the same seed. When `--final-floor` is used, `--floor` is omitted, so the CLI reports `floorIndex: 1` even on floor 10 (`Program.cs:48`).

`OS.execute` is called blocking with `read_stderr = true, open_console = false` (`local_procgen.gd:101`). Output is joined (`_join_output`, `local_procgen.gd:170`) and everything before the first `{` is stripped by `_extract_json_text` (`local_procgen.gd:177`) before `JSON.parse_string`.

## Contracts

Result dictionary from the GDScript path (`local_procgen.gd:47-56`):

| Key | Type | Meaning |
|-----|------|---------|
| `ok` | bool | Generation succeeded |
| `definition` | Dictionary | The `DungeonDefinition` |
| `input_seed` | int | Base run seed (what the player typed or what was rolled) |
| `tier_seed` | int | After `derive_tier_seed` |
| `generation_seed` | int | The floor seed actually fed to the generator |
| `floor_index` | int | Echoed floor |
| `run_id` | String | Deterministic UUID-shaped id from `DungeonProcgen._deterministic_run_id` |
| `generator` | String | `"gdscript"` or `"cli"` |

Failure envelope is `{"ok": false, "error": String}` (`local_procgen.gd:27-30`, `78-84`, `111-114`, `118`, `122`, `126`, `130`).

Consumers: `RunFlow` reads `definition`, `run_id`, `input_seed`, `generation_seed` (`run_flow.gd:160-165`); it does not read `generator`, so a silent CLI fallback is invisible to the player and to the save file.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| GDScript primary generation | IMPLEMENTED | `local_procgen.gd:35-56` |
| Rolled-seed reproducibility | PARTIAL | `_resolve_seed` uses unseeded `randi_range` (`local_procgen.gd:144`) |
| Tier access gate | PARTIAL | Only enforced when `run_seed != null` (`local_procgen.gd:26`) |
| CLI fallback determinism | BROKEN | `runId` is `Guid.NewGuid()` because `LocalProcgen` never passes one (`Program.cs:45`) |
| CLI fallback content parity | BROKEN | C# emits `roomContent`/`locks`/`puzzles` as empty arrays (`DungeonGenerator.cs:122-124`), so a CLI floor has no keys, locked doors, or room content |
| CLI final-floor floor index | BROKEN | `--floor` omitted when `--final-floor` is passed (`local_procgen.gd:90-94`) |
| Floor-seed decorrelation | PARTIAL | `mix_seed` is additive (`run_floor_config.gd:17`) |
| `DungeonSeedService.FLOOR_SEED_MULTIPLIER` | STUB | Declared, no reader (`dungeon_seed_service.gd:7`) |
| Generator provenance in results/save | ABSENT | `generator` key is set but never read; searched `run_flow.gd`, `castle_run.gd`, `local_save.gd` |
| Schema validation of the produced definition | ABSENT | `scripts/validate-content/validate.mjs:70` only validates `content/fixtures/*` |

## Related

- Improvement plan: [`../actual_improvements/local-procgen.md`](../actual_improvements/local-procgen.md)
- [`room-graph-procgen.md`](room-graph-procgen.md) — the generator this wraps
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) — tier unlocks and floor config
- [`run-flow.md`](run-flow.md) — caller
- [`packages.md`](packages.md) — the C# `packages/procedural` assembly
