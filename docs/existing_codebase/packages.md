# Packages

Two C# libraries shared by the API and the CLI: `Aumbrye.Procedural` (dungeon generation, content catalogs, affix rolling) and `Aumbrye.Shared` (API DTOs, version constants, OpenAPI spec). Neither is on the Godot play path — the client generates dungeons in GDScript (`scripts/dungeon/local_procgen.gd`), so these packages are the server/CLI half of a two-stack parity contract.

## Files

### `packages/shared/`

| Path | Role |
|------|------|
| `Aumbrye.Shared.csproj` | `net8.0`, `ImplicitUsings`, `Nullable` enabled, no package references, no project references |
| `Contracts/ApiVersions.cs` | Header names and expected versions |
| `Contracts/HealthResponse.cs` | `record HealthResponse(string Status)` |
| `Contracts/Auth/AuthContracts.cs` | `RegisterRequest`, `LoginRequest`, `RefreshRequest`, `AuthTokensResponse`, `AuthUserResponse`, `AuthResponse` |
| `Contracts/Runs/RunContracts.cs` | `CreateRunRequest/Response`, `CompleteRunRequest/Response`, `CompleteRunProgressionResponse`, `LootGrantedResponse` |
| `Contracts/Saves/SaveContracts.cs` | `SaveResponse`, `PutSaveRequest`, `PutSaveResponse`, `SaveConflictResponse` |
| `Contracts/Leaderboards/LeaderboardContracts.cs` | `SubmitLeaderboardRequest/Response`, `LeaderboardPageResponse`, `LeaderboardEntryResponse` |
| `Contracts/ErrorResponse.cs` | `ErrorResponse(string Error)` |
| `openapi/aumbrye-api.v1.yaml` | OpenAPI 3.0.3, 11 paths; CI-checked against Swashbuckle dump |

### `packages/procedural/`

| Path | Role |
|------|------|
| `Aumbrye.Procedural.csproj` | `net8.0`, references `..\shared\Aumbrye.Shared.csproj` |
| `ProceduralAssembly.cs` | `Version => ApiVersions.ExpectedClientVersion` |
| `Models/DungeonDefinition.cs` | `DungeonDefinition` plus typed `RoomContentEntry`, `DungeonLock`, `DungeonPuzzle` |
| `Generation/DungeonGenerator.cs` | Entry point `Generate(...)`; retry loop; loot instance-id assignment; `GuidExtensions.CreateVersion5` |
| `Generation/DungeonSeedDeriver.cs` | `DeriveTierSeed`, `MixFloorSeed`, `GenerationSeed` |
| `Generation/FinalFloorGenerator.cs` | Separate generator for the final floor |
| `Layout/LayoutGraphGenerator.cs` | `Generate(BiomeLayoutRules, int seed) -> LayoutGraph` |
| `Layout/LayoutModels.cs` | `LayoutNode`, `LayoutEdge`, `LayoutGraph.CanonicalFingerprint()`, `BiomeLayoutRules` |
| `Layout/RoomPlacement.cs` | `BuildRooms`, `ValidateDoorTopology` |
| `Assignment/RoomTypeAssigner.cs` | `Assign(biome, graph, rng) -> RoomAssignmentResult` |
| `Biome/BiomeCatalog.cs` | `GetRequired`, `TryGet` over `content/biomes/` |
| `Biome/BiomeDefinition.cs` | `BiomeDefinition`, `EnemyPoolEntry`, `BossPoolEntry`, `BiomeBudgets` |
| `Biome/RoomTemplateCatalog.cs` | `RoomSpec`, door-mask matching, `PickTemplateForDoors`, `TemplatePrefixForBiome`, yaw helpers |
| `Placement/EnemyPlacer.cs` | Threat-budgeted enemy placement |
| `Placement/LootPlacer.cs` | Chest placement per room type |
| `Placement/ThemeLootTables.cs` | `GetTreasureLoot`, `GetSecretLoot`, `GetSideLoot`, `GetArmoryLoot`, `GetCorridorTrap` per biome |
| `Loot/AffixRoller.cs` | `DeriveRollSeed`, `Roll`, `RollWithSeed`, `IsEquipment`, `ToJsonElement` |
| `Loot/RolledItemInstance.cs` | `RolledAffix`, `RolledItemInstance`, `ItemRarities` |
| `Content/ContentPaths.cs` | Resolves `content/` by walking up from `AppContext.BaseDirectory`, or `AUMBRYE_CONTENT_ROOT` |
| `Content/EnemyCatalog.cs`, `ItemCatalog.cs`, `AffixCatalog.cs`, `ProgressionCatalog.cs`, `TalentCatalog.cs` | Lazy JSON catalog loaders over `content/` |
| `Random/SeededRandom.cs` | SplitMix64 PRNG |
| `Serialization/CanonicalJsonSerializer.cs` | Deterministic key-sorted JSON + SHA-256 checksum |
| `Validation/ConnectivityValidator.cs` | `Validate`, `AreAdjacent`, `BuildAdjacency`, `IsReachable` |

