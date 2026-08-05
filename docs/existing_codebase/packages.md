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
| `Contracts/Runs/RunContracts.cs` | `CreateRunRequest/Response`, `CompleteRunRequest/Response`, `CompleteRunProgressionResponse`, `LootGrantedResponse`, `RunResultRequest` |
| `Contracts/Saves/SaveContracts.cs` | `SaveResponse`, `PutSaveRequest`, `PutSaveResponse` |
| `openapi/aumbrye-api.v1.yaml` | OpenAPI 3.0.3, 8 paths, `bearerAuth` scheme |

### `packages/procedural/`

| Path | Role |
|------|------|
| `Aumbrye.Procedural.csproj` | `net8.0`, references `..\shared\Aumbrye.Shared.csproj` |
| `ProceduralAssembly.cs` | `const string Version = "0.3.0"` |
| `Models/DungeonDefinition.cs` | The 13-field `DungeonDefinition` record plus `DungeonRoom`, `DungeonTransform`, `DungeonEdge`, `DungeonPlacements`, `EnemyPlacement`, `LootPlacement`, `LootItem`, `TrapPlacement`, `SecretPlacement`, `BossPlacement`, `Position3`, `DungeonBudgets` |
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
9. Build `DungeonDefinition`, serialize canonically, extract the checksum back out of the JSON string with a literal `"checksum":"` scan (`DungeonGenerator.cs:130-139`).

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

`ContentPaths.Root` (`Content/ContentPaths.cs:5`) is a static property evaluated once. It prefers `AUMBRYE_CONTENT_ROOT` if set and the directory exists, otherwise walks parent directories from `AppContext.BaseDirectory` looking for a `content` folder, and throws `InvalidOperationException("Could not locate content/ directory.")` if none is found (`ContentPaths.cs:30`). All five catalogs resolve their JSON through it.

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
- **`ProceduralAssembly.Version = "0.3.0"`** and `ApiVersions.ExpectedClientVersion = "0.3.0"` are separate constants that happen to match; nothing enforces that they stay in sync.
- **`Aumbrye.Shared` has zero dependencies**, so it can be referenced from any of the four projects without pulling in EF Core or ASP.NET.
- **Solution membership**: both packages are projects in `services/backend/Aumbrye.sln:18-20`, so `dotnet build Aumbrye.sln` builds them.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| `Aumbrye.Procedural` generation pipeline | IMPLEMENTED | `packages/procedural/Generation/DungeonGenerator.cs:27-128` |
| Deterministic seeding and checksums | IMPLEMENTED | `Random/SeededRandom.cs`, `Serialization/CanonicalJsonSerializer.cs` |
| `Aumbrye.Shared` DTOs | IMPLEMENTED | `packages/shared/Contracts/**` |
| `RoomContent`, `Locks`, `Puzzles` on `DungeonDefinition` | STUB | Always `Array.Empty<object>()` at `Generation/DungeonGenerator.cs:122-124`; serialized as empty arrays at `Serialization/CanonicalJsonSerializer.cs:63-65` |
| `DungeonPlacements.Puzzles` | STUB | Typed `IReadOnlyList<object>` and passed through untouched at `Serialization/CanonicalJsonSerializer.cs:111` |
| `RunResultRequest` DTO | STUB | Declared at `packages/shared/Contracts/Runs/RunContracts.cs:39-46`; no endpoint, service, or test references it |
| `CompleteRunProgressionResponse.CharacterStateJson` | STUB | Declared at `RunContracts.cs:29` with default `null`; the endpoint constructs the record without it (`services/backend/src/Aumbrye.Api/Endpoints/ApiEndpoints.cs:125-137`) |
| `PutSaveResponse.Conflict` | STUB | Declared at `SaveContracts.cs:13` with default `false`; the 409 path returns an anonymous object instead (`ApiEndpoints.cs:197-203`) |
| Leaderboards in the OpenAPI spec | ABSENT | `packages/shared/openapi/aumbrye-api.v1.yaml` declares 8 paths (`:9,15,29,43,57,78,97,120`); `/api/v1/leaderboards` and `/api/v1/leaderboards/submit` are not among them, though both are mapped at `services/backend/src/Aumbrye.Api/Endpoints/LeaderboardsEndpoints.cs:11,35` |
| Leaderboard DTOs in `packages/shared` | ABSENT | `SubmitLeaderboardRequest` is declared in the API project at `LeaderboardsEndpoints.cs:54`, not in `packages/shared/Contracts` |
| Checksum extraction | PARTIAL | `DungeonGenerator.ExtractChecksum` re-parses the serialized string for a literal `"checksum":"` marker instead of using the value `CanonicalJsonSerializer` already computed (`DungeonGenerator.cs:130-139`) |
| OpenAPI response schemas | PARTIAL | Only `SaveResponse` has a `content`/`schema` block (`aumbrye-api.v1.yaml:128-131`); the other 7 paths document status codes with prose descriptions only |
| Generated client from OpenAPI | ABSENT | No NSwag/openapi-generator config, no generated client in `apps/web` or `apps/game/client`; the spec is hand-maintained alongside hand-written clients |

## Related

- Improvement plan: [`../actual_improvements/packages.md`](../actual_improvements/packages.md)
- [`backend-api.md`](backend-api.md) — the API that consumes both packages
- [`website-and-backend.md`](website-and-backend.md) — the OpenAPI contract in use
- [`local-procgen.md`](local-procgen.md) — the GDScript generator this package must stay in parity with
- [`export-tools.md`](export-tools.md), [`tools-scripts.md`](tools-scripts.md) — `procgen-cli`
- [`content-catalog.md`](content-catalog.md) — the `content/` tree the catalogs read
