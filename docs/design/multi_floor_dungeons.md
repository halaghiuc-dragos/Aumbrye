# Multi-floor dungeon runs (FLOOR-7.x)

## Overview

EA main mode: **10-floor** dungeon runs per biome. Same run seed across floors; each floor uses a derived procgen seed so layouts differ.

**Umbral Endless** reuses the same floor loop with infinite floors and scaling difficulty (see [ENDLESS](#umbral-endless-mode)).

## Loop change (M7)

| Before | After |
|--------|-------|
| Kill boss → exit portal → hub | Kill floor boss → **stair lever** → next floor |
| Single-floor escape | Escape portal only after **floor 10 final boss** (castle mode) |

## Floor rules

- **Secrets:** max **2** secret rooms per floor (procgen validator + `RunFloorConfig.MAX_SECRETS_PER_FLOOR`).
- **Stairs:** physical collision on stair meshes; `StairLever` in stair room after boss defeat.
- **Ascend:** generates next floor; unloads prior floor chunk; player spawns at top of stairs, facing into the floor.
- **Descend:** regenerate previous floor from seed (castle mode only; **disabled in endless**).
- **Continue:** saves `currentFloor`, `runMode`, `dungeonDefinition` (current floor only), and snapshot.

## Floor chunking (M7 extension)

**Do not load all floors at once.**

| Behavior | Implementation |
|----------|----------------|
| Single active floor | Only current floor nodes exist under the run scene |
| Ascend unload | `RunFlow._unload_current_floor_chunk()` → `DungeonBuilder.unload_from_parent()` |
| No floor blob in save | v3 save drops `floorDefinitions`; layouts derived from `run_seed + floor_index` |
| Regenerate on continue | Same seed + floor index → identical layout |

Applies to **castle** and **endless** modes (`RunModeConfig.is_multi_floor`).

## Floor 10 (final — castle mode only)

1. **Lobby** (`isFinalFloor`): 1 health potion + 1 buff scroll (elixir).
2. **Final boss room:** tougher than theme boss; 3-phase design (Forgotten Castle fully implemented).

### Final boss phases (Forgotten Castle)

1. **Combat** — damage to ~25% HP.
2. **Spikes** — random simultaneous floor spikes; boss immune.
3. **Puzzle** — collect crystals, break shield via cannon pattern; then vulnerable.

Other biomes: document stub pattern in boss JSON; implement post-EA.

## Umbral Endless Mode

Dedicated hub portal starts runs with `runMode: "endless"`.

| Rule | Value |
|------|-------|
| Max floors | `999999` (`RunFloorConfig.ENDLESS_MAX_FLOORS`) |
| Escape portal | None — run ends on death |
| Descend | Disabled |
| Stair lever | Always after floor boss |
| Difficulty tier | `floor_index / 10` |
| Heavy scaling | After floor 10 (`EndlessDifficulty`) |
| Rare drop bonus | +2% per tier, cap 30% |

### Skip-floor consumables

Rare drops from any mode (`content/loot/global_drops.json`). On new endless start, menu prompts optional use:

| Item | Start floor |
|------|-------------|
| `skip_10_floors` | 11 |
| `skip_50_floors` | 51 |
| `skip_100_floors` | 101 |
| `skip_500_floors` | 501 |

Consumed from main inventory via `SkipFloorService`.

## Umbral Waves Mode

Separate single-arena mode — **not multi-floor**. Uses `wavesActiveRun` save block. See `WavesRunService` and `waves_run.tscn`.

## Code map

| Area | Path |
|------|------|
| Run modes | `apps/game/client/scripts/app/run_mode_config.gd` |
| Floor config | `apps/game/client/scripts/dungeon/run_floor_config.gd` |
| Run flow | `apps/game/client/scripts/app/run_flow.gd` |
| Chunk unload | `RunFlow._unload_current_floor_chunk`, `dungeon_builder.gd` |
| Endless scaling | `apps/game/client/scripts/dungeon/endless_difficulty.gd` |
| Skip items | `apps/game/client/scripts/dungeon/skip_floor_service.gd` |
| Waves | `apps/game/client/scripts/dungeon/waves_run_service.gd` |
| Stair lever | `apps/game/client/scripts/dungeon/stair_lever.gd` |
| Procgen floor | `packages/procedural/Generation/DungeonGenerator.cs`, `FinalFloorGenerator.cs` |
| CLI | `tools/procgen-cli` `--floor N`, `--final-floor` |

## Seed derivation

```
floor_seed = run_seed + floor_index * 7919
```

Implemented in `RunFloorConfig.mix_seed` (client) and `DungeonGenerator` (server/offline).

## Save schema (v3)

Active run fields:

- `runMode` — `"castle"` | `"endless"` | `"waves"`
- `currentFloor`, `maxFloors`
- `dungeonDefinition` — **current floor only**
- `snapshot` — player/enemy/loot state

Waves runs additionally use top-level `wavesActiveRun`.