## How it works

### Generation control flow

`DungeonGenerator.Generate(biomeId, seed, tier, playerLevel, runId, floorIndex, isFinalFloor, options)` (`packages/procedural/Generation/DungeonGenerator.cs:27`):

1. If `isFinalFloor`, delegate to `FinalFloorGenerator.Generate` and return.
2. `effectiveSeed = floorIndex <= 1 ? seed : seed + floorIndex * 7919` (`DungeonGenerator.cs:42`).
3. Build `BiomeLayoutRules` from the biome's `RoomCountMin`, `RoomCountMax`, `GridStep` (`DungeonGenerator.cs:43-47`).
4. Retry loop up to `GenerationOptions.MaxAttempts = 48`, adding `SeedOffsetPerAttempt = 1_000_003` per attempt (`DungeonGenerator.cs:17-18,50-62`). On exhaustion, throw `InvalidOperationException` wrapping the last error.

`TryGenerateOnce` (`DungeonGenerator.cs:69`) is one attempt:

1. `LayoutGraphGenerator.Generate(layoutRules, seed)`.
2. `new SeededRandom(seed ^ 0x5EED)` — the placement RNG is deliberately decorrelated from the layout seed (`DungeonGenerator.cs:82`).
3. `RoomTypeAssigner.Assign(biome, graph, rng)`.
4. `RoomPlacement.ValidateDoorTopology(graph, assignment)`.
5. `ConnectivityValidator.Validate(graph, entranceId, bossId, biome.RequiresSecret, secretIds)`; on failure, throw so the retry loop reseeds (`DungeonGenerator.cs:86-93`).
6. `EnemyPlacer.Place` returns placements plus `threatUsed`.
7. `LootPlacer.Place`, then `AssignLootInstanceIds`.
8. `lootValue` summed as `quantity * ItemCatalog.GetLootValue(itemId)` (`DungeonGenerator.cs:105-107`).
9. Build `DungeonDefinition`, serialize via `CanonicalJsonSerializer.Serialize` returning `(json, checksum)`.

### Determinism mechanics

| Mechanism | Detail |
|-----------|--------|
| PRNG | SplitMix64, `_state` seeded from `(ulong)(uint)seed`, zero remapped to `0x9E3779B97F4A7C15` (`Random/SeededRandom.cs:10-15`) |
| Seed derivation | `DeriveTierSeed`: tier 1 returns the base seed; tier >1 returns `max(1, baseSeed ^ (tier * 104729))`. `MixFloorSeed`: floor 1 returns the tier seed; floor >1 returns `max(1, tierSeed + floorIndex * 7919)` (`Generation/DungeonSeedDeriver.cs:12-32`) |
| Loot instance IDs | RFC 4122 v5 UUID over namespace `runId` and name `"{chestId}:{itemId}:{index}"`, SHA-1, with byte-order swaps for .NET GUID layout (`DungeonGenerator.cs:158-190`) |
| Affix roll seed | `AffixRoller.DeriveRollSeed(instanceId)` — the instance ID alone determines the roll (`Loot/AffixRoller.cs:15`) |
| Canonical JSON | Every object is a `SortedDictionary<string, object?>` with `StringComparer.Ordinal`, `WriteIndented = false` (`Serialization/CanonicalJsonSerializer.cs:31-33`) |
| Checksum | SHA-256 hex, lowercase, over the checksum-free canonical JSON, then re-serialized with the checksum key included (`CanonicalJsonSerializer.cs:15-29`) |

### Content loading

`ContentPaths.Root` prefers `AUMBRYE_CONTENT_ROOT`, else walks parents from `AppContext.BaseDirectory`. On failure throws a message naming searched paths and the env override.

### OpenAPI drift check

CI builds the API in Release, runs `dotnet tool run swagger tofile`, and `diff`s against `packages/shared/openapi/aumbrye-api.v1.yaml`.

### Shared contracts

`ApiVersions` (`packages/shared/Contracts/ApiVersions.cs`) declares four constants:

| Constant | Value |
|----------|-------|
| `ClientVersionHeader` | `"X-Client-Version"` |
| `ContentVersionHeader` | `"X-Content-Version"` |
| `ExpectedClientVersion` | `"0.3.0"` |
| `ExpectedContentVersion` | `"1"` |

`VersionHeaderMiddleware` enforces them and the Godot `ApiConfig` sends them; see [`website-and-backend.md`](website-and-backend.md).

## Contracts

- **`content/` is a build-time dependency of `Aumbrye.Procedural`.** The catalogs read JSON at runtime through `ContentPaths`, so publishing the CLI or the API without a sibling `content/` directory throws on first catalog access.
- **`DungeonDefinition` JSON shape** is the cross-stack contract with the GDScript generator; `content/schemas/dungeon-definition.v1.json` is the schema and `cross_stack_parity_suite.gd` asserts parity on prefixes, schema keys, and affix determinism.
- **`ProceduralAssembly.Version`** delegates to `ApiVersions.ExpectedClientVersion`.
- **`Aumbrye.Shared` has zero dependencies**, so it can be referenced from any project without pulling in EF Core or ASP.NET.
- **Solution membership**: both packages are in `services/backend/Aumbrye.sln`; `TreatWarningsAsErrors` enabled on both csprojs.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| `Aumbrye.Procedural` generation pipeline | IMPLEMENTED | `DungeonGenerator.cs` |
| Deterministic seeding and checksums | IMPLEMENTED | `SeededRandom.cs`, `CanonicalJsonSerializer.Serialize` tuple |
| `Aumbrye.Shared` DTOs | IMPLEMENTED | `packages/shared/Contracts/**` |
| Typed `RoomContent` / `Locks` / `Puzzles` | IMPLEMENTED | `RoomContentEntry`, `DungeonLock`, `DungeonPuzzle` in `DungeonDefinition.cs` |
| Leaderboards in OpenAPI + shared DTOs | IMPLEMENTED | `aumbrye-api.v1.yaml`, `LeaderboardContracts.cs` |
| `CompleteRunProgressionResponse.CharacterStateJson` | IMPLEMENTED | populated in `RunService.CompleteRunAsync` |
| `PutSaveResponse` + `SaveConflictResponse` on 409 | IMPLEMENTED | `ApiEndpoints.cs` |
| OpenAPI response schemas | IMPLEMENTED | `.Produces<T>` on all routes; CI swagger diff |
| Generated client from OpenAPI | ABSENT | no NSwag/openapi-generator config in client or web |

## Related

- Improvement plan: [`../actual_improvements/packages.md`](../actual_improvements/packages.md) — **FINISHED**
- [`backend-api.md`](backend-api.md) — the API that consumes both packages
- [`website-and-backend.md`](website-and-backend.md) — the OpenAPI contract in use
- [`local-procgen.md`](local-procgen.md) — the GDScript generator this package must stay in parity with
- [`export-tools.md`](export-tools.md), [`tools-scripts.md`](tools-scripts.md) — `procgen-cli`
- [`content-catalog.md`](content-catalog.md) — the `content/` tree the catalogs read
